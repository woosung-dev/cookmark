// 레시피 재료 추출 프록시 — 제목만 보고 LLM이 재료를 추론한다.
//
// 본문·자막·설명란을 긁지 않는다. 우리가 다루는 건 URL과 사용자가 적은 제목뿐이다
// (스펙 #13 Out of scope "URL·제목 수준만", 수익화·법적 리서치 #5 "YouTube 스크래핑 금지").
// 스펙은 프록시 2개를 명시했으나 #17 AC(레시피 북 재료 기반 미인식 칩)·매칭 규칙(저장 레시피
// 재료 목록)·G1 #8("그 자리에서 추출 완결")·T1 #6 원가표("레시피 저장 ingest")가 이걸 요구한다.
// 2026-07-15 사용자 결정으로 추가 — 근거는 docs/tickets/13/context-notes.md.

const MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';

/// 단가(USD per 1M 토큰) — recognize.mjs와 같은 출처(T1 #6). 모델을 바꾸면 함께 바꾼다.
const PRICE_INPUT_PER_M = Number(process.env.GEMINI_PRICE_INPUT_PER_M ?? 0.25);
const PRICE_OUTPUT_PER_M = Number(process.env.GEMINI_PRICE_OUTPUT_PER_M ?? 1.5);

const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

/// 텍스트 온리라 인식보다 빠르다(T1 #6 매칭 실측 1.2s).
const UPSTREAM_TIMEOUT_MS = 15_000;

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ingredients: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['ingredients'],
};

function promptFor(title) {
  return [
    `"${title}"을(를) 만들 때 보통 들어가는 재료를 한국어로 나열해 주세요.`,
    '',
    '규칙:',
    '- 재료 이름만 적습니다. 분량·조리법은 적지 마세요.',
    '- 흔한 조리법 기준으로 적습니다. 특정 레시피를 그대로 옮기려 하지 마세요.',
    '- 요리명이 무엇인지 알 수 없으면 ingredients를 빈 배열로 두세요.',
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
    // 텍스트 온리 호출이라 이미지 토큰은 늘 0이다.
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

  const title = req.body?.title;
  if (typeof title !== 'string' || title.trim().length === 0) {
    return res.status(400).json({ message: 'title이 필요합니다' });
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
        contents: [{ parts: [{ text: promptFor(title.trim()) }] }],
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
    usage: readUsage(payload.usageMetadata),
  });
}

export const __testing = { promptFor, readUsage, RESPONSE_SCHEMA };
