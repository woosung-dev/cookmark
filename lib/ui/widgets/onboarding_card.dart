// 첫 방문 상태 — 업로드 존 자리에 뜨는 "믿고 보는 레시피 3개만 저장해두세요" 카드(G1 #8).
//
// 별도 온보딩 화면이 아니다. 메인의 한 상태이고, 저장이 그 자리에서 완결된다(ADR-0001).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../recipe_book_controller.dart';
import 'recipe_form.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.savedCount,
    required this.saving,
    required this.onSubmit,
    required this.onSkip,
  });

  final int savedCount;
  final bool saving;
  final void Function(String url, String title) onSubmit;

  /// 건너뛰기는 허용된다 — 빈 레시피 북으로도 루프는 돈다(G1 #8).
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('onboarding-card'),
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '믿고 보는 레시피 3개만 저장해두세요',
                  style: AppTypography.headline,
                ),
              ),
              Text(
                '$savedCount/$trustedRecipeGoal',
                key: const Key('onboarding-counter'),
                style: AppTypography.numeric.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            '냉장고 사진과 맞춰볼 근거가 됩니다.',
            style: AppTypography.subhead.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: Space.xl),
          RecipeForm(saving: saving, onSubmit: onSubmit),
          const SizedBox(height: Space.sm),
          TextButton(
            key: const Key('onboarding-skip'),
            onPressed: onSkip,
            child: const Text('나중에 할게요'),
          ),
        ],
      ),
    );
  }
}

/// 3개 미만일 때 상시 뜨는 넛지 칩 — 건너뛴 사람에게도 길을 남긴다(G1 #8).
class RecipeNudgeChip extends StatelessWidget {
  const RecipeNudgeChip({
    super.key,
    required this.savedCount,
    required this.onTap,
  });

  final int savedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: const Key('recipe-nudge-chip'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: Container(
          constraints: const BoxConstraints(minHeight: Space.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.actionTint,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Text(
            '믿고 보는 레시피 담기 $savedCount/$trustedRecipeGoal',
            style: AppTypography.subhead.copyWith(color: AppColors.action),
          ),
        ),
      ),
    );
  }
}
