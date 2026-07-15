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
                  Text(
                    '아직 저장한 레시피가 없어요.',
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  )
                else
                  for (final recipe in recipes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: _RecipeTile(
                        recipe: recipe,
                        onRemove: () => controller.remove(recipe.url),
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

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({required this.recipe, required this.onRemove});

  final Recipe recipe;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('recipe-tile-${recipe.url}'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.title, style: AppTypography.headline),
                const SizedBox(height: Space.xs),
                Text(
                  recipe.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.footnote.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: Space.sm),
                if (recipe.ingredients.isEmpty)
                  Text(
                    '재료를 알아내지 못했어요 — 매칭에는 제목만 쓰입니다.',
                    style: AppTypography.footnote.copyWith(
                      color: AppColors.danger,
                    ),
                  )
                else
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
