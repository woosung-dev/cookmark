// 메인 「외길」 — 사진→재료 체크리스트→제안을 한 세로 페이지의 섹션으로 처리한다(ADR-0001, 화면 전환 0회).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'main_controller.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_page.dart';
import 'widgets/add_ingredient_bar.dart';
import 'widgets/checklist_section.dart';
import 'widgets/failure_card.dart';
import 'widgets/onboarding_card.dart';
import 'widgets/recipe_book_chips.dart';
import 'widgets/recognition_loading.dart';
import 'widgets/upload_zone.dart';
import 'widgets/vague_chips.dart';

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.controller,
    required this.recipeBookController,
    this.imagePicker,
  });

  final MainController controller;
  final RecipeBookController recipeBookController;

  /// 테스트가 사진 선택 다이얼로그를 건너뛸 수 있게 — 브라우저 파일 선택창은 자동화가 안 된다.
  final Future<XFile?> Function()? imagePicker;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  Future<void> _pickPhoto() async {
    final picker = widget.imagePicker ?? _pickFromGallery;
    final file = await picker();
    if (file == null) return;
    await widget.controller.uploadPhoto(await file.readAsBytes());
  }

  Future<XFile?> _pickFromGallery() =>
      ImagePicker().pickImage(source: ImageSource.gallery);

  Future<void> _openRecipeBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeBookPage(controller: widget.recipeBookController),
      ),
    );
    // 레시피 북에서 뭔가 바뀌었을 수 있다 — 미인식 칩·넛지가 이걸 따라간다.
    widget.controller.refresh();
  }

  Future<void> _saveRecipe(String url, String title) async {
    await widget.recipeBookController.add(url: url, title: title);
    widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉파'),
        actions: [
          // 레시피 북 진입점은 이 링크 하나뿐이다 — 탭 바 없음(ADR-0001).
          TextButton(
            key: const Key('recipe-book-link'),
            onPressed: _openRecipeBook,
            child: const Text('레시피 북'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.controller,
            widget.recipeBookController,
          ]),
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.screenPad,
                    Space.sm,
                    Space.screenPad,
                    Space.xxxl,
                  ),
                  child: _section(),
                ),
              ),
              // 추가 바는 체크리스트를 다듬는 동안에만 하단에 고정된다.
              if (widget.controller.phase == MainPhase.checklist)
                AddIngredientBar(
                  frequent: widget.controller.frequentIngredients,
                  onAdd: (name, path) =>
                      widget.controller.addIngredient(name, path: path),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section() {
    final controller = widget.controller;
    return switch (controller.phase) {
      MainPhase.upload => _uploadSection(),
      MainPhase.recognizing => RecognitionLoading(
        photo: controller.photo,
        startedAt: controller.recognizeStartedAt!,
        onCancel: controller.continueWithEmptyChecklist,
      ),
      MainPhase.failed => FailureCard(
        kind: controller.failure!,
        onRetry: controller.retryRecognition,
        onContinueManually: controller.continueWithEmptyChecklist,
      ),
      MainPhase.checklist => _checklistSection(),
    };
  }

  /// 첫 방문이면 업로드 존 자리에 온보딩 카드가 온다 — 별도 화면이 아니다(G1 #8).
  Widget _uploadSection() {
    final controller = widget.controller;
    if (controller.showsOnboarding) {
      return OnboardingCard(
        savedCount: controller.recipeCount,
        saving: widget.recipeBookController.saving,
        onSubmit: _saveRecipe,
        onSkip: controller.skipOnboarding,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UploadZone(onPick: _pickPhoto),
        if (controller.showsRecipeNudge) ...[
          const SizedBox(height: Space.lg),
          RecipeNudgeChip(
            savedCount: controller.recipeCount,
            onTap: _openRecipeBook,
          ),
        ],
      ],
    );
  }

  Widget _checklistSection() {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.md),
          child: Text('냉장고에 있는 것', style: AppTypography.largeTitle),
        ),
        ChecklistSection(
          ingredients: controller.ingredients,
          onToggle: controller.toggle,
        ),
        if (controller.vagueItems.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          VagueChips(
            items: controller.vagueItems,
            onSubstitute: controller.substituteVague,
            onDismiss: controller.dismissVague,
          ),
        ],
        if (controller.unrecognizedFromRecipeBook.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          RecipeBookChips(
            names: controller.unrecognizedFromRecipeBook,
            onAdd: (name, path) => controller.addIngredient(name, path: path),
          ),
        ],
        const SizedBox(height: Space.xl),
        Text(
          '맞는 것만 남기고 아닌 건 체크를 풀어주세요.',
          style: AppTypography.footnote.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
