// 테스트용 결정적 인식 페이크 — E2E가 LLM 경계에 주입하는 유일한 대역
import 'dart:typed_data';

import '../models/ingredient.dart';
import 'recognizer.dart';

/// E2E·수동 확인용 페이크. fixture는 P1 실측을 닮게 구성한다 —
/// high/medium/low 혼합 + 뭉뚱그림 항목("반찬통", ADR-0002) 포함.
class FakeRecognizer implements IngredientRecognizer {
  const FakeRecognizer({this.failWith, this.delay = Duration.zero});

  /// 실패 경로를 E2E에서 구동하기 위한 주입. null이면 성공한다.
  final FailureReason? failWith;

  /// 로딩 단계식 문구를 확인할 때만 쓴다. 기본은 즉시 응답(결정적).
  final Duration delay;

  static const _fixture = [
    (name: '대파', confidence: Confidence.high),
    (name: '계란', confidence: Confidence.high),
    (name: '두부', confidence: Confidence.medium),
    (name: '반찬통', confidence: Confidence.medium),
    (name: '애호박', confidence: Confidence.medium),
    (name: '트러플', confidence: Confidence.low),
    (name: '케이퍼', confidence: Confidence.low),
  ];

  @override
  Future<RecognitionResult> recognize(Uint8List imageBytes) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecognitionException(failWith!);

    return RecognitionResult(
      ingredients: [
        for (final f in _fixture)
          Ingredient.fromRecognition(name: f.name, confidence: f.confidence),
      ],
      // T1 #6의 flash-lite·768px 실측값(1157/295/0, 1.9s, $0.00073).
      usage: const RecognitionUsage(
        latencyMs: 1900,
        inputTokens: 1157,
        outputTokens: 295,
        thinkingTokens: 0,
        estimatedCostUsd: 0.00073,
        model: 'gemini-3.1-flash-lite',
      ),
    );
  }
}
