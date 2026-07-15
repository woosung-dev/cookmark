// 테스트용 결정적 LLM 경계 구현 — E2E·유닛이 이 seam에 주입한다(스펙 Testing Decisions).
import 'dart:typed_data';

import '../domain/ingredient.dart';
import 'llm_gateway.dart';

/// P1 실측을 닮은 인식 fixture — high/medium/low가 섞이고 뭉뚱그림 항목("반찬통")이 들어 있다.
///
/// 스펙 Testing Decisions가 요구하는 모양이다. 이걸 "깨끗한" 목록으로 바꾸면 체크리스트의
/// 3단 초기 상태와 뭉뚱그림 분리(ADR-0002)가 테스트에서 사라진다.
final defaultRecognitionFixture = <Ingredient>[
  Ingredient.recognized(name: '대파', confidence: Confidence.high),
  Ingredient.recognized(name: '계란', confidence: Confidence.high),
  Ingredient.recognized(name: '두부', confidence: Confidence.high),
  Ingredient.recognized(name: '애호박', confidence: Confidence.medium),
  Ingredient.recognized(name: '반찬통', confidence: Confidence.medium),
  Ingredient.recognized(name: '고추장', confidence: Confidence.low),
  Ingredient.recognized(name: '표고버섯', confidence: Confidence.low),
];

/// T1 #6 실측표의 `gemini-3.1-flash-lite 기본·768px` 행 그대로 — 1157/295, $0.00073, 이미지 1,064 고정.
/// 지어낸 숫자를 쓰면 원가 기록 장치의 테스트가 아무것도 지키지 못한다.
const _fixtureUsage = LlmUsage(
  promptTokens: 1157,
  outputTokens: 295,
  thoughtTokens: 0,
  imageTokens: 1064,
  costUsd: 0.00073,
  model: 'fake-recognizer',
);

/// 결정적 페이크. 지연·실패를 주입해 로딩 단계와 인라인 실패 카드를 테스트한다.
class FakeLlmGateway implements LlmGateway {
  FakeLlmGateway({
    List<Ingredient>? ingredients,
    this.latency = Duration.zero,
    this.failure,
  }) : ingredients = ingredients ?? defaultRecognitionFixture;

  final List<Ingredient> ingredients;

  /// 로딩 단계식 문구(0~3s / 3~10s / 10s 취소 등장)를 테스트하려면 여기를 늘린다.
  final Duration latency;

  /// null이 아니면 인식이 이 실패로 끝난다.
  final LlmFailure? failure;

  /// 이 페이크가 몇 번 호출됐는지 — "다시 시도"가 실제로 재호출하는지 검증할 때 쓴다.
  int recognizeCallCount = 0;

  @override
  Future<RecognitionResult> recognize(Uint8List jpegBytes) async {
    recognizeCallCount++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure != null) throw failure!;
    return RecognitionResult(ingredients: ingredients, usage: _fixtureUsage);
  }
}
