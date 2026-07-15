// 외길 페이지가 상태별로 무엇을 보여주는지 — E2E와 같은 흐름을 브라우저 없이 빠르게 돌린다.
import 'package:cookmark/app.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
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
    await tester.pumpWidget(
      CookmarkApp(
        controller: MainController(gateway ?? FakeLlmGateway(), storage),
        imagePicker: () async =>
            XFile.fromData(fridgePhoto(), mimeType: 'image/jpeg'),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 업로드→인식→체크리스트 관통은 E2E(integration_test/core_loop_test.dart)가 정본이다.
  // testWidgets는 FakeAsync 존이라 dart:ui 이미지 디코드 같은 실제 I/O가 완료되지 않는다.
  // 여기서는 async를 타지 않는 것만 본다.

  testWidgets('업로드 존이 먼저 뜬다', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('upload-photo')), findsOneWidget);
    expect(find.text('냉장고 사진 한 장이면 돼요'), findsOneWidget);
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
    expect(find.text('믿고 보는 레시피를 여기에 모읍니다.'), findsOneWidget);
  });
}
