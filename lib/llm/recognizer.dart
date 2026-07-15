// LLM 호출 경계 — 앱의 유일한 seam(스펙 #13). 테스트는 여기에 결정적 페이크를 주입한다.
import 'package:flutter/foundation.dart';

import '../models/ingredient.dart';

/// 인식 1회의 제한 시간. G1 #8의 단계식 문구가 30초에 타임아웃을 알리므로 같은 값이다.
///
/// 이 약속을 지키는 책임은 호출자([MainController])에 있다 — 구현마다 제 타이머를 두면
/// 타이머 없는 구현 하나가 부엌 앞 사용자를 무한히 기다리게 만든다.
const kRecognitionTimeout = Duration(seconds: 30);

/// 재료 인식의 경계. 구현은 서버리스 프록시([GeminiProxyRecognizer])이거나
/// 테스트용 페이크([FakeRecognizer])다. 위젯은 이 타입만 안다.
abstract interface class IngredientRecognizer {
  /// 냉장고 사진 1장에서 재료 후보를 얻는다.
  ///
  /// 실패는 [RecognitionException]으로 던진다 — 호출자는 인라인 에러 카드로 처리한다.
  Future<RecognitionResult> recognize(Uint8List imageBytes);
}

/// 인식 실패의 사유. G1 #8이 정한 실패 4종(0개·저품질·오류·타임아웃)에 대응한다.
enum FailureReason { empty, lowQuality, server, timeout }

class RecognitionException implements Exception {
  const RecognitionException(this.reason, [this.detail]);

  final FailureReason reason;
  final String? detail;

  @override
  String toString() =>
      'RecognitionException($reason${detail == null ? '' : ': $detail'})';
}

/// LLM 호출 1건의 사용량. 토큰·추정 원가는 프록시가 계산해 회신하고,
/// 앱은 이벤트에 그대로 실어 향후 과금 설계의 바닥 데이터로 남긴다(스펙 #13).
@immutable
class RecognitionUsage {
  const RecognitionUsage({
    this.latencyMs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.thinkingTokens = 0,
    this.estimatedCostUsd = 0,
    this.model = '',
  });

  factory RecognitionUsage.fromJson(Map<String, dynamic> json) =>
      RecognitionUsage(
        latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        thinkingTokens: (json['thinkingTokens'] as num?)?.toInt() ?? 0,
        estimatedCostUsd: (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0,
        model: json['model'] as String? ?? '',
      );

  final int latencyMs;
  final int inputTokens;
  final int outputTokens;

  /// Gemini의 `thoughtsTokenCount`. flash-lite는 0이지만 반드시 남긴다 —
  /// T1 #6 실측에서 thinking이 호출 원가의 78%를 차지한 구성이 있었고,
  /// 이 필드를 빠뜨리면 향후 과금 설계의 바닥 데이터가 그만큼 왜곡된다.
  final int thinkingTokens;
  final double estimatedCostUsd;

  /// 이 결과를 만든 모델명(프록시의 `GEMINI_MODEL`). 모델명이 환경변수로 교체 가능하므로
  /// 로그에 같이 남기지 않으면 파일럿 행을 어떤 모델이 만들었는지 사후에 댈 수 없다.
  final String model;

  Map<String, dynamic> toEventData() => {
    'latencyMs': latencyMs,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'thinkingTokens': thinkingTokens,
    'estimatedCostUsd': estimatedCostUsd,
    'model': model,
  };
}

@immutable
class RecognitionResult {
  const RecognitionResult({required this.ingredients, required this.usage});

  final List<Ingredient> ingredients;
  final RecognitionUsage usage;
}
