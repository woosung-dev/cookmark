// 제안 상세 — 카드 탭으로 들어오는 유일한 push 화면(P4, ADR-0007). 큰 사진·있는/부족 재료·이거 했어요.
//
// 사진·매칭%·담기·이어보기 타임스탬프는 백엔드 이월 placeholder다. pop만 하고 push하지 않는다.
import 'package:flutter/material.dart';

import '../domain/suggestion.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'widgets/photo_placeholder.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/suggestion_card.dart';

/// 상세에서 메인으로 되돌리는 결과. cooked만 결과와 함께 pop한다 — 토스트/undo는 메인이 띄운다(오펀 방지).
enum SuggestionDetailAction { cooked }

class SuggestionDetailPage extends StatelessWidget {
  const SuggestionDetailPage({
    super.key,
    required this.suggestion,
    required this.rank,
    required this.onOpenRecipe,
    this.available = const [],
  });

  final Suggestion suggestion;

  /// 1-based 순위 — 사진 위 배지에 쓴다.
  final int rank;

  /// "영상 보기" — 메인의 _openRecipe에 바인딩(로그 + 새 탭). pop하지 않는다.
  final VoidCallback onOpenRecipe;

  /// 있는 재료(레시피 재료 − 부족) — 저장 제안만 채워지고, 비면 섹션을 생략한다(파생, 저장소 무변경).
  final List<String> available;

  @override
  Widget build(BuildContext context) {
    final saved = suggestion.source == SuggestionSource.saved;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 큰 사진 + 뒤로 버튼 + (영상 보기 pill, 저장 제안만).
                  Stack(
                    children: [
                      const PhotoPlaceholder(aspectRatio: 16 / 9, iconSize: 56),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.sm),
                            child: _CircleButton(
                              key: const Key('detail-back'),
                              icon: Icons.arrow_back,
                              onTap: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                      ),
                      if (saved)
                        Positioned(
                          right: Space.md,
                          bottom: Space.md,
                          child: _VideoPill(
                            key: Key('detail-open-recipe-${suggestion.menu}'),
                            onTap: onOpenRecipe,
                          ),
                        ),
                    ],
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
                                style: AppTypography.largeTitle,
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            _DetailLabelBadge(label: suggestion.label),
                          ],
                        ),
                        const SizedBox(height: Space.sm),
                        // 출처 + 매칭%(placeholder).
                        Row(
                          children: [
                            Icon(
                              saved
                                  ? Icons.bookmark_outline
                                  : Icons.auto_awesome_outlined,
                              size: 14,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(
                              '${saved ? '내 레시피 북' : 'AI 제안'} · ${matchPercentOf(suggestion)}% 일치',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        if (suggestion.reason.isNotEmpty) ...[
                          const SizedBox(height: Space.md),
                          Text(
                            suggestion.reason,
                            style: AppTypography.subhead.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                        if (available.isNotEmpty) ...[
                          const SizedBox(height: Space.xxl),
                          _SectionLabel(text: '있는 재료 · ${available.length}'),
                          const SizedBox(height: Space.sm),
                          _IngredientCard(
                            children: [
                              for (final name in available)
                                _HaveRow(name: name),
                            ],
                          ),
                        ],
                        if (suggestion.missing.isNotEmpty) ...[
                          const SizedBox(height: Space.xxl),
                          _SectionLabel(
                            text: '부족 재료 · ${suggestion.missing.length}',
                          ),
                          const SizedBox(height: Space.sm),
                          _IngredientCard(
                            children: [
                              for (final m in suggestion.missing)
                                _MissingRow(missing: m),
                            ],
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            '쿠팡·마켓컬리에서 담을 수 있어요.',
                            style: AppTypography.footnote.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 하단 고정 "이거 했어요" — pop-with-result로 메인이 토스트/undo를 이어받는다.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: SizedBox(
                width: double.infinity,
                height: Space.touchMin + 4,
                child: PressableScale(
                  child: FilledButton(
                    key: Key('detail-cooked-${suggestion.menu}'),
                    onPressed: () =>
                        Navigator.pop(context, SuggestionDetailAction.cooked),
                    child: const Text('이거 했어요'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 위 원형 반투명 버튼 — 뒤로가기.
class _CircleButton extends StatelessWidget {
  const _CircleButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1D1D1F), // 반투명 먹빛 — 사진 위 가독성.
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Icon(icon, size: 20, color: AppColors.onAction),
        ),
      ),
    );
  }
}

/// 사진 위 "영상 보기" pill — 저장 제안만. (목업의 이어보기 타임스탬프는 데이터가 없어 생략, 정직.)
class _VideoPill extends StatelessWidget {
  const _VideoPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1D1D1F),
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow, size: 18, color: AppColors.onAction),
              const SizedBox(width: Space.xs),
              Text(
                '영상 보기',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상세용 라벨 배지 — 카드와 같은 색/아이콘(styleOf 공유), 단 카드의 키는 달지 않는다(중복 방지).
class _DetailLabelBadge extends StatelessWidget {
  const _DetailLabelBadge({required this.label});

  final SuggestionLabel label;

  @override
  Widget build(BuildContext context) {
    final style = styleOf(label);
    return Container(
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Space.xs),
      child: Text(text, style: AppTypography.headline),
    );
  }
}

/// 인셋 그룹 리스트 카드 — 재료 행을 하나로 묶고 hairline으로 나눈다(DESIGN.md §4·§7).
class _IngredientCard extends StatelessWidget {
  const _IngredientCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(indent: Space.lg),
            child,
          ],
        ],
      ),
    );
  }
}

/// 있는 재료 행 — 채워진 체크 + 이름.
class _HaveRow extends StatelessWidget {
  const _HaveRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Space.rowMin,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 20, color: AppColors.action),
            const SizedBox(width: Space.md),
            Expanded(child: Text(name, style: AppTypography.headline)),
          ],
        ),
      ),
    );
  }
}

/// 부족 재료 행 — 빈 원 + 이름 + '담기'(장식, 백엔드 이월이라 동작 없음).
class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.missing});

  final MissingIngredient missing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Space.rowMin,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Row(
          children: [
            const Icon(
              Icons.radio_button_unchecked,
              size: 20,
              color: AppColors.muted,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                missing.resolvedBySubstitute
                    ? '${missing.name}→${missing.substitute}'
                    : missing.name,
                style: AppTypography.headline,
              ),
            ),
            // 담기 — 장식 태그(백엔드 카트 미구현, ADR-0007). 죽은 버튼 대신 비상호작용 칩.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.hairline),
                borderRadius: BorderRadius.circular(Radii.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_shopping_cart,
                    size: 14,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: Space.xs),
                  Text(
                    '담기',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.muted,
                    ),
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
