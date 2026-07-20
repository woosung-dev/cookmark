// LLM 호출의 유일한 경계 — 테스트가 결정적 페이크를 주입하는 단 하나의 seam이다(스펙 Testing Decisions).
import 'package:flutter/foundation.dart';

import '../domain/ingredient.dart';
import '../domain/recipe.dart';
import '../domain/suggestion.dart';

/// LLM 호출 1건의 사용량 메타데이터. 프록시가 회신하고 그대로 이벤트에 부착된다.
///
/// 원가는 파일럿의 병목이 아니지만(2주 총 ~$0.013~0.08 실측) 향후 과금 설계의 바닥 데이터로 쌓는다.
/// 필드 구성은 T1 #6 실측 resolution이 지정한 것이다 — 토큰을 하나로 뭉치지 않는다.
@immutable
class LlmUsage {
  const LlmUsage({
    required this.promptTokens,
    required this.outputTokens,
    required this.thoughtTokens,
    required this.imageTokens,
    required this.costUsd,
    required this.model,
  });

  /// promptTokenCount — 이미지 + 텍스트 입력.
  final int promptTokens;

  /// candidatesTokenCount — 실제 출력.
  final int outputTokens;

  /// thoughtsTokenCount. 0이 아닌 모델로 갈아타면 이게 원가의 대부분이 된다 —
  /// T1 #6 실측에서 3.5-flash는 thinking이 호출 원가의 78%였다. 안 남기면 원가가 그만큼 증발한다.
  final int thoughtTokens;

  /// promptTokensDetails의 IMAGE 모달리티. Gemini는 해상도와 무관하게 1,064 고정이라
  /// 이 값이 흔들리면 모델이나 전처리가 바뀐 것이다.
  final int imageTokens;

  final double costUsd;

  /// 어느 모델이 이 숫자를 냈는지 — 모델명이 환경설정 주입이므로 로그에 귀속시켜야 해석이 된다.
  /// T1 #6 결론: 원가 단위는 "모델명"이 아니라 "모델+thinking 구성"이다.
  final String model;

  /// 과금 대상 토큰 합 — thinking은 output 단가로 과금된다(T1 #6).
  int get billedTokens => promptTokens + outputTokens + thoughtTokens;

  Map<String, Object?> toJson() => {
    'promptTokens': promptTokens,
    'outputTokens': outputTokens,
    'thoughtTokens': thoughtTokens,
    'imageTokens': imageTokens,
    'costUsd': costUsd,
    'model': model,
  };

  factory LlmUsage.fromJson(Map<String, Object?> json) => LlmUsage(
    promptTokens: (json['promptTokens']! as num).toInt(),
    outputTokens: (json['outputTokens']! as num).toInt(),
    thoughtTokens: (json['thoughtTokens'] as num?)?.toInt() ?? 0,
    imageTokens: (json['imageTokens'] as num?)?.toInt() ?? 0,
    costUsd: (json['costUsd']! as num).toDouble(),
    model: json['model']! as String,
  );
}

/// 재료 인식 1회의 결과.
@immutable
class RecognitionResult {
  const RecognitionResult({required this.ingredients, required this.usage});

  final List<Ingredient> ingredients;
  final LlmUsage usage;
}

/// LLM 호출이 실패한 이유 — 전부 해당 섹션의 인라인 카드로 해소된다(G1 #8, 에러 화면 없음).
enum LlmFailureKind {
  /// 인식 결과가 0개
  empty,

  /// 사진이 너무 어둡거나 흐려 판독 불가
  lowQuality,

  /// 네트워크·서버·파싱 오류
  error,

  /// 30초 초과
  timeout,
}

class LlmFailure implements Exception {
  const LlmFailure(this.kind, [this.detail]);

  final LlmFailureKind kind;
  final String? detail;

