// 재료 체크리스트 — 인식 결과를 확정 목록으로 다듬는 UI(CONTEXT.md 글로서리).
import 'package:flutter/material.dart';

import '../../domain/ingredient.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'confidence_checkbox.dart';

/// confidence 3단 초기 상태로 재료를 보여준다 — high·medium은 본문에, low는 "확실하지 않아요" 흐린 그룹에.
///
/// 조작(행 탭 토글·추가 바·칩)은 #15에서 붙는다. 여기서는 초기 상태의 렌더가 전부다.
class ChecklistSection extends StatelessWidget {
  const ChecklistSection({super.key, required this.ingredients});

  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    final confident = [
      for (final i in ingredients)
        if (i.confidence != Confidence.low) i,
    ];
    final uncertain = [
      for (final i in ingredients)
        if (i.confidence == Confidence.low) i,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confident.isEmpty && uncertain.isEmpty)
          const _EmptyChecklistHint()
        else
          _IngredientGroup(ingredients: confident),
        if (uncertain.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
            child: Text(
              '확실하지 않아요',
              style: AppTypography.footnote.copyWith(color: AppColors.muted),
            ),
          ),
          // 흐린 그룹 — 여기 있는 건 해제 상태이고, 그냥 두면 매칭에서 빠진다.
          Opacity(
            opacity: 0.6,
            child: _IngredientGroup(ingredients: uncertain),
          ),
        ],
      ],
    );
  }
}

class _IngredientGroup extends StatelessWidget {
  const _IngredientGroup({required this.ingredients});

  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    if (ingredients.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, ingredient) in ingredients.indexed) ...[
            if (index > 0) const Divider(indent: Space.lg),
            _IngredientRow(ingredient: ingredient),
          ],
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: ingredient.checked,
      label: ingredient.name,
      child: Container(
        constraints: const BoxConstraints(minHeight: Space.rowMin),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            ConfidenceCheckbox(
              checked: ingredient.checked,
              confidence: ingredient.confidence,
            ),
            const SizedBox(width: Space.md),
            Expanded(child: Text(ingredient.name, style: AppTypography.body)),
          ],
        ),
      ),
    );
  }
}

class _EmptyChecklistHint extends StatelessWidget {
  const _EmptyChecklistHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Text(
        '아래에서 재료를 직접 추가해 주세요.',
        style: AppTypography.body.copyWith(color: AppColors.muted),
      ),
    );
  }
}
