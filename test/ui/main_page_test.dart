// 외길 페이지가 상태별로 무엇을 보여주는지 — E2E와 같은 흐름을 브라우저 없이 빠르게 돌린다.
import 'package:cookmark/app.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/domain/session_state.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/ui/backup_controller.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
  });

  Future<void> pumpApp(WidgetTester tester, {FakeLlmGateway? gateway}) async {
    final llm = gateway ?? FakeLlmGateway();
    await tester.pumpWidget(
      CookmarkApp(
        controller: MainController(llm, storage),
        recipeBookController: RecipeBookController(llm, storage),
        backupController: BackupController(storage),
        imagePicker: () async =>
            XFile.fromData(fridgePhoto(), mimeType: 'image/jpeg'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 레시피 북이 비어 있으면 온보딩 카드가 업로드 존 자리를 차지한다 — 업로드 존을 보려면 건너뛴다.
  Future<void> pumpPastOnboarding(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
  }

  // 업로드→인식→체크리스트 관통은 E2E(integration_test/core_loop_test.dart)가 정본이다.
  // testWidgets는 FakeAsync 존이라 dart:ui 이미지 디코드 같은 실제 I/O가 완료되지 않는다.
  // 여기서는 async를 타지 않는 것만 본다.

  testWidgets('첫 방문에는 업로드 존 자리에 온보딩 카드가 온다 (#17)', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('onboarding-card')), findsOneWidget);
    expect(find.text('믿고 보는 레시피 3개만 저장해두세요'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-counter')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    // 별도 화면이 아니라 메인의 한 상태다 — 업로드 존은 아직 없다.
    expect(find.byKey(const Key('upload-photo')), findsNothing);
  });

  testWidgets('건너뛰면 업로드 존이 나오고 넛지 칩이 남는다 (#17)', (tester) async {
    await pumpPastOnboarding(tester);

    expect(find.byKey(const Key('onboarding-card')), findsNothing);
    expect(find.byKey(const Key('upload-photo')), findsOneWidget);
    expect(find.text('냉장고 사진 한 장이면 돼요'), findsOneWidget);
    // 3개 미만이라 넛지가 상시로 남는다.
    expect(find.byKey(const Key('recipe-nudge-chip')), findsOneWidget);
  });

  testWidgets('하단 탭 바로 두 화면을 오가고 헤더 링크도 병행한다 (ADR-0007)', (tester) async {
    await pumpApp(tester);
    // 구식 Material 2 BottomNavigationBar가 아니라 Material 3 NavigationBar를 쓴다.
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('recipe-book-link')), findsOneWidget);
  });

  testWidgets('헤더 링크로 레시피 북에 들어간다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 레시피가 없어요.'), findsOneWidget);
  });

  testWidgets('넛지 칩도 레시피 북으로 데려간다', (tester) async {
    await pumpPastOnboarding(tester);
    await tester.tap(find.byKey(const Key('recipe-nudge-chip')));
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 레시피가 없어요.'), findsOneWidget);
  });

  // #34 — 추출 실패가 화면에 뜨는지. 컨트롤러 단위 테스트로는 이 결함을 못 잡는다:
  // 실패는 `failure` 게터에 담겨 있었지만 UI가 그걸 읽지 않아 사용자가 몰랐다.
  group('추출 실패 인라인 (#34)', () {
    testWidgets('재료 0개 레시피에 "다시 시도"가 그 자리에 뜬다', (tester) async {
      await storage.writeRecipes(const [
        Recipe(url: 'https://youtu.be/abc', title: '김치찌개', ingredients: []),
      ]);
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('recipe-book-link')));
      await tester.pumpAndSettle();

      expect(find.text('재료를 알아내지 못했어요 — 매칭에는 제목만 쓰입니다.'), findsOneWidget);
      expect(
        find.byKey(const Key('recipe-retry-https://youtu.be/abc')),
        findsOneWidget,
      );
    });

    testWidgets('"다시 시도"를 누르면 재료가 채워진다', (tester) async {
      await storage.writeRecipes(const [
        Recipe(url: 'https://youtu.be/abc', title: '김치찌개', ingredients: []),
      ]);
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('recipe-book-link')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('recipe-retry-https://youtu.be/abc')),
      );
      await tester.pumpAndSettle();

      // 페이크의 '김치찌개' 추출 fixture가 채워진다.
      expect(find.textContaining('김치'), findsWidgets);
      expect(find.text('재료를 알아내지 못했어요 — 매칭에는 제목만 쓰입니다.'), findsNothing);
      expect(storage.readRecipes().single.ingredients, isNotEmpty);
    });

    testWidgets('재료가 있는 레시피엔 "다시 시도"가 없다', (tester) async {
      await storage.writeRecipes(const [
        Recipe(url: 'https://youtu.be/abc', title: '김치찌개', ingredients: ['김치']),
      ]);
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('recipe-book-link')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recipe-retry-https://youtu.be/abc')),
        findsNothing,
      );
    });
  });

  group('실행취소 토스트', () {
    /// 제안이 떠 있는 화면. 사진 경로를 타지 않는다 — 위 주석대로 FakeAsync에서 이미지
    /// 디코드가 끝나지 않으므로, 세션 복원으로 체크리스트를 세우고 매칭만 돌린다.
    Future<MainController> pumpWithSuggestions(WidgetTester tester) async {
      // 기본 800x600에서는 토스트가 두 번째 제안 카드를 덮어 탭이 조용히 빗나간다.
      // 실기기(세로로 긴 폰)에서는 카드가 토스트 위에 있으므로 화면을 그만큼 키운다.
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await storage.writeSession(
        SessionState(ingredients: defaultRecognitionFixture),
      );
      final llm = FakeLlmGateway();
      final controller = MainController(llm, storage)..restoreSession();
      await controller.requestSuggestions();

      await tester.pumpWidget(
        CookmarkApp(
          controller: controller,
          recipeBookController: RecipeBookController(llm, storage),
          backupController: BackupController(storage),
          imagePicker: () async =>
              XFile.fromData(fridgePhoto(), mimeType: 'image/jpeg'),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('"이거 했어요"를 연달아 눌러도 마지막 실행취소가 살아 있다 (#19)', (tester) async {
      final controller = await pumpWithSuggestions(tester);
      final menus = [for (final s in controller.suggestions) s.menu];

      await tester.tap(find.byKey(Key('cooked-${menus[0]}')));
      await tester.pumpAndSettle();

      // 두 번째 토스트가 첫 번째를 밀어낸다 — 밀려난 토스트의 닫힘이 여기서 살아 있는
      // 실행취소 창을 죽였다. pumpAndSettle이 그 퇴장 애니메이션을 끝까지 돌린다.
      await tester.tap(find.byKey(Key('cooked-${menus[1]}')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('실행취소'));
      await tester.pumpAndSettle();

      final events = storage.readEvents();
      expect(
        events
            .where((e) => e.type == AppEventType.cookedUndo)
            .single
            .data['menu'],
        menus[1],
      );
      // 되돌렸는데 cooked가 그대로 남으면 성공 지표 2가 영구히 과대집계된다.
      expect(events.where((e) => e.type == AppEventType.cooked), hasLength(2));
    });
  });
}
