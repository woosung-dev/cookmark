// "오늘 할 3개" 섹션 — 세로 스택 ≤3 + 투명성 줄(G1 #8).
import 'package:flutter/material.dart';

import '../../domain/suggestion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'suggestion_card.dart';

class SuggestionsSection extends StatelessWidget {
  const SuggestionsSection({
    super.key,
    required this.suggestions,
    required this.excludedCount,
    required this.onOpenRecipe,
    required this.onCooked,
  });

  final List<Suggestion> suggestions;
  final int excludedCount;
  final void Function(Suggestion) onOpenRecipe;
  final void Function(Suggestion) onCooked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: Space.xs, bottom: Space.md),
          child: Text('오늘 할 3개', style: AppTypography.largeTitle),
        ),
        if (suggestions.isEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Text(
              '지금 재료로 만들 만한 걸 찾지 못했어요.',
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
          )
        else
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: SuggestionCard(
                suggestion: suggestion,
                onOpenRecipe: () => onOpenRecipe(suggestion),
                onCooked: () => onCooked(suggestion),
              ),
            ),
        if (excludedCount > 0) ...[
          const SizedBox(height: Space.sm),
          // 투명성 줄 — 시스템이 뭘 걸렀는지 알린다(G1 #8).
          Text(
            '부족 4개 이상이라 제외한 메뉴 $excludedCount개',
            key: const Key('transparency-line'),
            style: AppTypography.footnote.copyWith(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// 매칭 대기 — "레시피 북 N개와 맞춰보는 중"(C 이식, G1 #8). 무엇을 기다리는지 알린다.
class MatchingLoading extends StatelessWidget {
  const MatchingLoading({super.key, required this.recipeCount});

  final int recipeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: Space.xxxl,
        horizontal: Space.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Text(
        '레시피 북 $recipeCount개와 맞춰보는 중',
        key: const Key('matching-message'),
        style: AppTypography.body.copyWith(color: AppColors.muted),
        textAlign: TextAlign.center,
      ),
    );
  }
}
