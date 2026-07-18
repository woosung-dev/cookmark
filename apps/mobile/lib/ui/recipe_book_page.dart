// 레시피 북 — 사용자가 신뢰하는 저장 레시피의 화면. 앱의 두 번째이자 마지막 화면(ADR-0001).
import 'package:flutter/material.dart';

import '../data/server_recipe_repository.dart';
import '../domain/recipe.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'backup_controller.dart';
import 'recipe_book_controller.dart';
import 'widgets/backup_section.dart';
import 'widgets/photo_placeholder.dart';
import 'widgets/recipe_add_failure_card.dart';
import 'widgets/recipe_form.dart';
import 'widgets/skeleton.dart';

class RecipeBookPage extends StatelessWidget {
  const RecipeBookPage({
    super.key,
    required this.controller,
    required this.backupController,
  });

  final RecipeBookController controller;
  final BackupController backupController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('레시피 북')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, backupController]),
          builder: (context, _) {
            final recipes = controller.recipes;
            final syncState = controller.syncState;
            return ListView(
              padding: const EdgeInsets.all(Space.screenPad),
              children: [
                // 저장 현황 + 가짜 과금 크롬 — 파일럿용 UI만이고 어떤 저장도 막지 않는다(ADR-0007).
                _SavedQuota(count: recipes.length),
                const SizedBox(height: Space.xl),
                RecipeForm(
                  saving: controller.saving,
                  // 하이드레이트 실패 상태의 저장은 컨트롤러가 버린다 — 입력도 막아 정직하게(#121).
                  enabled: syncState != RecipeSyncState.error,
                  onSubmit: (url, title) =>
                      controller.add(url: url, title: title),
                ),
                // 서버 모드에서 저장이 실패하면(502=미저장) 폼 아래 인라인 카드로 재시도를 연다(#121).
                if (controller.addFailure != null) ...[
                  const SizedBox(height: Space.md),
                  RecipeAddFailureCard(
                    kind: controller.addFailure!,
                    onRetry: () {
                      final failed = controller.failedAdd!;
                      controller.add(url: failed.url, title: failed.title);
                    },
                    onDismiss: controller.clearAddFailure,
                  ),
                ],
                const SizedBox(height: Space.xxl),
                if (syncState == RecipeSyncState.loading)
                  // 정직한 로딩 — 스피너 대신 곧 나타날 리스트의 모양을 정적으로 잡는다(DESIGN.md §7).
                  const _RecipeListSkeleton()
                else if (syncState == RecipeSyncState.error)
                  _SyncErrorCard(
                    kind: controller.syncFailure,
                    onRetry: controller.hydrate,
                  )
                else if (recipes.isEmpty)
                  const _EmptyRecipes()
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Space.xs,
                      bottom: Space.sm,
                    ),
                    child: Text(
                      '저장한 레시피 · ${recipes.length}',
                      style: AppTypography.footnote.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  // iOS 인셋 그룹 리스트 — 카드 하나에 셀을 쌓고 hairline으로 나눈다(DESIGN.md §4·§7).
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Radii.card),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (index, recipe) in recipes.indexed) ...[
                          if (index > 0) const Divider(indent: Space.lg),
                          _RecipeRow(
                            recipe: recipe,
                            onRemove: () => controller.remove(recipe.url),
                            retrying: controller.retryingUrl == recipe.url,
                            onRetry: () =>
                                controller.retryExtraction(recipe.url),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // 백업은 이 화면 최하단이다(G1 #8).
                const SizedBox(height: Space.xxxl),
                BackupSection(controller: backupController),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 레시피 북의 리스트 셀 — 좌 아이콘 + 제목(headline) + 보조(footnote muted) + 우 액션(DESIGN.md §7).
///
/// 바깥 카드는 부모가 하나로 묶는다(인셋 그룹 리스트) — 셀은 hairline으로만 나뉜다.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    required this.onRemove,
    required this.retrying,
    required this.onRetry,
  });

  final Recipe recipe;
  final VoidCallback onRemove;

  /// 이 레시피의 재추출이 도는 중인가 — 진행 표시는 자기 자리에서만 뜬다.
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('recipe-tile-${recipe.url}'),
      constraints: const BoxConstraints(minHeight: Space.rowMin),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 좌 썸네일 — 음식 사진 자리(홍시-틴트 placeholder, 백엔드 오면 og:image로 교체, ADR-0007).
          const PhotoPlaceholder(
            width: 44,
            height: 44,
            borderRadius: Radii.photo,
            icon: Icons.restaurant_menu,
            iconSize: 22,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.title, style: AppTypography.headline),
                const SizedBox(height: Space.xs),
                // 재료 0개면 이 레시피는 영원히 매칭되지 않는다 — 그 자리에서 복구할 길을 준다
                // (US 22 인라인 원칙, 에러 화면 없음).
                if (recipe.ingredients.isEmpty) ...[
                  Text(
                    '재료를 알아내지 못했어요 — 매칭에는 제목만 쓰입니다.',
                    style: AppTypography.footnote.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  if (retrying)
                    Text(
                      '재료를 다시 찾는 중이에요…',
                      style: AppTypography.footnote.copyWith(
                        color: AppColors.muted,
                      ),
                    )
                  else
                    TextButton(
                      key: Key('recipe-retry-${recipe.url}'),
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('다시 시도'),
                    ),
                ] else
                  // 출처(url host 파생) + 재료를 한 메타 줄로 — 재료 문자열은 매칭 근거라 보존한다.
                  Text(
                    '${_sourceLabel(recipe.url)} · ${recipe.ingredients.join(' · ')}',
                    style: AppTypography.footnote.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          IconButton(
            key: Key('recipe-remove-${recipe.url}'),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.muted,
            tooltip: '삭제',
          ),
        ],
      ),
    );
  }
}

