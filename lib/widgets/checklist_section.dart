// 재료 체크리스트 — confidence 3단 초기 상태를 렌더한다(ADR-0003과 한 몸)
import 'package:flutter/material.dart';

import '../models/ingredient.dart';
import '../theme/app_colors.dart';

/// 인식 결과를 확정 목록으로 다듬는 UI.
///
/// #14는 **초기 상태 렌더까지**다 — 행 탭 토글과 수동 수정 계측은 #15가 붙인다.
/// 계측 없이 토글만 먼저 내보내면 사용자가 가한 수정이 로그에 안 남아
/// 킬 기준(ADR-0003)의 원시 데이터가 조용히 유실된다.
class ChecklistSection extends StatelessWidget {
  const ChecklistSection({required this.ingredients, super.key});

  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final confident = ingredients
        .where((i) => i.confidence != Confidence.low)
        .toList();
    final uncertain = ingredients
        .where((i) => i.confidence == Confidence.low)
        .toList();

    return ListView(
      key: const Key('checklist'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (ingredients.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '재료를 직접 추가해 주세요.',
              style: t.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ),
        for (final i in confident) _IngredientRow(ingredient: i),
        if (uncertain.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '확실하지 않아요',
              key: const Key('uncertain-group-header'),
              style: t.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ),
          // 흐린 그룹 — 해제된 채로 두면 매칭에서 빠진다. 훑고 지나가도 되는 자리다.
          Opacity(
            opacity: 0.6,
            child: Column(
              children: [
                for (final i in uncertain) _IngredientRow(ingredient: i),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 재료 한 행. 행 높이는 48px 이상(G1 #8) — #15가 행 전체를 탭 타깃으로 만든다.
class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: Key('ingredient-${ingredient.name}'),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _ConfidenceBox(
            checked: ingredient.checked,
            confidence: ingredient.confidence,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(ingredient.name, style: t.bodyLarge)),
        ],
      ),
    );
  }
}

/// confidence 3단의 시각 신호. high=채운 체크 / medium=체크+물음표 점 / low=빈 체크.
class _ConfidenceBox extends StatelessWidget {
  const _ConfidenceBox({required this.checked, required this.confidence});

  final bool checked;
  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: checked ? AppColors.action : AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: checked ? AppColors.action : AppColors.hairline,
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(Icons.check, size: 16, color: AppColors.onAction)
                : null,
          ),
          // medium — "체크는 했는데 확인해 보세요"를 점 하나로 말한다.
          if (confidence == Confidence.medium)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                key: const Key('medium-dot'),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.buyFg,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
