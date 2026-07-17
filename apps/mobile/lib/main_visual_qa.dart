// 시각 QA 전용 엔트리 — DESIGN.md 대조 스크린샷용. 파일럿 빌드(lib/main.dart)에는 들어가지 않는다.
//
// FakeLlmGateway를 주입하고 `?state=` 쿼리로 각 화면을 선구동한다. 실행:
//   flutter run -d chrome -t lib/main_visual_qa.dart
//   → http://<host>/#/?state=suggestions
//   states: onboarding|upload|loading|checklist|matching|suggestions|detail|error|error-matching|recipebook|recipebook-empty
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'app.dart';
import 'data/storage.dart';
import 'domain/recipe.dart';
import 'domain/session_state.dart';
import 'domain/suggestion.dart';
import 'llm/fake_llm_gateway.dart';
import 'llm/llm_gateway.dart';
import 'theme/app_theme.dart';
import 'ui/backup_controller.dart';
import 'ui/main_controller.dart';
import 'ui/recipe_book_controller.dart';
import 'ui/recipe_book_page.dart';
import 'ui/suggestion_detail_page.dart';

/// 리사이즈·스캔 시머가 그릴 수 있는 진짜 JPEG(무늬가 있어야 압축이 살아난다).
Uint8List _fakePhoto() {
  final image = img.Image(width: 400, height: 300);
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 400; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return img.encodeJpg(image);
}

/// 매칭·제안 화면에 저장 카드가 나오도록 심는 레시피 북.
const _seedRecipes = <Recipe>[
  Recipe(
    url: 'https://youtu.be/abc',
    title: '김치찌개',
    ingredients: ['김치', '돼지고기', '두부', '대파'],
  ),
  Recipe(
    url: 'https://youtu.be/xyz',
    title: '된장찌개',
    ingredients: ['된장', '두부', '애호박', '대파'],
  ),
  Recipe(
    url: 'https://youtu.be/def',
    title: '계란말이',
    ingredients: ['계란', '대파', '소금'],
  ),
];

/// 레시피 북 화면용 — 마지막 항목은 재료 추출 실패 셀(인라인 복구 UI)을 보여준다.
const _recipeBookSeed = <Recipe>[
  Recipe(
    url: 'https://youtu.be/abc',
    title: '백종원 김치찌개',
    ingredients: ['김치', '돼지고기', '두부', '대파', '고춧가루'],
  ),
  Recipe(
    url: 'https://youtu.be/xyz',
    title: '애호박 새우젓 볶음',
    ingredients: ['애호박', '대파', '새우젓', '식용유'],
  ),
  Recipe(url: 'https://youtu.be/empty', title: '오늘의 저녁', ingredients: []),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  final state = Uri.base.queryParameters['state'] ?? 'checklist';

  // 제안 상세도 자체 Scaffold라 home으로 직접 띄운다(Navigator.push 없음 — 트립와이어 무영향).
  if (state == 'detail') {
    await storage.writeRecipes(_seedRecipes);
    const suggestion = Suggestion(
      menu: '김치찌개',
      source: SuggestionSource.saved,
      missing: [MissingIngredient(name: '돼지고기')],
      reason: '김치·두부·대파가 있어요.',
      recipeUrl: 'https://youtu.be/abc',
    );
    runApp(
      MaterialApp(
        title: '냉파',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: SuggestionDetailPage(
          suggestion: suggestion,
          rank: 1,
          onOpenRecipe: () {},
          available: const ['김치', '두부', '대파'],
        ),
      ),
    );
    return;
  }

  // 레시피 북은 자체 Scaffold라 home으로 직접 띄운다(Navigator.push 없음 — 트립와이어 무영향).
  if (state == 'recipebook' || state == 'recipebook-empty') {
    await storage.writeRecipes(
      state == 'recipebook-empty' ? const [] : _recipeBookSeed,
    );
    final gw = FakeLlmGateway();
    runApp(
      MaterialApp(
        title: '냉파',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: RecipeBookPage(
          controller: RecipeBookController(gw, storage),
          backupController: BackupController(storage),
        ),
      ),
    );
    return;
  }

  final photo = _fakePhoto();
  Future<XFile?> picker() async =>
      XFile.fromData(photo, name: 'fridge.jpg', mimeType: 'image/jpeg');

  late final FakeLlmGateway gateway;
  late final MainController controller;

  switch (state) {
    case 'onboarding':
      await storage.writeRecipes(const []);
      gateway = FakeLlmGateway();
      controller = MainController(gateway, storage);
    case 'upload':
      await storage.writeRecipes(_seedRecipes);
      gateway = FakeLlmGateway();
      controller = MainController(gateway, storage)..skipOnboarding();
    case 'loading':
      await storage.writeRecipes(_seedRecipes);
      gateway = FakeLlmGateway(latency: const Duration(minutes: 10));
      controller = MainController(gateway, storage);
      unawaited(controller.uploadPhoto(photo));
    case 'matching':
      await storage.writeRecipes(_seedRecipes);
      await storage.writeSession(
        SessionState(ingredients: defaultRecognitionFixture),
      );
      gateway = FakeLlmGateway(latency: const Duration(minutes: 10));
      controller = MainController(gateway, storage)..restoreSession();
      unawaited(controller.requestSuggestions());
    case 'suggestions':
      await storage.writeRecipes(_seedRecipes);
      await storage.writeSession(
        SessionState(ingredients: defaultRecognitionFixture),
      );
      gateway = FakeLlmGateway();
      controller = MainController(gateway, storage)..restoreSession();
      await controller.requestSuggestions();
    case 'error-matching':
      await storage.writeRecipes(_seedRecipes);
      await storage.writeSession(
        SessionState(ingredients: defaultRecognitionFixture),
      );
      gateway = FakeLlmGateway(
        matchFailure: const LlmFailure(LlmFailureKind.error),
      );
      controller = MainController(gateway, storage)..restoreSession();
      await controller.requestSuggestions();
    case 'error':
    case 'error-recognition':
      await storage.writeRecipes(_seedRecipes);
      gateway = FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty));
      controller = MainController(gateway, storage);
      await controller.uploadPhoto(photo);
    default: // 'checklist'
      await storage.writeRecipes(_seedRecipes);
      gateway = FakeLlmGateway();
      controller = MainController(gateway, storage);
      await controller.uploadPhoto(photo);
  }

  runApp(
    CookmarkApp(
      controller: controller,
      recipeBookController: RecipeBookController(gateway, storage),
      backupController: BackupController(storage),
      imagePicker: picker,
    ),
  );
}