/// url host로 출처 라벨을 파생한다 — 모델엔 source 필드가 없다(렌더타임 파생, 저장소 무변경).
String _sourceLabel(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return '링크';
  if (host.contains('youtu')) return '유튜브';
  if (host.contains('instagram')) return '인스타그램';
  if (host.contains('tiktok')) return '틱톡';
  return '블로그';
}

/// 저장 현황 + 가짜 과금 크롬(파일럿용 UI만, ADR-0007) — 실 카운트 × 가짜 상한 30, 저장을 막지 않는다.
class _SavedQuota extends StatelessWidget {
  const _SavedQuota({required this.count});

  final int count;
  static const _cap = 30;

  @override
  Widget build(BuildContext context) {
    final remaining = (_cap - count).clamp(0, _cap);
    final progress = (count / _cap).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$count / $_cap',
                        style: AppTypography.numeric.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const TextSpan(
                        text: ' 저장됨',
                        style: AppTypography.headline,
                      ),
                    ],
                  ),
                ),
              ),
              // "무료" 배지 — 가짜 플랜 표시.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.actionTint,
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Text(
                  '무료',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.action,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.sunken,
              color: AppColors.action,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text.rich(
            TextSpan(
              style: AppTypography.footnote.copyWith(color: AppColors.muted),
              children: [
                TextSpan(text: '$remaining개 더 저장할 수 있어요  '),
                TextSpan(
                  text: '프리미엄으로 무제한',
                  style: AppTypography.footnote.copyWith(
                    color: AppColors.action,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 빈 레시피 북 — 바 텍스트 한 줄 대신 아이콘과 함께 구성한다(DESIGN.md §7 "빈 상태도 구성").
class _EmptyRecipes extends StatelessWidget {
  const _EmptyRecipes();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: Space.xxxl,
        horizontal: Space.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.bookmark_outline,
            size: 40,
            color: AppColors.hairline,
          ),
          const SizedBox(height: Space.md),
          Text(
            '아직 저장한 레시피가 없어요.',
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 하이드레이트 중 리스트 자리 — 셀 3행(좌 44×44 썸네일 + 텍스트 2줄)의 모양을 정적으로 잡는다(#121).
///
/// 스피너·가짜 진행 없음 — 정직한 로딩(DESIGN.md §7).
class _RecipeListSkeleton extends StatelessWidget {
  const _RecipeListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recipe-list-skeleton'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const Divider(indent: Space.lg),
            Container(
              constraints: const BoxConstraints(minHeight: Space.rowMin),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 44, height: 44, radius: Radii.photo),
                  SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 16, radius: Radii.chip),
                        SizedBox(height: Space.sm),
                        SkeletonBox(
                          width: double.infinity,
                          height: 12,
                          radius: Radii.chip,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 하이드레이트 실패 — 리스트 자리의 인라인 에러(막다른 화면 없음, G1 #8). "다시 시도"가 재수화를 건다.
class _SyncErrorCard extends StatelessWidget {
  const _SyncErrorCard({required this.kind, required this.onRetry});

  final RecipeApiFailureKind? kind;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recipe-list-error'),
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 20,
                color: AppColors.danger,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  kind == RecipeApiFailureKind.unauthorized
                      ? '접속 정보가 유효하지 않아요.'
                      : '레시피 북을 불러오지 못했어요.',
                  style: AppTypography.headline.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          TextButton(
            key: const Key('recipe-list-error-retry'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
