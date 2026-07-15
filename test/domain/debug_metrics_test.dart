// 측정 푸터의 원시값과 단일맹검 방어 — 파운더만 본다(#22, ADR-0004).
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/debug_metrics.dart';
import 'package:cookmark/domain/suggestion.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime.utc(2026, 7, 15, 19);

const _recognitionUsage = LlmUsage(
  promptTokens: 1157,
  outputTokens: 295,
  thoughtTokens: 0,
  imageTokens: 1064,
  costUsd: 0.00073,
  model: 'gemini-3.1-flash-lite',
);

const _matchingUsage = LlmUsage(
  promptTokens: 395,
  outputTokens: 225,
  thoughtTokens: 0,
  imageTokens: 0,
  costUsd: 0.00044,
  model: 'gemini-3.1-flash-lite',
);

void main() {
  test('빈 로그는 전부 비어 있다', () {
    final metrics = debugMetricsFrom([]);
    expect(metrics.recognitionLatencyMs, isNull);
    expect(metrics.manualEdits, 0);
    expect(metrics.totalCostUsd, 0);
  });

  test('최근 지연·토큰·모델을 뽑는다', () {
    final metrics = debugMetricsFrom([
      AppEvent.recognitionDone(
        at: _at,
        latency: const Duration(milliseconds: 1940),
        usage: _recognitionUsage,
        count: 7,
      ),
      AppEvent.matchingDone(
        at: _at,
        latency: const Duration(milliseconds: 1200),
        usage: _matchingUsage,
        shownCount: 3,
        excludedCount: 1,
      ),
    ]);

    expect(metrics.recognitionLatencyMs, 1940);
    expect(metrics.matchingLatencyMs, 1200);
    expect(metrics.lastTokens, 395 + 225);
    expect(metrics.lastModel, 'gemini-3.1-flash-lite');
  });

  test('누적 원가는 모든 LLM 호출의 합이다 — 파일럿 전체가 \$0.1 미만이어야 정상(T1 #6)', () {
    final metrics = debugMetricsFrom([
      AppEvent.recognitionDone(
        at: _at,
        latency: Duration.zero,
        usage: _recognitionUsage,
        count: 7,
      ),
      AppEvent.matchingDone(
        at: _at,
        latency: Duration.zero,
        usage: _matchingUsage,
        shownCount: 3,
        excludedCount: 0,
      ),
    ]);

    expect(metrics.totalCostUsd, closeTo(0.00073 + 0.00044, 1e-9));
  });

  test('토큰 합에 thinking이 들어간다 — 빠뜨리면 원가가 증발한다(T1 #6)', () {
    final metrics = debugMetricsFrom([
      AppEvent.recognitionDone(
        at: _at,
        latency: Duration.zero,
        usage: const LlmUsage(
          promptTokens: 1157,
          outputTokens: 294,
          thoughtTokens: 1735,
          imageTokens: 1064,
          costUsd: 0.02,
          model: 'gemini-3.5-flash',
        ),
        count: 7,
      ),
    ]);

    expect(metrics.lastTokens, 1157 + 294 + 1735);
  });

  group('수동 수정 수 — ADR-0003 산식 그대로', () {
    AppEvent editOf(EditKind kind) => AppEvent.checklistEdit(
      at: _at,
      kind: kind,
      path: EditPath.row,
      name: '대파',
    );

    test('해제·재체크·추가·치환을 센다', () {
      final metrics = debugMetricsFrom([
        editOf(EditKind.uncheck),
        editOf(EditKind.recheck),
        editOf(EditKind.add),
        editOf(EditKind.substitute),
      ]);
      expect(metrics.manualEdits, 4);
    });

    test('뭉뚱그림 오탐 복귀는 세지 않는다 — 산식 판정이 미결이다', () {
      final metrics = debugMetricsFrom([
        editOf(EditKind.uncheck),
        editOf(EditKind.vagueDismiss),
      ]);
      expect(metrics.manualEdits, 1);
    });

    test('체크리스트 조작이 아닌 이벤트는 안 센다', () {
      final metrics = debugMetricsFrom([
        AppEvent.photoUpload(at: _at, bytes: 1, width: 768),
        AppEvent.cooked(
          at: _at,
          suggestion: const Suggestion(
            menu: '김치찌개',
            source: SuggestionSource.generated,
            missing: [],
            reason: '',
          ),
          stale: false,
        ),
      ]);
      expect(metrics.manualEdits, 0);
    });
  });

  group('debug 쿼리 파라미터 (ADR-0004)', () {
    test('테스트(비웹) 환경에는 쿼리가 없어 꺼져 있다', () {
      // Uri.base가 파일 URI라 debug 파라미터가 붙을 자리가 없다.
      expect(debugFooterEnabled(), isFalse);
    });

    test('?debug와 ?debug=1을 둘 다 인정한다', () {
      expect(
        Uri.parse('https://x/?debug').queryParameters.containsKey('debug'),
        isTrue,
      );
      expect(
        Uri.parse('https://x/?debug=1').queryParameters.containsKey('debug'),
        isTrue,
      );
      expect(
        Uri.parse('https://x/').queryParameters.containsKey('debug'),
        isFalse,
      );
    });
  });
}
