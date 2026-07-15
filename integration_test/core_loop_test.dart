// 검증의 정본 — 브라우저에서 사용자가 보는 것과 로그에 남는 것만 확인한다(coding-standards).
// 실행: scripts/e2e.sh  (또는 chromedriver --port=4444 && flutter drive \
//        --driver=test_driver/integration_test.dart --target=integration_test/core_loop_test.dart -d chrome)
//
// CheckedState는 dart:ui에 있고 flutter/semantics.dart가 export하지 않는다.
import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:cookmark/app.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';

/// 실제 JPEG — 리사이즈 경로(dart:ui 디코더)를 브라우저에서 진짜로 태운다.
XFile fridgePhotoFile() {
  final image = img.Image(width: 1600, height: 1200);
  for (var y = 0; y < 1200; y++) {
    for (var x = 0; x < 1600; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return XFile.fromData(img.encodeJpg(image), mimeType: 'image/jpeg');
}

/// 상태가 [predicate]를 만족할 때까지 기다린다.
///
/// 로딩 중에는 스캔 시머가 계속 돌아 pumpAndSettle이 영영 정착하지 않는다 — 그래서 프레임이 아니라
/// 상태를 기다린다. 임의의 sleep으로 찍으면 느린 기계에서 깨진다.
Future<void> waitForPhase(
  WidgetTester tester,
  MainController controller,
  bool Function() predicate,
) async {
  final completer = Completer<void>();
  void listener() {
    if (predicate() && !completer.isCompleted) completer.complete();
  }

  controller.addListener(listener);
  listener();
  while (!completer.isCompleted) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  controller.removeListener(listener);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    storage = await Storage.open();
    // 브라우저 localStorage는 테스트 사이에 살아남는다 — 비우고 시작해야 결정적이다.
    await storage.clear();
  });

  Future<MainController> pumpApp(
    WidgetTester tester, {
    FakeLlmGateway? gateway,
  }) async {
    final controller = MainController(gateway ?? FakeLlmGateway(), storage);
    await tester.pumpWidget(
      CookmarkApp(
        controller: controller,
        imagePicker: () async => fridgePhotoFile(),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// 사진을 올리고 인식이 끝날 때까지 기다린다.
  Future<void> uploadAndWait(
    WidgetTester tester,
    MainController controller,
  ) async {
    await tester.tap(find.byKey(const Key('upload-photo')));
    await tester.pump();
    await waitForPhase(
      tester,
      controller,
      () =>
          controller.phase == MainPhase.checklist ||
          controller.phase == MainPhase.failed,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('사진 1장을 올리면 재료 체크리스트가 뜬다 — 코어 루프 관통', (tester) async {
    final controller = await pumpApp(tester);

    // 외길의 출발점.
    expect(find.byKey(const Key('upload-photo')), findsOneWidget);

    await uploadAndWait(tester, controller);

    // 화면 전환 없이 같은 페이지가 체크리스트로 바뀐다(ADR-0001).
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
    for (final name in ['대파', '계란', '두부', '애호박', '고추장', '표고버섯']) {
      expect(find.text(name), findsOneWidget, reason: '$name이(가) 화면에 있어야 한다');
    }
  });

  testWidgets('confidence 3단 초기 상태가 화면에 나타난다 (ADR-0003)', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await pumpApp(tester);
    await uploadAndWait(tester, controller);

    CheckedState checkedOf(String name) =>
        tester.getSemantics(find.text(name)).flagsCollection.isChecked;

    // high·medium은 체크된 채로, low는 해제된 채로.
    expect(checkedOf('대파'), CheckedState.isTrue, reason: 'high는 체크');
    expect(checkedOf('애호박'), CheckedState.isTrue, reason: 'medium도 체크');
    expect(checkedOf('표고버섯'), CheckedState.isFalse, reason: 'low는 해제');

    // low는 "확실하지 않아요" 흐린 그룹으로 내려간다.
    expect(find.text('확실하지 않아요'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('업로드·인식 완료가 이벤트로 남고 스토리지를 다시 열어도 유지된다', (tester) async {
    final controller = await pumpApp(tester);
    await uploadAndWait(tester, controller);

    // 브라우저 스토리지에서 새로 읽는다 — 메모리 캐시가 아니라 진짜 영속층을 통과했는지.
    final reopened = await Storage.open();
    final events = reopened.readEvents();

    expect(events.map((e) => e.type), [
      AppEventType.photoUpload,
      AppEventType.recognitionDone,
    ]);

    expect(events.first.data['width'], 768, reason: '클라이언트에서 768px로 줄여 보낸다');

    final done = events.last;
    expect(done.data['promptTokens'], 1157);
    expect(done.data['outputTokens'], 295);
    expect(done.data['thoughtTokens'], 0);
    expect(done.data['imageTokens'], 1064);
    expect(done.data['costUsd'], 0.00073);
    expect(done.data['model'], 'fake-recognizer');
    expect(done.data['latencyMs'], isA<int>());
    expect(done.at, isA<DateTime>());
  });

  testWidgets('인식 중에는 사진 위 스캔 시머와 체크박스 스켈레톤이 뜬다', (tester) async {
    final controller = await pumpApp(
      tester,
      gateway: FakeLlmGateway(latency: const Duration(seconds: 2)),
    );

    await tester.tap(find.byKey(const Key('upload-photo')));
    await tester.pump();
    await waitForPhase(
      tester,
      controller,
      () => controller.phase == MainPhase.recognizing,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('loading-message')), findsOneWidget);
    expect(find.text('재료를 찾는 중이에요'), findsOneWidget);
    // 업로드한 사진이 화면에 있다.
    expect(find.byType(Image), findsWidgets);
    // 10초 전에는 취소가 없다.
    expect(find.byKey(const Key('loading-cancel')), findsNothing);

    await waitForPhase(
      tester,
      controller,
      () => controller.phase == MainPhase.checklist,
    );
    await tester.pumpAndSettle();
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
  });

  testWidgets('인식이 실패하면 인라인 카드로 해소된다 — 에러 화면이 없다', (tester) async {
    final controller = await pumpApp(
      tester,
      gateway: FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty)),
    );
    await uploadAndWait(tester, controller);

    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('재료를 하나도 찾지 못했어요.'), findsOneWidget);

    // 레시피 북 링크가 그대로 있다 — 막다른 화면이 아니라 같은 페이지의 한 섹션이다.
    expect(find.byKey(const Key('recipe-book-link')), findsOneWidget);

    // "직접 입력으로 계속"이 루프를 이어간다.
    await tester.tap(find.byKey(const Key('failure-manual')));
    await tester.pumpAndSettle();
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
    expect(find.byKey(const Key('failure-card')), findsNothing);

    // 오류가 유형과 함께 로그에 남는다.
    final errors = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.errorShown,
    );
    expect(errors.single.data['kind'], 'empty');
  });

  testWidgets('레시피 북은 헤더 링크 하나로만 들어간다 — 탭 바가 없다', (tester) async {
    await pumpApp(tester);

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();
    expect(find.text('믿고 보는 레시피를 여기에 모읍니다.'), findsOneWidget);
  });
}
