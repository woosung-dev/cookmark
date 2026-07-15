// 메인 「외길」 — 사진→재료 체크리스트→제안을 한 세로 페이지의 섹션으로 처리한다(ADR-0001, 화면 전환 0회).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'main_controller.dart';
import 'recipe_book_page.dart';
import 'widgets/checklist_section.dart';
import 'widgets/failure_card.dart';
import 'widgets/recognition_loading.dart';
import 'widgets/upload_zone.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.controller, this.imagePicker});

  final MainController controller;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉파'),
        actions: [
          // 레시피 북 진입점은 이 링크 하나뿐이다 — 탭 바 없음(ADR-0001).
          TextButton(
            key: const Key('recipe-book-link'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecipeBookPage()),
            ),
            child: const Text('레시피 북'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.screenPad,
              Space.sm,
              Space.screenPad,
              Space.xxxl,
            ),
            child: _section(),
          ),
        ),
      ),
    );
  }

  Widget _section() {
    final controller = widget.controller;
    return switch (controller.phase) {
      MainPhase.upload => UploadZone(onPick: _pickPhoto),
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
      MainPhase.checklist => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.md),
            child: Text('냉장고에 있는 것', style: AppTypography.largeTitle),
          ),
          ChecklistSection(ingredients: controller.ingredients),
          const SizedBox(height: Space.xl),
          Text(
            '맞는 것만 남기고 아닌 건 체크를 풀어주세요.',
            style: AppTypography.footnote.copyWith(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    };
  }
}
