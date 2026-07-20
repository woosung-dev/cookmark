// 파운더 전용 측정 푸터 — 앱바 타이틀 롱프레스로 연 세션에만 존재한다(#143, ADR-0004).
//
// 배우자 화면에는 위젯 트리에조차 없다. "숨김"이 아니라 "부재"다 —
// 숨겨두면 언젠가 보인다.
import 'package:flutter/material.dart';

import '../../domain/debug_metrics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class DebugFooter extends StatelessWidget {
  const DebugFooter({super.key, required this.metrics, required this.onReset});

  final DebugMetrics metrics;

  /// D0 직전 기록 초기화(#144). 확인 단계를 띄우는 건 부모(main_page)이고 여기는 알리기만 한다 —
  /// 위젯은 영속 API를 직접 부르지 않는다(AGENTS.md 경계 규칙).
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('debug-footer'),
      margin: const EdgeInsets.only(top: Space.xxxl),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: DefaultTextStyle(
        style: AppTypography.numeric.copyWith(color: AppColors.muted),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '측정 (debug)',
              style: AppTypography.caption.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: Space.xs),
            Text('인식 ${metrics.recognitionLatencyMs ?? '-'}ms'),
            Text('매칭 ${metrics.matchingLatencyMs ?? '-'}ms'),
            Text(
              '토큰 ${metrics.lastTokens ?? '-'} · ${metrics.lastModel ?? '-'}',
            ),
            Text('누적 원가 \$${metrics.totalCostUsd.toStringAsFixed(5)}'),
            Text('수동 수정 ${metrics.manualEdits}'),
            Text('이벤트 ${metrics.eventCount}'),
            const SizedBox(height: Space.md),
            // 푸터 안에 있으므로 배우자에게는 도달 경로가 없다 — 푸터를 열 줄 모르면
            // 이 버튼도 못 본다. 파운더의 모든 동작이 앱 안에서 끝난다(#144).
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('reset-record'),
                onPressed: onReset,
                child: const Text('기록 초기화'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
