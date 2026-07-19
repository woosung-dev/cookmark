// 메인 「외길」 — 사진→재료 체크리스트→제안을 한 세로 페이지의 섹션으로 처리한다(ADR-0001, 화면 전환 0회).
//
// 섹션은 쌓이고, 지나간 섹션은 요약 한 줄로 접힌다(G1 #8). 접힌 체크리스트를 다시 펼쳐
// 재료를 손보면 아래 제안이 낡고("다시 제안" 배너), 그때 발생한 이벤트엔 stale이 붙는다.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/suggestion.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'backup_controller.dart';
import 'main_controller.dart';
import 'recipe_book_controller.dart';
import 'suggestion_detail_page.dart';
import 'widgets/add_ingredient_bar.dart';
import 'widgets/backup_section.dart';
import 'widgets/brand_hero.dart';
import 'widgets/checklist_section.dart';
import 'widgets/debug_footer.dart';
import 'widgets/failure_card.dart';
import 'widgets/in_app_browser_banner.dart';
import 'widgets/onboarding_card.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/recipe_add_failure_card.dart';
import 'widgets/recipe_book_chips.dart';
import 'widgets/recognition_loading.dart';
import 'widgets/section_summary.dart';
import 'widgets/suggestions_section.dart';
import 'widgets/upload_zone.dart';
import 'widgets/vague_chips.dart';

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.controller,
    required this.recipeBookController,
    required this.backupController,
    this.imagePicker,
    required this.onOpenRecipeBook,
  });

  final MainController controller;
  final RecipeBookController recipeBookController;
  final BackupController backupController;

  /// 테스트가 사진 선택 다이얼로그를 건너뛸 수 있게 — 브라우저 파일 선택창은 자동화가 안 된다.
  final Future<XFile?> Function()? imagePicker;

  /// 레시피 북 탭으로 전환한다 — 셸이 주입한다(탭 기반 이동, ADR-0007).
  final VoidCallback onOpenRecipeBook;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  MainController get _controller => widget.controller;

  Future<void> _pickPhoto() async {
    final picker = widget.imagePicker ?? _pickFromGallery;
    final file = await picker();
    if (file == null) return;
    await _controller.uploadPhoto(await file.readAsBytes());
  }

  Future<XFile?> _pickFromGallery() =>
      ImagePicker().pickImage(source: ImageSource.gallery);

  Future<void> _saveRecipe(String url, String title) async {
    await widget.recipeBookController.add(url: url, title: title);
    _controller.refresh();
  }

  /// "레시피 보기" — 원본을 새 탭으로 연다. 레시피 실행(③)은 익숙한 유튜브에서 한다(스펙 #13).
  Future<void> _openRecipe(Suggestion suggestion) async {
    await _controller.openRecipe(suggestion);
    final url = suggestion.recipeUrl;
    if (url == null) return;
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  /// "이거 했어요" → 5초 실행취소 토스트. 실수 입력을 바로 되돌린다(G1 #8).
  Future<void> _markCooked(Suggestion suggestion) async {
    // 더블탭 재진입이 무시됐으면 토스트도 다시 띄우지 않는다 — 실행취소 창을 연장하지 않게.
    final recorded = await _controller.markCooked(suggestion);
    if (!recorded || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            key: const Key('cooked-toast'),
            content: Text('${suggestion.menu} — 잘 드셨어요!'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '실행취소',
              onPressed: _controller.undoCooked,
            ),
          ),
        )
        .closed
        .then((_) {
          // 이 토스트가 닫혔다(사유 무관) — 실행취소를 안 눌렀다면 pending을 정리한다. 그 사이
          // 다른 제안의 "이거 했어요"가 pending을 바꿔 이 창을 밀어냈거나, 레시피 북에서 삭제해
          // clearSnackBars로 밀려났어도 제안 대조로 안전하다(dismissUndoFor 참조).
          _controller.dismissUndoFor(suggestion);
        });
  }

  /// 카드 탭 → 제안 상세로 push한다 — 앱의 유일한 명령형 push다(ADR-0007, navigation_test).
  ///
  /// 상세의 "이거 했어요"는 결과와 함께 pop하고, 상세가 사라진 뒤 여기서 _markCooked를 부른다 —
  /// 토스트/undo가 상세가 아니라 메인 위에 뜨게 한다(오펀 방지).
  Future<void> _openDetail(Suggestion suggestion, int rank) async {
    final action = await Navigator.of(context).push<SuggestionDetailAction>(
      MaterialPageRoute(
        builder: (_) => SuggestionDetailPage(
          suggestion: suggestion,
          rank: rank,
          onOpenRecipe: () => _openRecipe(suggestion),
          available: _availableFor(suggestion),
        ),
      ),
    );
    if (!mounted) return;
    if (action == SuggestionDetailAction.cooked) {
      await _markCooked(suggestion);
    }
  }

  /// 있는 재료 = 저장 레시피의 재료 − 부족. AI 제안(recipeUrl 없음)·재료 빈 레시피면 빈 목록(파생, 저장소 무변경).
  List<String> _availableFor(Suggestion suggestion) {
    final url = suggestion.recipeUrl;
    if (url == null) return const [];
    final matches = widget.recipeBookController.recipes.where(
      (r) => r.url == url,
    );
    if (matches.isEmpty) return const [];
    final missing = suggestion.missing.map((m) => m.name).toSet();
    return [
      for (final ingredient in matches.first.ingredients)
        if (!missing.contains(ingredient)) ingredient,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉파'),
        actions: [
          // 헤더 '둘러보기' 링크도 레시피 북 탭으로 전환한다(하단 탭 바와 병행, ADR-0007).
          TextButton(
            key: const Key('recipe-book-link'),
            onPressed: widget.onOpenRecipeBook,
            child: const Text('레시피 북'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _controller,
            widget.recipeBookController,
            widget.backupController,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _sections(),
                  ),
                ),
              ),
              // 추가 바는 체크리스트를 펼쳐 다듬는 동안에만 하단에 고정된다.
              if (_showsChecklist && _controller.checklistExpanded)
                AddIngredientBar(
                  frequent: _controller.frequentIngredients,
                  onAdd: (name, path) =>
                      _controller.addIngredient(name, path: path),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 체크리스트 섹션이 페이지에 있는가 — 인식이 끝난 뒤로는 계속 있다(접혀 있을 뿐).
  bool get _showsChecklist => switch (_controller.phase) {
    MainPhase.checklist || MainPhase.matching || MainPhase.suggestions => true,
    MainPhase.failed => _controller.failureStage == FailureStage.matching,
    MainPhase.upload || MainPhase.recognizing => false,
  };

  /// 쌓이는 섹션들. 위에서부터 사진 → 재료 → 제안 순이고, 지나간 것은 접힌다.
  List<Widget> _sections() {
    final controller = _controller;

    return [
      // 카톡 인앱 브라우저 상시 경고 — 닫을 수 없다. 여기서 쓰면 기록이 날아간다(#21).
      if (controller.showsInAppBrowserWarning) ...[
        const InAppBrowserBanner(),
        const SizedBox(height: Space.lg),
      ],

      // 7일이 지났으면 주간 성적표로 백업을 권한다(G1 #8). 수동 수정 수는 여기 없다(ADR-0004).
      if (widget.backupController.needsBackup) ...[
        WeeklyReportBanner(
          copy: widget.backupController.weeklyReport.copy,
          onTap: widget.onOpenRecipeBook,
        ),
        const SizedBox(height: Space.lg),
      ],

      // 3개 미만이면 **상시** 넛지다(G1 #8) — 온보딩을 건너뛴 사람에게도 길을 남긴다.
      // 온보딩 카드가 떠 있는 동안엔 카드 자체가 그 일을 하므로 중복해 띄우지 않는다.
      if (controller.showsRecipeNudge && !controller.showsOnboarding) ...[
        RecipeNudgeChip(
          savedCount: controller.recipeCount,
          onTap: widget.onOpenRecipeBook,
        ),
        const SizedBox(height: Space.lg),
      ],

      // 재업로드 자리는 첫 인식 뒤에도 남는다 — 매일 새로 찍는 2주 파일럿의 반복 진입점.
      // 이벤트는 남기지 않는다. 진짜 photoUpload는 다음 사진을 고르는 순간 찍힌다.
      if (controller.phase != MainPhase.upload) ...[
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('start-new-photo'),
            onPressed: controller.startNewPhoto,
            child: const Text('다른 사진으로 다시'),
          ),
        ),
        const SizedBox(height: Space.sm),
      ],

      switch (controller.phase) {
        MainPhase.upload => _uploadSection(),
        MainPhase.recognizing => RecognitionLoading(
          photo: controller.photo,
          startedAt: controller.recognizeStartedAt!,
          onCancel: controller.continueWithEmptyChecklist,
        ),
        MainPhase.failed
            when controller.failureStage == FailureStage.recognition =>
          FailureCard(
            kind: controller.failure!,
            stage: FailureStage.recognition,
            onRetry: controller.retryRecognition,
            onContinueManually: controller.continueWithEmptyChecklist,
          ),
        _ => const SizedBox.shrink(),
      },

      if (_showsChecklist) ...[
        if (controller.checklistExpanded)
          _checklistSection()
        else
          SectionSummary(
            key: const Key('checklist-summary'),
            label: '냉장고에 있는 것 ${controller.matchableIngredients.length}개',
            onTap: controller.toggleChecklistExpanded,
          ),
        // 재료를 손봐서 아래 제안이 낡았다면 갱신을 권한다(ADR-0001).
        if (controller.isStale) ...[
          const SizedBox(height: Space.md),
          RematchBanner(onRematch: controller.requestSuggestions),
        ],
        const SizedBox(height: Space.xxl),
      ],

      switch (controller.phase) {
        MainPhase.matching => MatchingLoading(
          recipeCount: controller.matchingRecipeCount,
        ),
        MainPhase.suggestions => SuggestionsSection(
          suggestions: controller.suggestions,
          excludedCount: controller.excludedCount,
          onOpenRecipe: _openRecipe,
          onCooked: _markCooked,
          onOpenDetail: _openDetail,
        ),
        MainPhase.failed
            when controller.failureStage == FailureStage.matching =>
          FailureCard(
            kind: controller.failure!,
            stage: FailureStage.matching,
            onRetry: controller.requestSuggestions,
            onContinueManually: controller.backToChecklist,
          ),
        _ => const SizedBox.shrink(),
      },

      // debug 파라미터가 없으면 이 위젯은 트리에 존재하지 않는다(ADR-0004).
      if (controller.showsDebugFooter)
        DebugFooter(metrics: controller.debugMetrics),
    ];
  }

  /// 첫 방문이면 업로드 존 자리에 온보딩 카드가 온다 — 별도 화면이 아니다(G1 #8).
  /// 위에 브랜드 히어로를 얹어 진입의 온기를 만든다(P2, 목업 화면 1).
  Widget _uploadSection() {
    final controller = _controller;
    final book = widget.recipeBookController;
    final card = controller.showsOnboarding
        ? OnboardingCard(
            savedCount: controller.recipeCount,
            saving: book.saving,
            // 서버 미러가 ready가 아닌 동안 입력을 막는다 — 로컬 모드는 항상 ready다(#121).
            enabled: book.syncState == RecipeSyncState.ready,
            onSubmit: _saveRecipe,
            onSkip: controller.skipOnboarding,
            // 서버 모드 저장 실패(502=미저장)도 온보딩 자리에서 인라인으로 해소한다(#121).
            failure: book.addFailure == null
                ? null
                : RecipeAddFailureCard(
                    kind: book.addFailure!,
                    onRetry: () {
                      final failed = book.failedAdd!;
                      _saveRecipe(failed.url, failed.title);
                    },
                    onDismiss: book.clearAddFailure,
                  ),
          )
        : UploadZone(onPick: _pickPhoto);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandHero(),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AppColors.action,
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                '출처 있는, 내가 저장한 레시피만 추천해요.',
                style: AppTypography.footnote.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        card,
      ],
    );
  }

  Widget _checklistSection() {
    final controller = _controller;
    final hasSuggestions = controller.suggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: Space.xs, bottom: Space.md),
          child: Text('냉장고에 있는 것', style: AppTypography.largeTitle),
        ),
        // 첫 인식 결과 위 1회성 — 인식 오류를 실패로 느끼지 않게 한다(B 이식, G1 #8).
        if (controller.showsExpectationNote) ...[
          const ExpectationNote(),
          const SizedBox(height: Space.md),
        ],
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
        const SizedBox(height: Space.lg),
        // 제안이 이미 있으면 이 버튼 대신 "다시 제안" 배너가 갱신을 맡는다.
        if (!hasSuggestions)
          SizedBox(
            height: Space.touchMin + 4,
            child: PressableScale(
              enabled: controller.matchableIngredients.isNotEmpty,
              child: FilledButton(
                key: const Key('request-suggestions'),
                onPressed: controller.matchableIngredients.isEmpty
                    ? null
                    : controller.requestSuggestions,
                child: const Text('오늘 뭐 해먹지'),
              ),
            ),
          )
        else
          Center(
            child: TextButton(
              key: const Key('collapse-checklist'),
              onPressed: controller.toggleChecklistExpanded,
              child: const Text('접기'),
            ),
          ),
      ],
    );
  }
}
