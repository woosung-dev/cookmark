// 외길 페이지가 상태별로 무엇을 보여주는지 — E2E와 같은 흐름을 브라우저 없이 빠르게 돌린다.
import 'package:cookmark/app.dart';
import 'package:cookmark/data/storage.dart';
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

  testWidgets('탭 바가 없고 레시피 북은 헤더 링크로만 간다 (ADR-0001)', (tester) async {
    await pumpApp(tester);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
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
}
