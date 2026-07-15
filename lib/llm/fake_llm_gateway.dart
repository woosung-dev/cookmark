// 테스트용 결정적 LLM 경계 구현 — E2E·유닛이 이 seam에 주입한다(스펙 Testing Decisions).
import 'dart:typed_data';

import '../domain/ingredient.dart';
import '../domain/recipe.dart';
import '../domain/suggestion.dart';
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
    this.matchFailure,
  }) : ingredients = ingredients ?? defaultRecognitionFixture;

  final List<Ingredient> ingredients;

  /// 로딩 단계식 문구(0~3s / 3~10s / 10s 취소 등장)를 테스트하려면 여기를 늘린다.
  final Duration latency;

  /// null이 아니면 모든 호출이 이 실패로 끝난다.
  final LlmFailure? failure;

  /// 매칭만 실패시킨다 — 인식은 성공해야 매칭 단계까지 갈 수 있다.
  final LlmFailure? matchFailure;

  /// 이 페이크가 몇 번 호출됐는지 — "다시 시도"가 실제로 재호출하는지 검증할 때 쓴다.
  int recognizeCallCount = 0;
  int extractCallCount = 0;

  /// 제목 → 재료. 없는 제목은 [_fallbackExtraction]으로 답한다.
  final Map<String, List<String>> extractions = {
    '김치찌개': ['김치', '돼지고기', '두부', '대파', '고춧가루'],
    '애호박볶음': ['애호박', '대파', '소금', '식용유'],
    '계란찜': ['계란', '대파', '새우젓'],
  };

  static const _fallbackExtraction = ['소금', '식용유'];

  @override
  Future<RecognitionResult> recognize(Uint8List jpegBytes) async {
    recognizeCallCount++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure != null) throw failure!;
    return RecognitionResult(ingredients: ingredients, usage: _fixtureUsage);
  }

  @override
  Future<ExtractionResult> extractIngredients(String title) async {
    extractCallCount++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure != null) throw failure!;
    return ExtractionResult(
      ingredients: extractions[title] ?? _fallbackExtraction,
      usage: _extractionUsage,
    );
  }

  @override
  Future<MatchResult> match({
    required List<String> ingredients,
    required List<Recipe> recipes,
  }) async {
    matchCallCount++;
    lastMatchedIngredients = ingredients;
    lastMatchedRecipes = recipes;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final fail = matchFailure ?? failure;
    if (fail != null) throw fail;
    return MatchResult(
      suggestions: suggestions ?? defaultSuggestions(recipes),
      usage: _matchingUsage,
    );
  }

  int matchCallCount = 0;
  List<String>? lastMatchedIngredients;
  List<Recipe>? lastMatchedRecipes;

  /// null이면 [defaultSuggestions]를 쓴다.
  List<Suggestion>? suggestions;
}

/// 라벨 3종과 출처 2종이 다 나오는 fixture — 카드가 모든 모양을 보여줄 수 있게.
///
/// 저장 제안은 실제 레시피 북에서 제목을 빌린다. 레시피 북이 비면 생성 제안만 나온다.
List<Suggestion> defaultSuggestions(List<Recipe> recipes) => [
  if (recipes.isNotEmpty)
    Suggestion(
      menu: recipes.first.title,
      source: SuggestionSource.saved,
      missing: const [],
      reason: '냉장고에 있는 재료로 다 돼요.',
      recipeUrl: recipes.first.url,
    ),
  const Suggestion(
    menu: '애호박볶음',
    source: SuggestionSource.generated,
    missing: [MissingIngredient(name: '식용유')],
    reason: '애호박이 있어서 금방 만들 수 있어요.',
  ),
  const Suggestion(
    menu: '두부조림',
    source: SuggestionSource.generated,
    missing: [MissingIngredient(name: '우유', substitute: '두유')],
    reason: '두부가 있고 우유는 두유로 대신할 수 있어요.',
  ),
];

/// T1 #6 실측의 매칭 호출 — 395/225, 1.2s, $0.00044.
const _matchingUsage = LlmUsage(
  promptTokens: 395,
  outputTokens: 225,
  thoughtTokens: 0,
  imageTokens: 0,
  costUsd: 0.00044,
  model: 'fake-matcher',
);

/// T1 #6 실측의 매칭 호출(텍스트 온리, 395/225 → $0.00044) 자리를 빌린다 —
/// 추출도 같은 모양의 텍스트 온리 호출이라 이미지 토큰이 0이다.
const _extractionUsage = LlmUsage(
  promptTokens: 395,
  outputTokens: 225,
  thoughtTokens: 0,
  imageTokens: 0,
  costUsd: 0.00044,
  model: 'fake-extractor',
);
