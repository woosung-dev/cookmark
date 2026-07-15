// 재료 인식 프록시 — API 키를 서버에 가두고, 토큰·추정 원가를 앱에 회신한다(스펙 #13).
// 앱과 분리된 서버리스 함수다. 클라이언트는 절대 Gemini를 직접 부르지 않는다.

/// 모델은 환경변수로 주입해 교체 가능하게 둔다(스펙 #13). 파일럿 중에는 바꾸지 않는다.
const MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';

/// 단가(USD per 1M 토큰). gemini-3.1-flash-lite = $0.25 / $1.50 — T1 #6이 공식 가격 페이지에서
/// 확인하고 실측으로 검산한 값이다(1157 in / 295 out → $0.00073).
/// 모델을 바꾸면 이 값도 함께 바꿔야 한다 — 안 바꾸면 원가 로그가 조용히 틀린다.
const PRICE_INPUT_PER_M = Number(process.env.GEMINI_PRICE_INPUT_PER_M ?? 0.25);
const PRICE_OUTPUT_PER_M = Number(process.env.GEMINI_PRICE_OUTPUT_PER_M ?? 1.5);

const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

/// 인식 호출의 상한. 클라이언트도 30초에서 끊지만(G1 #8) 서버가 매달려 있을 이유는 없다.
const UPSTREAM_TIMEOUT_MS = 28_000;

const PROMPT = [
  '이 냉장고 사진에 실제로 보이는 식재료만 한국어로 나열해 주세요.',
  '',
  '규칙:',
  '- 사진에서 보이는 것만 적습니다. 냉장고에 있을 법한 것을 추측해서 넣지 마세요.',
  '- 각 항목에 confidence를 붙입니다. high = 분명히 보임, medium = 보이지만 확실치 않음, low = 있을 수도 있음.',
  '- 용기 안이 안 보이면 추측하지 말고 보이는 그대로("반찬통", "소스류") 적고 confidence를 낮춥니다.',
  '- 사진이 너무 어둡거나 흐려서 판독이 불가능하면 lowQuality를 true로 하고 ingredients를 비웁니다.',
].join('\n');

/// P1에서 확정된 인식 출력 형태(스펙 #13). lowQuality는 실패 4종 중 "저품질"을 가르기 위한 추가 필드다.
const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ingredients: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          confidence: { type: 'STRING', enum: ['high', 'medium', 'low'] },
        },
        required: ['name', 'confidence'],
      },
    },
    lowQuality: { type: 'BOOLEAN' },
  },
  required: ['ingredients'],
};

function estimateCostUsd({ promptTokens, outputTokens, thoughtTokens }) {
  // Gemini는 thinking 토큰을 output 단가로 과금한다(T1 #6). flash-lite는 thinking을 안 쓰지만,
  // 모델명이 환경변수라 언젠가 thinking 모델이 들어올 수 있다 — 그때 원가의 78%가 증발하지 않게 한다.
  const inputCost = (promptTokens * PRICE_INPUT_PER_M) / 1_000_000;
  const outputCost = ((outputTokens + thoughtTokens) * PRICE_OUTPUT_PER_M) / 1_000_000;
  return inputCost + outputCost;
}

function readUsage(usageMetadata = {}) {
  const imageTokens = (usageMetadata.promptTokensDetails ?? [])
    .filter((d) => d.modality === 'IMAGE')
    .reduce((sum, d) => sum + (d.tokenCount ?? 0), 0);

  const usage = {
    promptTokens: usageMetadata.promptTokenCount ?? 0,
    outputTokens: usageMetadata.candidatesTokenCount ?? 0,
    thoughtTokens: usageMetadata.thoughtsTokenCount ?? 0,
    imageTokens,
    model: MODEL,
  };
  return { ...usage, costUsd: estimateCostUsd(usage) };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ message: 'POST만 받습니다' });
  }
  if (!process.env.GEMINI_API_KEY) {
    return res.status(500).json({ message: 'GEMINI_API_KEY가 없습니다' });
  }

  const { imageBase64 } = req.body ?? {};
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return res.status(400).json({ message: 'imageBase64가 필요합니다' });
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
          {
            parts: [
              { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } },
              { text: PROMPT },
            ],
          },
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
    ingredients: parsed.ingredients ?? [],
    lowQuality: parsed.lowQuality === true,
    usage: readUsage(payload.usageMetadata),
  });
}

export const __testing = { estimateCostUsd, readUsage, RESPONSE_SCHEMA };
