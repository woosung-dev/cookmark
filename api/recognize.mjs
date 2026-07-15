// 재료 인식 프록시 — API 키를 서버에 가두고, 토큰·추정 원가를 앱에 회신한다(스펙 #13).
//
// 앱과 분리된 서버리스 함수다. 클라이언트는 절대 Gemini를 직접 부르지 않는다.
// 모델·단가·원가 산식은 _gemini.mjs 한 곳에 있다.
import { generateJson, rejectNonPost } from './_gemini.mjs';

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

export default async function handler(req, res) {
  if (rejectNonPost(req, res)) return;

  const { imageBase64 } = req.body ?? {};
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return res.status(400).json({ message: 'imageBase64가 필요합니다' });
  }

  const { parsed, usage, error } = await generateJson({
    parts: [
      { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } },
      { text: PROMPT },
    ],
    schema: RESPONSE_SCHEMA,
    timeoutMs: UPSTREAM_TIMEOUT_MS,
  });
  if (error) return res.status(error.status).json({ message: error.message });

  return res.status(200).json({
    ingredients: parsed.ingredients ?? [],
    lowQuality: parsed.lowQuality === true,
    usage,
  });
}

export const __testing = { PROMPT, RESPONSE_SCHEMA };
