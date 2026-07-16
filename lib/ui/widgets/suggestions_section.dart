// "오늘 할 3개" 섹션 — 세로 스택 ≤3 + 투명성 줄(G1 #8).
import 'package:flutter/material.dart';

import '../../domain/suggestion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'skeleton.dart';
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
          // 빈 상태도 구성한다 — 아이콘 + 문구(DESIGN.md §7, 다른 빈 상태와 동일 패턴).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.no_meals_outlined,
                  size: 40,
                  color: AppColors.hairline,
                ),
                const SizedBox(height: Space.md),
                Text(
                  '지금 재료로 만들 만한 걸 찾지 못했어요.',
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              ],
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

/// 매칭 대기 — "레시피 북 N개와 맞춰보는 중"(C 이식, G1 #8) + 곧 나타날 제안 카드 스켈레톤(DESIGN.md §7).
///
/// 무엇을 기다리는지 문구로 알리고, 원형 스피너 대신 결과의 모양을 미리 보여준다.
class MatchingLoading extends StatefulWidget {
  const MatchingLoading({super.key, required this.recipeCount});

  final int recipeCount;

  @override
  State<MatchingLoading> createState() => _MatchingLoadingState();
}

class _MatchingLoadingState extends State<MatchingLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.lg),
          child: Text(
            '레시피 북 ${widget.recipeCount}개와 맞춰보는 중',
            key: const Key('matching-message'),
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
        ),
        _SuggestionCardSkeleton(shimmer: _shimmer),
        const SizedBox(height: Space.md),
        _SuggestionCardSkeleton(shimmer: _shimmer),
      ],
    );
  }
}

/// 제안 카드의 모양을 미리 보여주는 스켈레톤 — surface·r16·flat(카드와 같은 형태).
class _SuggestionCardSkeleton extends StatelessWidget {
  const _SuggestionCardSkeleton({required this.shimmer});

  final Animation<double> shimmer;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Shimmer(
                animation: shimmer,
                child: const SkeletonBox(
                  width: 68,
                  height: 20,
                  radius: Radii.pill,
                ),
              ),
              const SizedBox(width: Space.sm),
              Shimmer(
                animation: shimmer,
                child: const SkeletonBox(
                  width: 56,
                  height: 14,
                  radius: Radii.pill,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Shimmer(
            animation: shimmer,
            child: const SkeletonBox(
              width: 160,
              height: 26,
              radius: Radii.pill,
            ),
          ),
          const SizedBox(height: Space.md),
          Shimmer(
            animation: shimmer,
            child: const SkeletonBox(
              width: double.infinity,
              height: 14,
              radius: Radii.pill,
            ),
          ),
          const SizedBox(height: Space.xl),
          Shimmer(
            animation: shimmer,
            child: const SkeletonBox(
              width: double.infinity,
              height: 52,
              radius: Radii.control,
            ),
          ),
        ],
      ),
    );
  }
}
