// 지나간 섹션의 요약 한 줄 — 탭하면 다시 펼쳐진다(G1 #8 "지나간 섹션은 요약 한 줄").
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class SectionSummary extends StatelessWidget {
  const SectionSummary({
    super.key,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;

  /// 접힌 섹션에 붙는 경고 같은 것 — "다시 제안" 배너가 여기 온다.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        constraints: const BoxConstraints(minHeight: Space.rowMin),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.subhead.copyWith(color: AppColors.muted),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: Space.sm),
            ],
            const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// 재료를 손봐서 아래 제안이 낡았다 — 갱신을 권한다(ADR-0001).
class RematchBanner extends StatelessWidget {
  const RematchBanner({super.key, required this.onRematch});

  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('rematch-banner'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.actionTint,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '재료가 바뀌었어요. 다시 골라볼까요?',
              style: AppTypography.subhead.copyWith(color: AppColors.action),
            ),
          ),
          const SizedBox(width: Space.sm),
          SizedBox(
            height: Space.touchMin,
            child: FilledButton(
              key: const Key('rematch-button'),
              onPressed: onRematch,
              child: const Text('다시 제안'),
            ),
          ),
        ],
      ),
    );
  }
}
