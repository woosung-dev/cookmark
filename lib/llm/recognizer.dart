// LLM 호출 경계 — 앱의 유일한 seam(스펙 #13). 테스트는 여기에 결정적 페이크를 주입한다.
import 'package:flutter/foundation.dart';

import '../models/ingredient.dart';

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
  String toString() => 'RecognitionException($reason${detail == null ? '' : ': $detail'})';
}

/// LLM 호출 1건의 사용량. 토큰·추정 원가는 프록시가 계산해 회신하고,
/// 앱은 이벤트에 그대로 실어 향후 과금 설계의 바닥 데이터로 남긴다(스펙 #13).
@immutable
class RecognitionUsage {
  const RecognitionUsage({
    this.latencyMs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.estimatedCostUsd = 0,
  });

  factory RecognitionUsage.fromJson(Map<String, dynamic> json) => RecognitionUsage(
    latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    estimatedCostUsd: (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0,
  );

  final int latencyMs;
  final int inputTokens;
  final int outputTokens;
  final double estimatedCostUsd;

  Map<String, dynamic> toEventData() => {
    'latencyMs': latencyMs,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'estimatedCostUsd': estimatedCostUsd,
  };
}

@immutable
class RecognitionResult {
  const RecognitionResult({required this.ingredients, required this.usage});

  final List<Ingredient> ingredients;
  final RecognitionUsage usage;
}