  @override
  String toString() =>
      'LlmFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// 응답 해석에서 나온 **어떤** 실패든 [LlmFailure]로 정규화한다 — 구현이 공통으로 쓰는 계약 강제 장치.
///
/// 왜 필요한가 — 200인데 모양이 다른 본문(Map이 아님·`usage` 없음·항목 모양이 다름)은 JSON 파싱을
/// 통과하므로 `FormatException`이 아니라 **`TypeError`** 를 낳는다. `TypeError`는 `Error`이지
/// `Exception`이 아니라서 `on FormatException`도 `on Exception`도, 컨트롤러의 `on LlmFailure`도
/// 못 잡는다. 그러면 컨트롤러가 phase를 실패로 넘기지 못하고 **화면이 로딩에 영구 고착**한다
/// (폐기된 arm #25를 죽인 결함이 랜딩된 #26에 그대로 살아 있었다 — #142).
///
/// 예외 유형을 열거하지 않는 것이 핵심이다. `on TypeError`만 잡으면 응답 모양이 조금 달라질 때
/// `NoSuchMethodError`·`RangeError`가 대신 나와 고착이 그대로 돌아온다 — 두더지잡기다(#123 교훈:
/// "결정적 경로는 광범위 except로 최종단을 보장한다"). **정규화되지 않은 실패가 게이트웨이 밖으로
/// 새지 않는 것이 이 경계의 계약이고**, 이 함수가 그 계약의 유일한 강제 지점이다.
Future<T> normalizeLlmFailures<T>(Future<T> Function() interpret) async {
  try {
    return await interpret();
  } on LlmFailure {
    // empty·lowQuality는 이미 정규화된 도메인 실패다 — error로 뭉개면 실패 카드 문구가 갈린다.
    rethrow;
  } catch (e) {
    // bare catch는 Error까지 잡는다 — on Exception이 못 잡는 그 차이가 결함의 전부였다.
    throw LlmFailure(LlmFailureKind.error, '응답 형식 불일치: $e');
  }
}

/// 레시피 제목(또는 URL 내용)에서 재료를 추론한 결과.
@immutable
class ExtractionResult {
  const ExtractionResult({required this.ingredients, required this.usage});

  final List<String> ingredients;

  /// 서버가 JSON-LD로 결정적 추출을 하면 LLM이 돌지 않아 usage가 없다(#123) — 그때 null이다.
  final LlmUsage? usage;
}

/// 매칭 1회의 결과.
@immutable
class MatchResult {
  const MatchResult({required this.suggestions, required this.usage});

  /// LLM이 준 그대로 — 부족 4개 이상 제외와 3개 상한은 클라이언트가 한다(스펙 #13).
  final List<Suggestion> suggestions;

  final LlmUsage usage;
}

/// 인식·추출·매칭을 감싸는 경계. 구현은 서버리스 프록시(운영)와 페이크(테스트) 둘뿐이다.
abstract interface class LlmGateway {
  /// 냉장고 사진에서 재료 후보를 얻는다. [jpegBytes]는 이미 768px로 리사이즈된 것이어야 한다.
  Future<RecognitionResult> recognize(Uint8List jpegBytes);

  /// 레시피 제목에서 재료를 추론한다. [url]이 있으면 서버가 URL 내용 기반 추출 사다리를 탄다(#123).
  ///
  /// 파일럿 프록시 경계는 [url]을 무시하고 제목만 쓴다 — 행동 무변화.
  /// "김치찌개"처럼 요리명이 또렷하면 잘 되고, "오늘의 저녁"처럼 모호하면 빈약해진다.
  Future<ExtractionResult> extractIngredients(String title, {String? url});

  /// 확정 재료와 저장 레시피를 맞춰 제안을 얻는다.
  ///
  /// 한 번의 호출로 끝낸다 — 한국어 동의어·정규화("대파"/"파")는 프롬프트 안에서 LLM이 처리한다.
  Future<MatchResult> match({
    required List<String> ingredients,
    required List<Recipe> recipes,
  });
}
