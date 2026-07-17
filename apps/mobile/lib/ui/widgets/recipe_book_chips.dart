// 레시피 북 재료 중 인식되지 않은 것들의 강조 칩 — 질문 2 검증 확률을 올리는 장치(B 이식, G1 #8).
import 'package:flutter/material.dart';

import '../../domain/app_event.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// "자주 쓰는 재료" 칩과 달리 강조 스타일이다 — 저장 레시피와 연결될 재료를 놓치지 않게.
class RecipeBookChips extends StatelessWidget {
  const RecipeBookChips({super.key, required this.names, required this.onAdd});

  final List<String> names;
  final void Function(String name, EditPath path) onAdd;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text(
            '레시피 북에 있는 재료예요 — 혹시 있나요?',
            style: AppTypography.footnote.copyWith(color: AppColors.muted),
          ),
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final name in names)
              InkWell(
                key: Key('recipe-book-chip-$name'),
                onTap: () => onAdd(name, EditPath.recipeBookChip),
                borderRadius: BorderRadius.circular(Radii.chip),
                child: Container(
                  constraints: const BoxConstraints(minHeight: Space.touchMin),
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.actionTint,
                    borderRadius: BorderRadius.circular(Radii.chip),
                    border: Border.all(color: AppColors.action, width: 1),
                  ),
                  child: Text(
                    name,
                    style: AppTypography.subhead.copyWith(
                      color: AppColors.action,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
