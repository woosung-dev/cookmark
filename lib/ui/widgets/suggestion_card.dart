// 제안 카드 — "오늘 할 3개"의 한 장(G1 #8 확정 구성, DESIGN.md §7).
import 'package:flutter/material.dart';

import '../../domain/suggestion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// 라벨의 색과 아이콘 — 색만으로 말하지 않는다(DESIGN.md §8 "색+아이콘 이중 신호").
///
/// 색 매핑의 정본은 DESIGN.md §2다. 스펙 #13 본문은 초록/호박/파랑이라 적었지만
/// 2026-07-15 사용자 결정으로 DESIGN.md(그린/앰버/그레이)를 택했다 — 근거는 context-notes.
({Color fg, Color bg, IconData icon}) _styleOf(SuggestionLabel label) =>
    switch (label) {
      SuggestionLabel.ready => (
        fg: AppColors.goFg,
        bg: AppColors.goBg,
        icon: Icons.check_circle_outline,
      ),
      SuggestionLabel.buyOne => (
        fg: AppColors.buyFg,
        bg: AppColors.buyBg,
        icon: Icons.add_shopping_cart,
      ),
      SuggestionLabel.maybe => (
        fg: AppColors.maybeFg,
        bg: AppColors.maybeBg,
        icon: Icons.swap_horiz,
      ),
    };

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onOpenRecipe,
  });

  final Suggestion suggestion;

  /// "레시피 보기" — 저장 카드만 가진다.
  final VoidCallback onOpenRecipe;

  @override
  Widget build(BuildContext context) {
    final saved = suggestion.source == SuggestionSource.saved;

    return Container(
      key: Key('suggestion-card-${suggestion.menu}'),
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
              _LabelBadge(label: suggestion.label),
              const SizedBox(width: Space.sm),
              _SourceBadge(source: suggestion.source),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(suggestion.menu, style: AppTypography.largeTitle),
          if (suggestion.missing.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            _MissingChips(missing: suggestion.missing),
          ],
          if (suggestion.reason.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              suggestion.reason,
              style: AppTypography.subhead.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: Space.xl),
          if (saved)
            SizedBox(
              height: Space.touchMin,
              child: OutlinedButton(
                key: Key('open-recipe-${suggestion.menu}'),
                onPressed: onOpenRecipe,
                child: const Text('레시피 보기'),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabelBadge extends StatelessWidget {
  const _LabelBadge({required this.label});

  final SuggestionLabel label;

  @override
  Widget build(BuildContext context) {
    final style = _styleOf(label);
    return Container(
      key: Key('label-badge-${label.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.fg),
          const SizedBox(width: Space.xs),
          Text(
            label.text,
            style: AppTypography.caption.copyWith(color: style.fg),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final SuggestionSource source;

  @override
  Widget build(BuildContext context) {
    final saved = source == SuggestionSource.saved;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          saved ? Icons.bookmark : Icons.auto_awesome,
          size: 14,
          color: AppColors.muted,
        ),
        const SizedBox(width: Space.xs),
        Text(
          saved ? '내 레시피 북' : 'AI 제안',
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 부족 재료 칩 ≤3. 대체재로 해소되면 "우유→두유" 화살표 + 흐림(G1 #8).
class _MissingChips extends StatelessWidget {
  const _MissingChips({required this.missing});

  final List<MissingIngredient> missing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final m in missing)
          Opacity(
            // 대체재가 있으면 흐리게 — 사야 하는 게 아니라 이미 해소된 것이다.
            opacity: m.resolvedBySubstitute ? 0.55 : 1,
            child: Container(
              key: Key('missing-chip-${m.name}'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                color: m.resolvedBySubstitute
                    ? AppColors.maybeBg
                    : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(Radii.chip),
              ),
              child: Text(
                m.resolvedBySubstitute ? '${m.name}→${m.substitute}' : m.name,
                style: AppTypography.caption.copyWith(
                  color: m.resolvedBySubstitute
                      ? AppColors.maybeFg
                      : AppColors.danger,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
