// 제안 카드 — "오늘 할 3개"의 한 장(목업 풀 패리티, 사진·순위·매칭%·영상 보기).
//
// 사진과 매칭%는 백엔드 이월이라 placeholder다 — 자산/점수가 붙으면 실값으로 교체된다.
import 'package:flutter/material.dart';

import '../../domain/suggestion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'photo_placeholder.dart';
import 'pressable_scale.dart';

/// 라벨의 색과 아이콘 — 색만으로 말하지 않는다(DESIGN.md §8 "색+아이콘 이중 신호").
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
    required this.rank,
    required this.onOpenRecipe,
    required this.onCooked,
    this.onTap,
  });

  final Suggestion suggestion;

  /// 1-based 순위 — 사진 위 배지에 쓴다.
  final int rank;

  /// "영상 보기" — 저장 카드만 가진다.
  final VoidCallback onOpenRecipe;

  /// "이거 했어요" — 성공 지표 2의 판정 장치.
  final VoidCallback onCooked;

  /// 카드 탭 → 제안 상세(P4). null이면 탭 비활성.
  final VoidCallback? onTap;

  /// 매칭% placeholder — 실 점수는 백엔드 이월. 부족(대체 미해소) 수로 근사한다.
  int get _matchPercent {
    final missing = suggestion.missing
        .where((m) => !m.resolvedBySubstitute)
        .length;
    return switch (missing) {
      0 => 96,
      1 => 88,
      2 => 79,
      _ => 72,
    };
  }

  @override
  Widget build(BuildContext context) {
    final saved = suggestion.source == SuggestionSource.saved;

    return Container(
      key: Key('suggestion-card-${suggestion.menu}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhotoPlaceholder(
              aspectRatio: 16 / 9,
              overlay: MatchBadge(rank: rank, percent: _matchPercent),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestion.menu,
                          style: AppTypography.title,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      _LabelBadge(label: suggestion.label),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  _SourceBadge(source: suggestion.source),
                  if (suggestion.missing.isNotEmpty) ...[
                    const SizedBox(height: Space.md),
                    _MissingChips(missing: suggestion.missing),
                  ],
                  if (suggestion.reason.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Text(
                      suggestion.reason,
                      style: AppTypography.subhead.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  Row(
                    children: [
                      if (saved) ...[
                        Expanded(
                          child: SizedBox(
                            height: Space.touchMin + 4,
                            child: OutlinedButton.icon(
                              key: Key('open-recipe-${suggestion.menu}'),
                              onPressed: onOpenRecipe,
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('영상 보기'),
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: Space.touchMin + 4,
                          child: PressableScale(
                            child: FilledButton(
                              key: Key('cooked-${suggestion.menu}'),
                              onPressed: onCooked,
                              child: const Text('이거 했어요'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
          // 스트로크 통일 — 은유 아이콘은 outlined로(DESIGN.md §7).
          saved ? Icons.bookmark_outline : Icons.auto_awesome_outlined,
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
