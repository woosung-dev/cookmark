// 레시피 북 — 사용자가 신뢰하는 저장 레시피의 화면. 앱의 두 번째이자 마지막 화면(ADR-0001).
import 'package:flutter/material.dart';

import '../domain/recipe.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'backup_controller.dart';
import 'recipe_book_controller.dart';
import 'widgets/backup_section.dart';
import 'widgets/recipe_form.dart';

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
            return ListView(
              padding: const EdgeInsets.all(Space.screenPad),
              children: [
                Text(
                  '믿고 보는 레시피만 모아두세요. 여기 있는 게 제안의 근거가 됩니다.',
                  style: AppTypography.subhead.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: Space.xl),
                RecipeForm(
                  saving: controller.saving,
                  onSubmit: (url, title) =>
                      controller.add(url: url, title: title),
                ),
                const SizedBox(height: Space.xxl),
                if (recipes.isEmpty)
                  const _EmptyRecipes()
                else
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
          // 좌 아이콘 — 제목 줄에 맞춰 살짝 내린다.
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.bookmark_outline,
              size: 20,
              color: AppColors.muted,
            ),
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
                  Text(
                    recipe.ingredients.join(' · '),
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
