// 매칭 프록시 — 확정 재료 + 저장 레시피 재료를 단일 프롬프트로 보내 "오늘 할 3개"의 후보를 받는다.
//
// 한국어 동의어·정규화("대파"/"파", "간장"/"진간장")는 프롬프트 안에서 LLM이 처리한다(스펙 #13).
// 부족 4개 이상 제외와 3개 상한은 여기가 아니라 클라이언트가 한다 — 제외 수를 투명성 줄에
// 집계해야 하므로 걸러지기 전의 원본이 앱까지 와야 한다.

const MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';

/// 단가(USD per 1M 토큰) — recognize.mjs와 같은 출처(T1 #6). 모델을 바꾸면 함께 바꾼다.
const PRICE_INPUT_PER_M = Number(process.env.GEMINI_PRICE_INPUT_PER_M ?? 0.25);
const PRICE_OUTPUT_PER_M = Number(process.env.GEMINI_PRICE_OUTPUT_PER_M ?? 1.5);

const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

/// 텍스트 온리 — T1 #6 실측 1.2s.
const UPSTREAM_TIMEOUT_MS = 20_000;

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    suggestions: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          menu: { type: 'STRING' },
          source: { type: 'STRING', enum: ['saved', 'generated'] },
          missing: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                name: { type: 'STRING' },
                substitute: { type: 'STRING' },
              },
              required: ['name'],
            },
          },
          reason: { type: 'STRING' },
        },
        required: ['menu', 'source', 'missing', 'reason'],
      },
    },
  },
  required: ['suggestions'],
};

function promptFor(ingredients, recipes) {
  const savedBlock = recipes.length
    ? recipes
        .map((r) => `- ${r.title}: ${(r.ingredients ?? []).join(', ') || '(재료 미상)'}`)
        .join('\n')
    : '(저장된 레시피 없음)';

  return [
    '지금 냉장고에 있는 재료로 오늘 저녁에 해먹을 메뉴를 골라 주세요.',
    '',
    '## 있는 재료',
    ingredients.join(', ') || '(없음)',
    '',
    '## 사용자가 저장해 둔 레시피 (신뢰하는 것들)',
    savedBlock,
    '',
    '## 규칙',
    '- 저장된 레시피 중에 만들 수 있는 게 있으면 **먼저** 고릅니다. source는 "saved", menu는 저장된 제목 그대로.',
    '- 저장 레시피로 3개가 안 되면 일반적인 한국 가정식으로 채웁니다. source는 "generated".',
    '- 최대 6개까지 후보를 주세요. 고르는 건 앱이 합니다.',
    '- missing에는 그 메뉴에 필요한데 없는 재료만 넣습니다. 있는 재료는 넣지 마세요.',
    '- 있는 재료로 대신할 수 있으면 substitute에 그 재료를 적습니다(예: 우유가 없고 두유가 있으면 name="우유", substitute="두유").',
    '- 대신할 게 없으면 substitute를 비웁니다.',
    '- 한국어 재료명의 동의어와 표기 차이는 같은 것으로 봅니다("대파"="파", "간장"="진간장", "달걀"="계란").',
    '- reason은 왜 이걸 골랐는지 한 줄로. 재료 나열 말고 사람에게 하는 말로.',
  ].join('\n');
}

function readUsage(usageMetadata = {}) {
  const promptTokens = usageMetadata.promptTokenCount ?? 0;
  const outputTokens = usageMetadata.candidatesTokenCount ?? 0;
  const thoughtTokens = usageMetadata.thoughtsTokenCount ?? 0;
  return {
    promptTokens,
    outputTokens,
    thoughtTokens,
    imageTokens: 0,
    model: MODEL,
    costUsd:
      (promptTokens * PRICE_INPUT_PER_M) / 1_000_000 +
      ((outputTokens + thoughtTokens) * PRICE_OUTPUT_PER_M) / 1_000_000,
  };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ message: 'POST만 받습니다' });
  }
  if (!process.env.GEMINI_API_KEY) {
    return res.status(500).json({ message: 'GEMINI_API_KEY가 없습니다' });
  }

  const { ingredients, recipes } = req.body ?? {};
  if (!Array.isArray(ingredients) || ingredients.length === 0) {
    return res.status(400).json({ message: 'ingredients가 필요합니다' });
  }

  let upstream;
  try {
    upstream = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': process.env.GEMINI_API_KEY,
      },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      body: JSON.stringify({
        contents: [
          { parts: [{ text: promptFor(ingredients, recipes ?? []) }] },
        ],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
        },
      }),
    });
  } catch (e) {
    return res.status(502).json({ message: `업스트림 호출 실패: ${e.name}` });
  }

  if (!upstream.ok) {
    return res.status(502).json({ message: `업스트림 ${upstream.status}` });
  }

  const payload = await upstream.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    return res.status(502).json({ message: '업스트림 응답에 본문이 없습니다' });
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return res.status(502).json({ message: '구조화 출력 파싱 실패' });
  }

  return res.status(200).json({
    suggestions: parsed.suggestions ?? [],
    usage: readUsage(payload.usageMetadata),
  });
}

export const __testing = { promptFor, readUsage, RESPONSE_SCHEMA };
