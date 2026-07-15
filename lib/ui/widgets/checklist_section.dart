// 재료 체크리스트 — 인식 결과를 확정 목록으로 다듬는 UI(CONTEXT.md 글로서리).
import 'package:flutter/material.dart';

import '../../domain/ingredient.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'confidence_checkbox.dart';

/// confidence 3단 초기 상태로 재료를 보여주고, 행 전체 탭으로 토글한다.
///
/// 제스처는 행 탭 하나뿐이다 — 스와이프·롱프레스·삭제 버튼 없음(G1 #8). 삭제 개념 자체가 없다.
/// 해제가 곧 매칭 제외다.
class ChecklistSection extends StatelessWidget {
  const ChecklistSection({
    super.key,
    required this.ingredients,
    required this.onToggle,
  });

  final List<Ingredient> ingredients;
  final void Function(String name) onToggle;

  @override
  Widget build(BuildContext context) {
    // 뭉뚱그림 항목은 본문에 섞이지 않는다 — 점선 칩으로 따로 나간다(ADR-0002).
    final items = [
      for (final i in ingredients)
        if (!i.isVague) i,
    ];
    final confident = [
      for (final i in items)
        if (i.confidence != Confidence.low) i,
    ];
    final uncertain = [
      for (final i in items)
        if (i.confidence == Confidence.low) i,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confident.isEmpty && uncertain.isEmpty)
          const _EmptyChecklistHint()
        else
          _IngredientGroup(ingredients: confident, onToggle: onToggle),
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
            child: _IngredientGroup(ingredients: uncertain, onToggle: onToggle),
          ),
        ],
      ],
    );
  }
}

class _IngredientGroup extends StatelessWidget {
  const _IngredientGroup({required this.ingredients, required this.onToggle});

  final List<Ingredient> ingredients;
  final void Function(String name) onToggle;

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
            _IngredientRow(ingredient: ingredient, onToggle: onToggle),
          ],
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, required this.onToggle});

  final Ingredient ingredient;
  final void Function(String name) onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: ingredient.checked,
      label: ingredient.name,
      button: true,
      child: InkWell(
        // 행 전체가 탭 타깃이다 — 체크박스만 노리게 하지 않는다.
        key: Key('ingredient-row-${ingredient.name}'),
        onTap: () => onToggle(ingredient.name),
        child: Container(
          constraints: const BoxConstraints(minHeight: Space.rowMin),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: ConfidenceCheckbox(
                  checked: ingredient.checked,
                  confidence: ingredient.confidence,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  ingredient.name,
                  style: AppTypography.body.copyWith(
                    color: ingredient.checked
                        ? AppColors.text
                        : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
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
