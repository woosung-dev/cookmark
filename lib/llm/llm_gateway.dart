// LLM 호출의 유일한 경계 — 테스트가 결정적 페이크를 주입하는 단 하나의 seam이다(스펙 Testing Decisions).
import 'package:flutter/foundation.dart';

import '../domain/ingredient.dart';

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

/// 인식·매칭을 감싸는 경계. 구현은 서버리스 프록시(운영)와 페이크(테스트) 둘뿐이다.
abstract interface class LlmGateway {
  /// 냉장고 사진에서 재료 후보를 얻는다. [jpegBytes]는 이미 768px로 리사이즈된 것이어야 한다.
  Future<RecognitionResult> recognize(Uint8List jpegBytes);
}
