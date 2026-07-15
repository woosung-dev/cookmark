// 재료 인식 프록시 — API 키를 서버에 두고 Gemini를 호출한 뒤 재료와 사용량을 회신한다
//
// 앱과 분리된 서버리스 함수(ADR-0005). 클라이언트는 키를 모르고, 이 함수만 키를 쥔다.
// 응답 계약은 P1 #7에서 확정된 형태다: {"ingredients":[{"name","confidence"}], "usage":{...}}

const MODEL = process.env.GEMINI_MODEL || 'gemini-3.1-flash-lite';

// 2026-07-13 공식 가격 페이지 확인(T1 #6), USD per 1M tokens.
// thinking 토큰은 output 단가로 과금된다.
const PRICING = { inputPerM: 0.25, outputPerM: 1.5 };

// P1 #7·MVP 동일 프롬프트 — 한국어 재료 후보 JSON.
const PROMPT = [
  '이 냉장고 사진에서 보이는 식재료를 나열해줘.',
  '사진에 실제로 보이는 것만 답하고, 있을 법한 것을 추측해서 넣지 마.',
  '각 항목의 confidence는 확실히 식별되면 high, 아마도면 medium, 불확실하면 low로 답해.',
  '재료명은 한국어로 답해.',
].join(' ');

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    ingredients: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['name', 'confidence'],
      },
    },
  },
  required: ['ingredients'],
};

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST만 받습니다' });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error('GEMINI_API_KEY가 설정되지 않았습니다');
    return res.status(500).json({ error: '서버 설정 오류' });
  }

  const imageBase64 = req.body?.imageBase64;
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return res.status(400).json({ error: 'imageBase64가 필요합니다' });
  }

  const startedAt = Date.now();
  try {
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: PROMPT },
                { inline_data: { mime_type: 'image/jpeg', data: imageBase64 } },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: RESPONSE_SCHEMA,
          },
        }),
      },
    );

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error(`Gemini ${upstream.status}: ${detail.slice(0, 500)}`);
      return res.status(502).json({ error: '인식 서비스 오류' });
    }

    const payload = await upstream.json();
    const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      console.error('Gemini 응답에 텍스트가 없습니다', JSON.stringify(payload).slice(0, 500));
      return res.status(502).json({ error: '인식 결과를 읽지 못했습니다' });
    }

    const parsed = JSON.parse(text);
    const ingredients = Array.isArray(parsed.ingredients) ? parsed.ingredients : [];

    return res.status(200).json({
      ingredients,
      usage: buildUsage(payload.usageMetadata, Date.now() - startedAt),
    });
  } catch (e) {
    console.error('인식 프록시 실패', e);
    return res.status(502).json({ error: '인식 서비스 오류' });
  }
}

/// usageMetadata를 이벤트 로그가 쓰는 형태로 옮기고 원가를 계산한다.
/// thoughtsTokenCount를 빠뜨리면 원가가 최대 78%까지 과소 계상된다(T1 #6).
function buildUsage(meta, latencyMs) {
  const inputTokens = meta?.promptTokenCount ?? 0;
  const outputTokens = meta?.candidatesTokenCount ?? 0;
  const thinkingTokens = meta?.thoughtsTokenCount ?? 0;

  const estimatedCostUsd =
    (inputTokens * PRICING.inputPerM + (outputTokens + thinkingTokens) * PRICING.outputPerM) /
    1e6;

  return {
    latencyMs,
    inputTokens,
    outputTokens,
    thinkingTokens,
    estimatedCostUsd,
    model: MODEL,
  };
}
