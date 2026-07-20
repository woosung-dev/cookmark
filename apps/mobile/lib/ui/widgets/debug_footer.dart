// 파운더 전용 측정 푸터 — 앱바 타이틀 롱프레스로 연 세션에만 존재한다(#143, ADR-0004).
//
// 배우자 화면에는 위젯 트리에조차 없다. "숨김"이 아니라 "부재"다 —
// 숨겨두면 언젠가 보인다.
import 'package:flutter/material.dart';

import '../../domain/debug_metrics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class DebugFooter extends StatelessWidget {
  const DebugFooter({super.key, required this.metrics});

  final DebugMetrics metrics;

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
          ],
        ),
      ),
    );
  }
}
