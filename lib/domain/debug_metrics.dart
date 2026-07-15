// 파운더 전용 측정 푸터의 숫자 — 파일럿 중 로그 건전성을 매일 확인하는 창(#22, ADR-0004).
//
// 배우자에게는 절대 보이지 않는다. debug 쿼리 파라미터가 있을 때만 렌더되고, 없으면
// 위젯 트리에 존재조차 하지 않는다 — 단일맹검(ADR-0004)이 깨지면 P2 킬 기준이 통째로 오염된다.
import 'package:flutter/foundation.dart';

import 'app_event.dart';

@immutable
class DebugMetrics {
  const DebugMetrics({
    required this.recognitionLatencyMs,
    required this.matchingLatencyMs,
    required this.lastTokens,
    required this.totalCostUsd,
    required this.manualEdits,
    required this.eventCount,
    required this.lastModel,
  });

  /// 최근 인식 지연. 없으면 null.
  final int? recognitionLatencyMs;

  /// 최근 매칭 지연.
  final int? matchingLatencyMs;

  /// 최근 LLM 호출의 과금 대상 토큰 합.
  final int? lastTokens;

  /// 누적 추정 원가 — 파일럿 전체가 $0.1 미만이어야 정상이다(T1 #6).
  final double totalCostUsd;

  /// 수동 수정 수 — ADR-0003 산식 그대로(vagueDismiss는 미결이라 제외).
  final int manualEdits;

  final int eventCount;
  final String? lastModel;
}

/// 이벤트 로그에서 파운더가 볼 원시값을 뽑는다.
DebugMetrics debugMetricsFrom(List<AppEvent> events) {
  int? recognitionLatencyMs;
  int? matchingLatencyMs;
  int? lastTokens;
  String? lastModel;
  var totalCostUsd = 0.0;
  var manualEdits = 0;

  for (final event in events) {
    switch (event.type) {
      case AppEventType.recognitionDone:
        recognitionLatencyMs = event.data['latencyMs'] as int?;
        lastTokens = _billedTokens(event.data);
        lastModel = event.data['model'] as String?;
      case AppEventType.matchingDone:
        matchingLatencyMs = event.data['latencyMs'] as int?;
        lastTokens = _billedTokens(event.data);
        lastModel = event.data['model'] as String?;
      case AppEventType.checklistEdit:
        final kind = EditKind.values
            .where((k) => k.name == event.data['kind'])
            .firstOrNull;
        if (kind != null && kind.countsAsManualEdit) manualEdits++;
      case _:
        break;
    }
    totalCostUsd += (event.data['costUsd'] as num?)?.toDouble() ?? 0;
  }

  return DebugMetrics(
    recognitionLatencyMs: recognitionLatencyMs,
    matchingLatencyMs: matchingLatencyMs,
    lastTokens: lastTokens,
    totalCostUsd: totalCostUsd,
    manualEdits: manualEdits,
    eventCount: events.length,
    lastModel: lastModel,
  );
}

/// thinking은 output 단가로 과금된다 — 합에 넣지 않으면 원가가 증발한다(T1 #6).
int _billedTokens(Map<String, Object?> data) =>
    ((data['promptTokens'] as num?)?.toInt() ?? 0) +
    ((data['outputTokens'] as num?)?.toInt() ?? 0) +
    ((data['thoughtTokens'] as num?)?.toInt() ?? 0);

/// debug 쿼리 파라미터가 붙어 있는가 — `?debug` 또는 `?debug=1`.
///
/// [Uri.base]는 웹에서 현재 페이지 URL이고, 그 외 타깃에서는 쿼리가 없다.
/// 그래서 플랫폼을 갈라둘 필요가 없다.
bool debugFooterEnabled() => Uri.base.queryParameters.containsKey('debug');
