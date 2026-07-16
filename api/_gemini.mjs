// 세 프록시 함수(인식·추출·매칭)가 공유하는 Gemini 호출부 — 모델·단가·원가 산식이 여기 한 곳에만 있다.
//
// 나눠 두면 모델을 바꿀 때 한쪽만 고치게 되고, 그러면 원가 로그가 조용히 틀린다.
// 원가는 T1 #6이 파일럿 원가 판정에 쓰는 입력이라 조용히 틀리면 비싸다.

/// 모델은 환경변수로 주입해 교체 가능하게 둔다(스펙 #13). 파일럿 중에는 바꾸지 않는다.
export const MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';

/// 단가(USD per 1M 토큰). gemini-3.1-flash-lite = $0.25 / $1.50 — T1 #6이 공식 가격 페이지에서
/// 확인하고 실측으로 검산한 값이다(1157 in / 295 out → $0.00073).
///
/// **모델을 바꾸면 이 값도 함께 바꿔야 한다.** 안 바꾸면 원가 로그가 조용히 틀린다.
const PRICE_INPUT_PER_M = Number(process.env.GEMINI_PRICE_INPUT_PER_M ?? 0.25);
const PRICE_OUTPUT_PER_M = Number(process.env.GEMINI_PRICE_OUTPUT_PER_M ?? 1.5);

const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

/// 호출 1건의 사용량 — 필드 구성은 T1 #6 실측 resolution이 지정한 것이다. 토큰을 하나로 뭉치지 않는다.
export function readUsage(usageMetadata = {}) {
  const promptTokens = usageMetadata.promptTokenCount ?? 0;
  const outputTokens = usageMetadata.candidatesTokenCount ?? 0;
  // thinking을 빠뜨리면 원가의 대부분이 증발한다 — T1 #6에서 3.5-flash는 78%였다.
  const thoughtTokens = usageMetadata.thoughtsTokenCount ?? 0;
  const imageTokens = (usageMetadata.promptTokensDetails ?? [])
    .filter((d) => d.modality === 'IMAGE')
    .reduce((sum, d) => sum + (d.tokenCount ?? 0), 0);

  return {
    promptTokens,
    outputTokens,
    thoughtTokens,
    imageTokens,
    model: MODEL,
    // Gemini는 thinking을 output 단가로 과금한다(T1 #6).
    costUsd:
      (promptTokens * PRICE_INPUT_PER_M) / 1_000_000 +
      ((outputTokens + thoughtTokens) * PRICE_OUTPUT_PER_M) / 1_000_000,
  };
}

/// 구조화 출력 1회. 성공하면 `{ parsed, usage }`, 실패하면 `{ error: {status, message} }`.
///
/// 프록시 3개가 다루는 실패 모양을 여기서 하나로 만든다 — 어느 함수에서 나든 앱은 같은 걸 본다.
export async function generateJson({ parts, schema, timeoutMs }) {
  if (!process.env.GEMINI_API_KEY) {
    return { error: { status: 500, message: 'GEMINI_API_KEY가 없습니다' } };
  }

  let upstream;
  try {
    upstream = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': process.env.GEMINI_API_KEY,
      },
      signal: AbortSignal.timeout(timeoutMs),
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: schema,
        },
      }),
    });
  } catch (e) {
    return { error: { status: 502, message: `업스트림 호출 실패: ${e.name}` } };
  }

  if (!upstream.ok) {
    return { error: { status: 502, message: `업스트림 ${upstream.status}` } };
  }

  const payload = await upstream.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    return { error: { status: 502, message: '업스트림 응답에 본문이 없습니다' } };
  }

  try {
    return { parsed: JSON.parse(text), usage: readUsage(payload.usageMetadata) };
  } catch {
    return { error: { status: 502, message: '구조화 출력 파싱 실패' } };
  }
}

/// POST가 아니면 거절한다 — 세 함수가 똑같이 하던 일.
export function rejectNonPost(req, res) {
  if (req.method === 'POST') return false;
  res.status(405).json({ message: 'POST만 받습니다' });
  return true;
}
