// 검증의 정본 — 브라우저에서 사용자가 보는 것과 로그에 남는 것만 확인한다(coding-standards).
// 실행: scripts/e2e.sh  (또는 chromedriver --port=4444 && flutter drive \
//        --driver=test_driver/integration_test.dart --target=integration_test/core_loop_test.dart -d chrome)
//
// CheckedState는 dart:ui에 있고 flutter/semantics.dart가 export하지 않는다.
import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:cookmark/app.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/backup.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/domain/suggestion.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/llm/proxy_llm_gateway.dart';
import 'package:cookmark/ui/backup_controller.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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

/// 화면이 [ready]를 만족할 때까지 기다린다.
///
/// 로딩 중에는 스캔 시머가 계속 돌아 pumpAndSettle이 영영 정착하지 않는다 — 그래서 프레임이 아니라
/// 화면 상태를 기다린다. 상태를 컨트롤러가 아니라 화면으로 관측하는 이유는 이 파일이 리팩터의
/// 안전망이기 때문이다 — 상태 관리 구현(ChangeNotifier·Riverpod)이 바뀌어도 이 대기는 안 바뀐다(#38).
Future<void> waitForVisible(
  WidgetTester tester,
  bool Function() ready, {
  Duration limit = const Duration(seconds: 20),
}) async {
  // 상한이 없으면 조건이 영영 안 맞을 때 테스트가 매달린다 — 읽을 수 있는 실패로 끝낸다.
  const step = Duration(milliseconds: 50);
  var waited = Duration.zero;
  while (!ready()) {
    if (waited > limit) {
      fail('화면 상태를 $limit 안에 못 봤다.');
    }
    await tester.pump(step);
    waited += step;
  }
}

/// 위젯이 트리에 있으면 true — 대기 predicate를 짧게 쓴다.
bool _visible(Finder finder) => finder.evaluate().isNotEmpty;

/// "레시피 보기"의 launchUrl을 삼키는 페이크 — 실제 새 탭 열기는 headless 브라우저에서
/// 응답 없이 매달린다(#38 안전망 이관 중 발견). 위젯은 이 seam만 안다.
class _FakeUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => true;
}

/// 프록시가 200을 주는데 모양이 다르다 — 오형식 200 고착(#142)을 화면 수준에서 재현하는 페이크.
///
/// 페이크를 LLM 경계가 아니라 **HTTP 층**에 꽂는 것이 핵심이다. 결함은 게이트웨이와 컨트롤러
/// **사이**에 있었으므로(정규화되지 않은 `TypeError`가 그 틈으로 샜다) 실 [ProxyLlmGateway]를
/// 통과시켜야 재현된다. `FakeLlmGateway`는 `LlmFailure`를 얌전히 던지므로 이 결함을 못 만든다.
///
/// [byPath]에 없는 경로는 전부 `[]`(Map이 아닌 200)로 답한다 — 오형식이 기본값이다.
ProxyLlmGateway proxyReturning(
  Map<String, Object> byPath, {
  List<String>? requestLog,
}) {
  return ProxyLlmGateway(
    client: MockClient((request) async {
      requestLog?.add(request.url.path);
      return http.Response(
        jsonEncode(byPath[request.url.path] ?? const <Object>[]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

/// 인식만 정상으로 돌려줄 때 쓰는 본문 — 매칭 단계까지 가야 그 단계의 고착을 볼 수 있다.
/// T1 #6 실측표의 flash-lite 기본·768px 행 그대로다(지어낸 숫자를 쓰지 않는다).
const _validRecognitionBody = {
  'ingredients': [
    {'name': '대파', 'confidence': 'high'},
    {'name': '두부', 'confidence': 'high'},
  ],
  'usage': {
    'promptTokens': 1157,
    'outputTokens': 295,
    'thoughtTokens': 0,
    'imageTokens': 1064,
    'costUsd': 0.00073,
    'model': 'gemini-3.1-flash-lite',
  },
};

/// 이벤트가 스토리지에 실제로 도착할 때까지 기다린다.
///
/// pumpAndSettle은 프레임만 기다린다 — 버튼을 눌러 시작된 스토리지 쓰기(async)까지
/// 기다려주지는 않는다. 로그를 검증하려면 로그를 기다려야 한다.
Future<List<AppEvent>> waitForEvents(
  WidgetTester tester,
  Storage storage,
  bool Function(List<AppEvent>) predicate, {
  Duration limit = const Duration(seconds: 10),
}) async {
  const step = Duration(milliseconds: 50);
  var waited = Duration.zero;
  while (true) {
    final events = (await Storage.open()).readEvents();
    if (predicate(events)) return events;
    if (waited > limit) {
      fail('이벤트를 $limit 안에 못 봤다. 지금 ${events.map((e) => e.type.name)}');
    }
    await tester.pump(step);
    waited += step;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    // "레시피 보기"의 launchUrl을 삼킨다 — headless에서 실제 새 탭 열기는 매달린다.
    UrlLauncherPlatform.instance = _FakeUrlLauncher();
    storage = await Storage.open();
    // 브라우저 localStorage는 테스트 사이에 살아남는다 — 비우고 시작해야 결정적이다.
    await storage.clear();
  });

  /// [gateway]가 `LlmGateway`인 이유는 [proxyReturning] 참조 — 오형식 200 고착(#142)은
  /// 실 게이트웨이를 통과시켜야 재현된다.
  Future<void> pumpApp(
    WidgetTester tester, {
    LlmGateway? gateway,
    bool skipOnboarding = true,
    String userAgent = 'Mozilla/5.0 Chrome/120.0.0.0 Mobile Safari/537.36',
  }) async {
    final llm = gateway ?? FakeLlmGateway();
    final controller = MainController(llm, storage, userAgent: () => userAgent);
    await tester.pumpWidget(
      CookmarkApp(
        controller: controller,
        recipeBookController: RecipeBookController(llm, storage),
        backupController: BackupController(storage),
        imagePicker: () async => fridgePhotoFile(),
      ),
    );
    await tester.pumpAndSettle();

    // 레시피 북이 비어 있을 때만 온보딩 카드가 업로드 존 자리를 차지한다(G1 #8) —
    // 레시피를 미리 담아둔 테스트에서는 애초에 뜨지 않는다.
    final skip = find.byKey(const Key('onboarding-skip'));
    if (skipOnboarding && skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }
  }

  /// 파운더가 실기기에서 하는 그대로 — 앱바 타이틀을 길게 누른다(#143).
  ///
  /// 주입 훅이 없으므로 테스트도 이 경로로만 푸터를 연다. "테스트는 통과하는데
  /// 실기기에서는 안 열린다"가 구조적으로 불가능해진다.
  Future<void> openDebugFooter(WidgetTester tester) async {
    await tester.longPress(find.byKey(const Key('app-title')));
    await tester.pumpAndSettle();
  }

  /// 앱을 껐다 켠 것과 같게 만든다 — 트리를 완전히 내리고 새 컨트롤러로 다시 띄운다.
  ///
  /// 같은 `CookmarkApp`을 곧바로 다시 pump하면 엘리먼트가 재사용돼 위에 쌓인 라우트가
  /// 남고, 그 아래 메인 페이지는 offstage라 finder에 안 잡힌다. 재시작에 기대는
  /// 단언(세션 한정 푸터·초기화 리허설)은 전부 이 헬퍼를 지나야 한다.
  Future<void> restartApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester);
  }

  /// 스크롤 안의 위젯은 뷰포트 밖이면 탭이 안 먹는다 — 올린 뒤 누른다.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 파운더가 D0 직전에 하는 그대로 — 푸터의 초기화 버튼 → 확인(#144).
  ///
  /// 확인 다이얼로그를 우회하는 경로를 일부러 두지 않는다. 테스트가 컨트롤러를 직접
  /// 부르면 "확인 단계가 1개"라는 AC가 테스트에서 증발한다 — 푸터를 여는 경로와 같은 원칙이다.
  /// ([tapVisible]보다 뒤에 있어야 한다 — Dart 지역 함수는 선언 전 참조가 안 된다.)
  Future<void> resetPilotRecord(WidgetTester tester) async {
    await tapVisible(tester, find.byKey(const Key('reset-record')));
    await tester.tap(find.byKey(const Key('reset-confirm')));
    await tester.pumpAndSettle();
  }

  /// 체크리스트가 길면 "오늘 뭐 해먹지"가 뷰포트 밖에 있다 — 스크롤해 올린 뒤 탭한다.
  Future<void> tapRequestSuggestions(WidgetTester tester) async {
    final button = find.byKey(const Key('request-suggestions'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await waitForVisible(
      tester,
      () =>
          _visible(find.text('오늘 할 3개')) ||
          _visible(find.byKey(const Key('failure-card'))),
    );
    await tester.pumpAndSettle();
  }

  /// 사진을 올리고 인식이 끝날 때까지 기다린다.
  Future<void> uploadAndWait(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('upload-photo')));
    await tester.pump();
    await waitForVisible(
      tester,
      () =>
          _visible(find.text('냉장고에 있는 것')) ||
          _visible(find.byKey(const Key('failure-card'))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('사진 1장을 올리면 재료 체크리스트가 뜬다 — 코어 루프 관통', (tester) async {
    await pumpApp(tester);

    // 외길의 출발점.
    expect(find.byKey(const Key('upload-photo')), findsOneWidget);

    await uploadAndWait(tester);

    // 화면 전환 없이 같은 페이지가 체크리스트로 바뀐다(ADR-0001).
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
    for (final name in ['대파', '계란', '두부', '애호박', '고추장', '표고버섯']) {
      expect(find.text(name), findsOneWidget, reason: '$name이(가) 화면에 있어야 한다');
    }
  });

  testWidgets('confidence 3단 초기 상태가 화면에 나타난다 (ADR-0003)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await uploadAndWait(tester);

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
    await pumpApp(tester);
    await uploadAndWait(tester);

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
    await pumpApp(
      tester,
      gateway: FakeLlmGateway(latency: const Duration(seconds: 2)),
    );

    await tester.tap(find.byKey(const Key('upload-photo')));
    await tester.pump();
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('loading-message'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('loading-message')), findsOneWidget);
    expect(find.text('재료를 찾는 중이에요'), findsOneWidget);
    // 업로드한 사진이 화면에 있다.
    expect(find.byType(Image), findsWidgets);
    // 10초 전에는 취소가 없다.
    expect(find.byKey(const Key('loading-cancel')), findsNothing);

    await waitForVisible(tester, () => _visible(find.text('냉장고에 있는 것')));
    await tester.pumpAndSettle();
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
  });

  testWidgets('인식이 실패하면 인라인 카드로 해소된다 — 에러 화면이 없다', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty)),
    );
    await uploadAndWait(tester);

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

  testWidgets('인식이 오형식 200을 받아도 로딩에 고착하지 않는다 (#142)', (tester) async {
    // 200이지만 본문이 Map이 아니다. 예전에는 여기서 TypeError가 게이트웨이 밖으로 새어
    // 컨트롤러의 on LlmFailure를 지나쳤고, phase가 recognizing에 영원히 머물렀다 —
    // 사용자에게는 영영 도는 스캔 시머만 남고 실패 카드도 재시도 버튼도 없었다.
    final requests = <String>[];
    await pumpApp(
      tester,
      gateway: proxyReturning(const {}, requestLog: requests),
    );

    await uploadAndWait(tester);

    // 고착의 부재를 화면으로 확인한다 — 로딩이 아니라 실패 카드다.
    expect(find.byKey(const Key('loading-message')), findsNothing);
    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('인식에 실패했어요.'), findsOneWidget);

    // 재시도 경로가 살아 있다. 같은 오형식이 또 와도 두 번째 실패까지 화면에 도달한다 —
    // 실패가 로그에 두 번 남는 것이 "이번에도 고착하지 않았다"의 증거다.
    await tester.ensureVisible(find.byKey(const Key('failure-retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('failure-retry')));
    await tester.pump();
    await waitForEvents(
      tester,
      storage,
      (events) =>
          events.where((e) => e.type == AppEventType.errorShown).length == 2,
    );
    await tester.pumpAndSettle();

    expect(requests.length, 2, reason: '"다시 시도"가 실제로 다시 호출한다');
    expect(find.byKey(const Key('failure-card')), findsOneWidget);

    // 막다른 화면이 아니다 — 직접 입력으로 루프를 이어간다(G1 #8).
    await tapVisible(tester, find.byKey(const Key('failure-manual')));
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
    expect(find.byKey(const Key('failure-card')), findsNothing);

    // 오형식 200은 error로 정규화되어 로그에 남는다.
    final errors = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.errorShown,
    );
    expect(errors.map((e) => e.data['kind']), ['error', 'error']);
    expect(errors.first.data['stage'], 'recognition');
  });

  testWidgets('매칭이 오형식 200을 받아도 로딩에 고착하지 않는다 (#142)', (tester) async {
    // 인식은 정상, 매칭만 오형식 200 — 같은 공통 경로라 같은 모양으로 고착했다.
    final requests = <String>[];
    await pumpApp(
      tester,
      gateway: proxyReturning(const {
        '/api/recognize': _validRecognitionBody,
      }, requestLog: requests),
    );

    await uploadAndWait(tester);
    expect(find.text('냉장고에 있는 것'), findsOneWidget);

    await tapRequestSuggestions(tester);

    expect(find.byKey(const Key('matching-message')), findsNothing);
    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('메뉴를 고르지 못했어요.'), findsOneWidget);

    // 재시도가 실제로 매칭을 다시 부른다 — 버튼이 있기만 하고 아무것도 안 하면
    // 사용자에게는 고착과 구별되지 않는다.
    await tester.ensureVisible(find.byKey(const Key('failure-retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('failure-retry')));
    await tester.pump();
    await waitForEvents(
      tester,
      storage,
      (events) =>
          events.where((e) => e.type == AppEventType.errorShown).length == 2,
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((path) => path == '/api/match').length,
      2,
      reason: '"다시 시도"가 매칭을 실제로 다시 호출한다',
    );
    expect(find.byKey(const Key('failure-card')), findsOneWidget);

    // 매칭 실패의 탈출구는 재료로 돌아가는 것이다.
    await tapVisible(tester, find.byKey(const Key('failure-manual')));
    expect(find.byKey(const Key('failure-card')), findsNothing);

    // 첫 실패와 재시도 실패 둘 다 매칭 단계로 귀속돼 남는다 — 인식은 성공했다.
    final errors = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.errorShown,
    );
    expect(errors.map((e) => e.data['kind']), ['error', 'error']);
    expect(errors.map((e) => e.data['stage']), ['matching', 'matching']);
  });

  testWidgets('행 전체를 탭해 재료를 토글하고, 그게 유형·경로와 함께 남는다 (#15)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    // 체크박스가 아니라 행을 탭한다.
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));
    await tapVisible(tester, find.byKey(const Key('ingredient-row-표고버섯')));

    final edits = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.checklistEdit,
    );
    expect(edits.map((e) => (e.data['kind'], e.data['path'], e.data['name'])), [
      ('uncheck', 'row', '대파'),
      ('recheck', 'row', '표고버섯'),
    ]);
  });

  testWidgets('하단 추가 바로 빠진 재료를 넣는다 — 경로 typing (#15)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    await tester.enterText(find.byKey(const Key('add-ingredient-field')), '두유');
    await tapVisible(tester, find.byKey(const Key('add-ingredient-submit')));

    expect(find.text('두유'), findsOneWidget);

    final add = (await Storage.open()).readEvents().lastWhere(
      (e) => e.type == AppEventType.checklistEdit,
    );
    expect(add.data, {'kind': 'add', 'path': 'typing', 'name': '두유'});
  });

  testWidgets('뭉뚱그림 항목이 점선 칩으로 분리되고 인라인 치환된다 (#16)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    // "반찬통"은 본문이 아니라 "이건 뭐였나요?" 칩으로 나온다.
    expect(find.text('이건 뭐였나요?'), findsOneWidget);
    expect(find.byKey(const Key('vague-chip-반찬통')), findsOneWidget);

    // 칩을 탭하면 그 자리에서 입력창이 열린다 — 화면 전환 없음(ADR-0001).
    await tapVisible(tester, find.byKey(const Key('vague-chip-반찬통')));
    await tester.enterText(find.byKey(const Key('vague-input-반찬통')), '멸치볶음, 김');
    await tapVisible(tester, find.byKey(const Key('vague-submit-반찬통')));

    expect(find.byKey(const Key('vague-chip-반찬통')), findsNothing);
    expect(find.text('멸치볶음'), findsOneWidget);
    expect(find.text('김'), findsOneWidget);

    // 몇 개로 갈리든 수동 수정 1회다(ADR-0003).
    final edits = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.checklistEdit,
    );
    expect(edits, hasLength(1));
    expect(edits.single.data['kind'], 'substitute');
    expect(edits.single.data['path'], 'vagueChip');
  });

  testWidgets('뭉뚱그림 오탐은 탭 1회로 일반 항목이 된다 (#16)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    await tapVisible(tester, find.byKey(const Key('vague-dismiss-반찬통')));

    expect(find.byKey(const Key('vague-chip-반찬통')), findsNothing);
    expect(find.text('이건 뭐였나요?'), findsNothing);
    // 이제 체크리스트 본문의 한 행이다.
    expect(find.byKey(const Key('ingredient-row-반찬통')), findsOneWidget);

    final edits = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.checklistEdit,
    );
    expect(edits.single.data['kind'], 'vagueDismiss');
  });

  testWidgets('수정 카운터는 화면 어디에도 없다 (ADR-0004 단일맹검)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    await tester.tap(find.byKey(const Key('ingredient-row-대파')));
    await tester.pumpAndSettle();

    // 조작을 3번 해도 "3"이나 "수정" 같은 숫자·문구가 뜨지 않는다 — 죄책감 UI 회피.
    expect(find.textContaining('수정'), findsNothing);
    expect(find.textContaining('1개 고침'), findsNothing);
  });

  testWidgets('첫 방문 온보딩 카드에서 레시피 저장이 그 자리에서 끝난다 (#17)', (tester) async {
    await pumpApp(tester, skipOnboarding: false);

    // 업로드 존 자리에 온보딩 카드가 온다 — 별도 화면이 아니다(G1 #8).
    expect(find.byKey(const Key('onboarding-card')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(find.byKey(const Key('upload-photo')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('recipe-url-field')),
      'https://youtu.be/abc',
    );
    await tester.enterText(find.byKey(const Key('recipe-title-field')), '김치찌개');
    await tester.tap(find.byKey(const Key('recipe-submit')));
    await tester.pumpAndSettle();

    // 카드는 그 자리에 남고 카운터만 오른다 — "0/3, 그 자리에서 완결"(G1 #8).
    // 1개에서 카드를 치우면 3개를 채울 방법이 없다.
    expect(find.byKey(const Key('onboarding-card')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byKey(const Key('upload-photo')), findsNothing);

    final saved = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.recipeBookChanged,
    );
    expect(saved.single.data['action'], 'add');
    expect(saved.single.data['title'], '김치찌개');

    // 3개를 채우면 그제서야 업로드 존으로 넘어간다.
    for (final (i, title) in ['계란찜', '애호박볶음'].indexed) {
      await tester.enterText(
        find.byKey(const Key('recipe-url-field')),
        'https://youtu.be/more$i',
      );
      await tester.enterText(
        find.byKey(const Key('recipe-title-field')),
        title,
      );
      await tapVisible(tester, find.byKey(const Key('recipe-submit')));
    }

    expect(find.byKey(const Key('onboarding-card')), findsNothing);
    expect(find.byKey(const Key('upload-photo')), findsOneWidget);
    // 3개를 채웠으니 넛지도 사라진다.
    expect(find.byKey(const Key('recipe-nudge-chip')), findsNothing);
  });

  testWidgets('넛지 칩은 체크리스트·제안 단계에서도 상시로 남는다 (#17)', (tester) async {
    await pumpApp(tester);

    // 건너뛰면 업로드 존 + 넛지.
    expect(find.byKey(const Key('recipe-nudge-chip')), findsOneWidget);

    // 체크리스트로 넘어가도 남는다 — "3개 미만 상시".
    await uploadAndWait(tester);
    expect(find.byKey(const Key('recipe-nudge-chip')), findsOneWidget);

    // 제안 단계에서도.
    await tapRequestSuggestions(tester);
    expect(find.byKey(const Key('recipe-nudge-chip')), findsOneWidget);
  });

  testWidgets('레시피 북 재료 중 미인식 재료가 강조 칩으로 뜨고 탭으로 추가된다 (#17)', (tester) async {
    // 먼저 레시피를 하나 담는다.
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await uploadAndWait(tester);

    // 김치찌개 재료 중 사진에서 안 나온 것들.
    expect(find.text('레시피 북에 있는 재료예요 — 혹시 있나요?'), findsOneWidget);
    expect(find.byKey(const Key('recipe-book-chip-김치')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('recipe-book-chip-김치')));

    // 체크리스트에 들어가고 칩에서는 빠진다.
    expect(find.byKey(const Key('ingredient-row-김치')), findsOneWidget);
    expect(find.byKey(const Key('recipe-book-chip-김치')), findsNothing);

    final edit = (await Storage.open()).readEvents().lastWhere(
      (e) => e.type == AppEventType.checklistEdit,
    );
    expect(edit.data['path'], 'recipeBookChip');
  });

  testWidgets('레시피 북에서 저장·삭제가 되고 이벤트로 남는다 (#17)', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('recipe-url-field')),
      'https://youtu.be/abc',
    );
    await tester.enterText(find.byKey(const Key('recipe-title-field')), '김치찌개');
    await tester.tap(find.byKey(const Key('recipe-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/abc')),
      findsOneWidget,
    );
    expect(find.text('김치찌개'), findsOneWidget);
    // 제목에서 추론된 재료가 보인다.
    expect(find.textContaining('돼지고기'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('recipe-remove-https://youtu.be/abc')),
    );
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 레시피가 없어요.'), findsOneWidget);

    final events = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.recipeBookChanged,
    );
    expect(events.map((e) => e.data['action']), ['add', 'remove']);
  });

  testWidgets('확정 재료로 "오늘 할 3개"가 뜬다 — 라벨·출처·부족 칩 (#18)', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await uploadAndWait(tester);

    await tapRequestSuggestions(tester);

    expect(find.text('오늘 할 3개'), findsOneWidget);

    // 저장 제안이 먼저 온다 — 출처 배지와 "레시피 보기"가 붙는다.
    expect(find.byKey(const Key('suggestion-card-김치찌개')), findsOneWidget);
    expect(find.text('내 레시피 북'), findsOneWidget);
    expect(find.byKey(const Key('open-recipe-김치찌개')), findsOneWidget);

    // 라벨 3종이 색+아이콘으로 뜬다.
    expect(find.byKey(const Key('label-badge-ready')), findsOneWidget);
    expect(find.byKey(const Key('label-badge-buyOne')), findsOneWidget);
    expect(find.byKey(const Key('label-badge-maybe')), findsOneWidget);

    // AI 제안엔 "레시피 보기"가 없다 — 열 원본이 없다.
    expect(find.text('AI 제안'), findsWidgets);
    expect(find.byKey(const Key('open-recipe-애호박볶음')), findsNothing);

    // 부족 재료 칩 — 대체 해소는 화살표로.
    expect(find.byKey(const Key('missing-chip-식용유')), findsOneWidget);
    expect(find.text('우유→두유'), findsOneWidget);

    final events = (await Storage.open()).readEvents();
    final done = events.lastWhere((e) => e.type == AppEventType.matchingDone);
    expect(done.data['costUsd'], 0.00044);
    expect(done.data['shownCount'], 3);

    final shown = events.lastWhere(
      (e) => e.type == AppEventType.suggestionsShown,
    );
    expect(shown.data['sources'], ['saved', 'generated', 'generated']);
  });

  testWidgets('매칭 중에는 "레시피 북 N개와 맞춰보는 중"이 뜬다 (#18)', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(
      tester,
      gateway: FakeLlmGateway(latency: const Duration(seconds: 1)),
    );
    await uploadAndWait(tester);

    final button = find.byKey(const Key('request-suggestions'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await waitForVisible(tester, () => _visible(find.textContaining('맞춰보는 중')));
    await tester.pump();

    expect(find.text('레시피 북 1개와 맞춰보는 중'), findsOneWidget);

    await waitForVisible(tester, () => _visible(find.text('오늘 할 3개')));
    await tester.pumpAndSettle();
  });

  testWidgets('부족 4개 이상 메뉴는 제외되고 투명성 줄에 집계된다 (#18)', (tester) async {
    final gateway = FakeLlmGateway()
      ..suggestions = [
        const Suggestion(
          menu: '두부조림',
          source: SuggestionSource.generated,
          missing: [],
          reason: '두부가 있어요.',
        ),
        const Suggestion(
          menu: '불가능한메뉴',
          source: SuggestionSource.generated,
          missing: [
            MissingIngredient(name: 'a'),
            MissingIngredient(name: 'b'),
            MissingIngredient(name: 'c'),
            MissingIngredient(name: 'd'),
          ],
          reason: '',
        ),
      ];

    await pumpApp(tester, gateway: gateway);
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    expect(find.byKey(const Key('suggestion-card-불가능한메뉴')), findsNothing);
    expect(find.byKey(const Key('transparency-line')), findsOneWidget);
    expect(find.text('부족 4개 이상이라 제외한 메뉴 1개'), findsOneWidget);
  });

  testWidgets('"이거 했어요" → 5초 실행취소, 둘 다 로그에 남는다 (#19)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    const menu = '애호박볶음'; // 레시피 북이 비어 첫 제안은 generated 애호박볶음(fake)
    final cooked = find.byKey(const Key('cooked-$menu'));
    await tester.ensureVisible(cooked);
    await tester.pumpAndSettle();
    await tester.tap(cooked);
    await tester.pump();

    // 5초 실행취소 토스트.
    expect(find.text('실행취소'), findsOneWidget);
    await tester.tap(find.text('실행취소'));
    await tester.pumpAndSettle();

    final events = (await Storage.open()).readEvents();
    expect(
      events.where((e) => e.type == AppEventType.cooked).single.data['menu'],
      menu,
    );
    expect(
      events
          .where((e) => e.type == AppEventType.cookedUndo)
          .single
          .data['menu'],
      menu,
    );
  });

  testWidgets('카드를 탭하면 제안 상세로 가고, 상세의 "이거 했어요"가 메인에 토스트를 띄운다 (P4)', (
    tester,
  ) async {
    // 저장 제안(김치찌개)은 recipeUrl이 있어 영상 pill·있는 재료가 뜬다.
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    // 카드 루트(사진 영역)를 탭하면 상세로 push된다 — 버튼이 아니라 카드 몸통.
    final card = find.byKey(const Key('suggestion-card-김치찌개'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    // 상세 전용 키가 뜬다(카드에는 없다).
    expect(find.byKey(const Key('detail-cooked-김치찌개')), findsOneWidget);
    expect(find.byKey(const Key('detail-open-recipe-김치찌개')), findsOneWidget);
    expect(find.byKey(const Key('detail-back')), findsOneWidget);

    // 뒤로가면 메인으로 복귀한다(pop만, push 아님).
    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-cooked-김치찌개')), findsNothing);
    expect(find.byKey(const Key('suggestion-card-김치찌개')), findsOneWidget);

    // 다시 열어 상세에서 "이거 했어요"를 누른다.
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    final detailCooked = find.byKey(const Key('detail-cooked-김치찌개'));
    await tester.ensureVisible(detailCooked);
    await tester.pumpAndSettle();
    await tester.tap(detailCooked);
    await tester.pumpAndSettle();

    // 상세는 닫히고, 실행취소 토스트는 메인 위에 뜬다(오펀 아님).
    expect(find.byKey(const Key('detail-cooked-김치찌개')), findsNothing);
    expect(find.byKey(const Key('cooked-toast')), findsOneWidget);
    expect(find.text('실행취소'), findsOneWidget);

    final cooked = (await Storage.open()).readEvents().where(
      (e) => e.type == AppEventType.cooked,
    );
    expect(cooked.single.data['menu'], '김치찌개');
  });

  testWidgets('재료를 재수정하면 "다시 제안" 배너가 뜨고 stale이 붙는다 (#19)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    // 제안이 뜨면 체크리스트는 요약 한 줄로 접힌다(G1 #8).
    expect(find.byKey(const Key('checklist-summary')), findsOneWidget);
    expect(find.byKey(const Key('rematch-banner')), findsNothing);

    // 펼쳐서 재료를 손본다 — 아래 제안이 낡는다.
    await tapVisible(tester, find.byKey(const Key('checklist-summary')));
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));

    expect(find.byKey(const Key('rematch-banner')), findsOneWidget);

    // 낡은 카드에서 누른 "이거 했어요"에는 stale이 붙는다.
    const menu = '애호박볶음'; // 레시피 북이 비어 첫 제안은 generated 애호박볶음(fake)
    final cooked = find.byKey(const Key('cooked-$menu'));
    await tester.ensureVisible(cooked);
    await tester.pumpAndSettle();
    await tester.tap(cooked);
    await tester.pump();

    final staleCooked = (await Storage.open()).readEvents().lastWhere(
      (e) => e.type == AppEventType.cooked,
    );
    expect(staleCooked.data['stale'], isTrue);
  });

  testWidgets('"다시 제안"이 이벤트로 남고 새 제안은 stale이 아니다 (#19)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    await tapVisible(tester, find.byKey(const Key('checklist-summary')));
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));

    final rematch = find.byKey(const Key('rematch-button'));
    await tester.ensureVisible(rematch);
    await tester.pumpAndSettle();
    await tester.tap(rematch);
    await tester.pump();
    await waitForVisible(tester, () => _visible(find.text('오늘 할 3개')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rematch-banner')), findsNothing);

    final events = (await Storage.open()).readEvents();
    expect(events.where((e) => e.type == AppEventType.rematch), hasLength(1));
    expect(
      events
          .lastWhere((e) => e.type == AppEventType.suggestionsShown)
          .data['stale'],
      isFalse,
    );
  });

  testWidgets('레시피 북 최하단 백업 — 내보내기·미리보기·가져오기 (#20)', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();

    // 백업은 이 화면 최하단이다.
    final section = find.byKey(const Key('backup-section'));
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    expect(section, findsOneWidget);

    // 한 동작 내보내기 — 클립보드로 나가고 이벤트가 남는다.
    final exportButton = find.byKey(const Key('backup-export'));
    await tester.ensureVisible(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pump();

    final afterExport = await waitForEvents(
      tester,
      storage,
      (events) => events.any((e) => e.type == AppEventType.backup),
    );
    final exported = afterExport.lastWhere(
      (e) => e.type == AppEventType.backup,
    );
    expect(exported.data['direction'], 'export');
    expect(exported.data['recipeCount'], 1);
    await tester.pumpAndSettle();

    // 다른 기기 백업을 붙여넣고 미리보기 → 확정.
    final incoming = jsonEncode(
      BackupData(
        recipes: const [
          Recipe(
            url: 'https://youtu.be/xyz',
            title: '계란찜',
            ingredients: ['계란'],
          ),
        ],
        events: const [],
        exportedAt: DateTime.utc(2026, 7, 14),
      ).toJson(),
    );

    final field = find.byKey(const Key('backup-import-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, incoming);
    final preview = find.byKey(const Key('backup-preview'));
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();

    // 확정 전에 무엇이 들어올지 보여준다(C 이식).
    expect(find.byKey(const Key('merge-preview')), findsOneWidget);
    expect(find.textContaining('계란찜'), findsWidgets);
    expect(find.text('레시피 1개가 새로 들어와요.'), findsOneWidget);
    expect(find.text('레시피만 가져옵니다. 이 기기의 기록은 그대로예요.'), findsOneWidget);

    // 미리보기가 열리며 레이아웃이 길어졌다 — 확정 버튼을 화면에 올린 뒤 누른다.
    final confirm = find.byKey(const Key('backup-confirm'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();

    final afterImport = await waitForEvents(
      tester,
      storage,
      (events) => events.any(
        (e) => e.type == AppEventType.backup && e.data['direction'] == 'import',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/xyz')),
      findsOneWidget,
    );

    final imported = afterImport.lastWhere(
      (e) => e.type == AppEventType.backup && e.data['direction'] == 'import',
    );
    expect(imported.data['newRecipes'], 1);
  });

  testWidgets('7일이 지나면 주간 성적표 배너가 뜬다 — 수동 수정 수는 없다 (#20)', (tester) async {
    // 8일 전 업로드 1건 + 이번 주 조작 여러 건.
    await storage.appendEvent(
      AppEvent.photoUpload(
        at: DateTime.now().subtract(const Duration(days: 8)),
        bytes: 1,
        width: 768,
      ),
    );
    for (var i = 0; i < 7; i++) {
      await storage.appendEvent(
        AppEvent.checklistEdit(
          at: DateTime.now(),
          kind: EditKind.uncheck,
          path: EditPath.row,
          name: '재료$i',
        ),
      );
    }

    await pumpApp(tester);

    expect(find.byKey(const Key('weekly-report-banner')), findsOneWidget);
    // 업로드는 8일 전이라 이번 주 집계는 0이다.
    expect(find.text('이번 주 업로드 0회, 이거 했어요 0회 — 기록 저장하기'), findsOneWidget);
    // 조작을 7번 했어도 그 숫자는 어디에도 없다(ADR-0004).
    expect(find.textContaining('수정'), findsNothing);
    expect(find.textContaining('7회'), findsNothing);
  });

  testWidgets('카톡 인앱 브라우저면 상시 경고 배너가 뜬다 (#21)', (tester) async {
    await pumpApp(
      tester,
      userAgent:
          'Mozilla/5.0 (Linux; Android 14) Mobile Safari/537.36 KAKAOTALK 10.4.5',
    );

    expect(find.byKey(const Key('in-app-browser-banner')), findsOneWidget);
    expect(find.text('여기서는 기록이 사라질 수 있어요'), findsOneWidget);
    // 기본 브라우저로 열기 + 홈 화면 추가 안내(G1 #8).
    expect(find.textContaining('다른 브라우저로 열기'), findsOneWidget);
    expect(find.textContaining('홈 화면에 추가'), findsOneWidget);
  });

  testWidgets('일반 브라우저면 경고가 없다 (#21)', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('in-app-browser-banner')), findsNothing);
  });

  testWidgets('첫 인식 결과 위에 기대 세팅 문구가 1회만 뜬다 (#21)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    expect(find.byKey(const Key('expectation-note')), findsOneWidget);
    expect(find.text('인식이 틀려도 괜찮아요 — 체크로 다듬는 게 정상이에요.'), findsOneWidget);

    // 다시 열면(새 컨트롤러) 이제 안 뜬다 — 브라우저 스토리지에 남는 1회성이다.
    await pumpApp(tester);
    await uploadAndWait(tester);
    expect(find.byKey(const Key('expectation-note')), findsNothing);
  });

  testWidgets('매칭 실패도 인라인 카드로 해소된다 — 에러 화면이 없다 (#21)', (tester) async {
    await pumpApp(
      tester,
      gateway: FakeLlmGateway(
        matchFailure: const LlmFailure(LlmFailureKind.timeout),
      ),
    );
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('메뉴를 고르는 데 시간이 너무 걸렸어요.'), findsOneWidget);
    // 재료 섹션이 위에 그대로, 펼쳐진 채로 있다 — 접힘은 매칭이 성공했을 때만이고,
    // 실패했으면 손봐야 할 대상이 바로 그 재료다. 막다른 화면이 아니다.
    expect(find.text('냉장고에 있는 것'), findsOneWidget);
    expect(find.byKey(const Key('ingredient-row-대파')), findsOneWidget);

    // "재료 다시 보기"로 루프를 이어간다.
    final fallback = find.byKey(const Key('failure-manual'));
    await tester.ensureVisible(fallback);
    await tester.pumpAndSettle();
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failure-card')), findsNothing);

    final errors = await waitForEvents(
      tester,
      storage,
      (events) => events.any((e) => e.type == AppEventType.errorShown),
    );
    final error = errors.lastWhere((e) => e.type == AppEventType.errorShown);
    expect(error.data['stage'], 'matching');
    expect(error.data['kind'], 'timeout');
  });

  testWidgets('측정 푸터는 앱바 타이틀 롱프레스로만 열린다 (#143, ADR-0004)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    // 열기 전에는 트리에 없다 — 제스처를 모르는 배우자에게는 도달 경로가 없다.
    expect(find.byKey(const Key('debug-footer')), findsNothing);

    await openDebugFooter(tester);

    final footer = find.byKey(const Key('debug-footer'));
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();

    expect(footer, findsOneWidget);
    expect(find.textContaining('인식'), findsWidgets);
    // 파운더는 수동 수정 수를 본다 — 여기서만.
    expect(find.textContaining('수동 수정'), findsOneWidget);

    // 같은 제스처로 도로 닫는다 — 배우자가 다가오면 재시작 말고 이걸 쓴다.
    await openDebugFooter(tester);
    expect(find.byKey(const Key('debug-footer')), findsNothing);
  });

  testWidgets('제스처 전에는 측정 푸터가 트리에 없다 — 숨김이 아니라 부재다 (#143)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    expect(find.byKey(const Key('debug-footer')), findsNothing);
    // 배우자 화면 어디에도 계측이 새지 않는다(ADR-0004).
    expect(find.textContaining('수동 수정'), findsNothing);
    expect(find.textContaining('토큰'), findsNothing);
  });

  testWidgets('앱을 다시 띄우면 푸터는 도로 숨는다 — 그 세션 한정이다 (#143)', (tester) async {
    await pumpApp(tester);
    await openDebugFooter(tester);
    expect(find.byKey(const Key('debug-footer')), findsOneWidget);

    // [restartApp]은 컨트롤러를 새로 만들지만 [storage]는 그대로 살아 있다 — 그래서
    // 이 단언의 이빨은 "누군가 열림 여부를 영속층에 저장했는가"에 정확히 걸린다.
    // 저장하는 순간 배우자 기기에 잔상이 남고 단일맹검(ADR-0004)이 깨진다.
    await restartApp(tester);

    expect(find.byKey(const Key('debug-footer')), findsNothing);
  });

  testWidgets('코어 루프+백업 관통 후 export JSON에 이벤트 12종이 전부 있다 (#22)', (
    tester,
  ) async {
    // ⑩ 레시피 북 변경
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    // ⑫ 오류 표시 — 첫 시도를 실패시켜 오류를 만든 뒤 직접 입력으로 잇는다.
    await pumpApp(
      tester,
      gateway: FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty)),
    );
    await uploadAndWait(tester);
    await tester.tap(find.byKey(const Key('failure-manual')));
    await tester.pumpAndSettle();

    // ① 사진 업로드 ② 인식 완료
    await pumpApp(tester);
    await uploadAndWait(tester);

    // ③ 체크리스트 조작
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));

    // ④ 매칭 완료 ⑤ 제안 노출
    await tapRequestSuggestions(tester);

    // ⑥ 제안 선택 — 저장 카드만 "레시피 보기"를 가진다(김치찌개, 레시피 북 유래).
    await tapVisible(tester, find.byKey(const Key('open-recipe-김치찌개')));

    // ⑦ 이거 했어요 ⑧ 실행취소
    const menu = '김치찌개'; // 레시피 북에 김치찌개가 있어 첫 제안은 saved 김치찌개(fake)
    await tapVisible(tester, find.byKey(const Key('cooked-$menu')));
    await tester.tap(find.text('실행취소'));
    await tester.pumpAndSettle();

    // ⑨ 다시 제안 — 재료를 손봐 낡게 만든 뒤 갱신.
    await tapVisible(tester, find.byKey(const Key('checklist-summary')));
    await tapVisible(tester, find.byKey(const Key('ingredient-row-계란')));
    await tapVisible(tester, find.byKey(const Key('rematch-button')));
    await tester.pump();
    await waitForVisible(tester, () => _visible(find.text('오늘 할 3개')));
    await tester.pumpAndSettle();

    // ⑪ 백업 export/import
    final backup = BackupController(storage);
    await backup.exportJson();
    backup.previewImport(
      jsonEncode(
        BackupData(
          recipes: const [
            Recipe(
              url: 'https://youtu.be/other',
              title: '계란찜',
              ingredients: ['계란'],
            ),
          ],
          events: const [],
          exportedAt: DateTime.utc(2026, 7, 14),
        ).toJson(),
      ),
    );
    await backup.confirmImport();

    // export JSON이 분석에 넘어가는 유일한 산출물이다 — 여기 다 있어야 한다.
    final exported =
        jsonDecode(await BackupController(storage).exportJson())
            as Map<String, Object?>;
    final events = (exported['events'] as List).cast<Map<String, Object?>>();
    final types = events.map((e) => e['type']).toSet();

    for (final type in AppEventType.values) {
      expect(
        types,
        contains(type.name),
        reason: '이벤트 카탈로그 ${type.name}이(가) export JSON에 없다',
      );
    }
    expect(types, hasLength(AppEventType.values.length), reason: '12종 전부');

    // 모든 이벤트에 타임스탬프가 있다.
    for (final event in events) {
      expect(event['at'], isA<String>());
      expect(() => DateTime.parse(event['at']! as String), returnsNormally);
    }

    // 요구 필드 — 유형·경로·stale·토큰·원가.
    Map<String, Object?> firstOf(String type) =>
        events.firstWhere((e) => e['type'] == type);

    final edit = firstOf('checklistEdit');
    expect(edit['kind'], isA<String>(), reason: '유형');
    expect(edit['path'], isA<String>(), reason: '경로');

    final recognition = firstOf('recognitionDone');
    expect(recognition['promptTokens'], isA<int>(), reason: '토큰');
    expect(recognition['thoughtTokens'], isA<int>(), reason: 'thinking 토큰');
    expect(recognition['costUsd'], isA<num>(), reason: '원가');
    expect(recognition['model'], isA<String>(), reason: '모델 귀속');

    final matching = firstOf('matchingDone');
    expect(matching['costUsd'], isA<num>());
    expect(matching['excludedCount'], isA<int>());

    expect(firstOf('suggestionsShown')['stale'], isA<bool>(), reason: 'stale');
    expect(firstOf('cooked')['stale'], isA<bool>(), reason: 'stale');
    expect(firstOf('cookedUndo')['stale'], isA<bool>(), reason: 'stale');
    expect(firstOf('suggestionOpened')['stale'], isA<bool>(), reason: 'stale');
    expect(firstOf('backup')['direction'], isA<String>());
    expect(firstOf('errorShown')['kind'], isA<String>(), reason: '오류 유형');

    // 레시피 북도 같은 파일에 있다(US 30) — 백업 2개로 가구 단위 분석이 된다.
    expect(exported['recipes'], isNotEmpty);
  });

  testWidgets('D0 전 기록 초기화 리허설 — 푸터에서 지우면 레시피만 남는다 (#41, #144)', (
    tester,
  ) async {
    // 관통 테스트 흔적을 실 UI로 만든다 — 레시피 저장 + 업로드·인식 + 체크 수정 + 매칭.
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));
    await tapRequestSuggestions(tester);

    // 지울 것이 실제로 쌓였는지 먼저 본다 — 안 쌓였으면 아래 "0이 됐다"가 공허해진다.
    final before = storage.readEvents().map((e) => e.type).toSet();
    for (final type in [
      AppEventType.photoUpload,
      AppEventType.recognitionDone,
      AppEventType.checklistEdit,
      AppEventType.matchingDone,
    ]) {
      expect(before, contains(type), reason: '관통 이벤트 $type이(가) 안 쌓였다');
    }

    // 절차 ① 제스처로 측정 푸터를 연다. 절차 ② 초기화 → 확인. 끝이다.
    //
    // 웹 시절의 5단계(복사 → 카톡 보관 → 사이트 데이터 삭제 → 재열기 → 붙여넣기)는
    // **브라우저가 선택적 삭제를 못 해서** 생긴 우회였다. 네이티브는 키 단위로 지우므로
    // export도 재import도 절차에서 통째로 빠진다(#144).
    await openDebugFooter(tester);
    await resetPilotRecord(tester);

    // 웹에서는 재import가 backup/import 1건을 남겨 "이벤트 1"이 정상이었다.
    // 재import가 사라졌으므로 네이티브에서는 **0이 정상**이다 — 불변식이 뒤집혔다.
    final footer = find.byKey(const Key('debug-footer'));
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    expect(find.text('이벤트 0'), findsOneWidget);
    expect(find.text('수동 수정 0'), findsOneWidget);

    // 레시피 북은 그대로다 — 파일럿의 입력이라 살아남아야 한다.
    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/abc')),
      findsOneWidget,
    );

    // 다시 띄워도 지워진 채다 — 그리고 관통 테스트의 체크리스트가 되살아나지 않는다.
    // 세션까지 지우는 이유가 정확히 이것이다(#144 보존 경계).
    await restartApp(tester);
    expect(storage.readEvents(), isEmpty);
    expect(find.byKey(const Key('ingredient-row-대파')), findsNothing);
    expect(storage.readRecipes(), hasLength(1));
  });

  testWidgets('초기화 확인을 취소하면 아무것도 지워지지 않는다 (#144)', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

    await pumpApp(tester);
    await uploadAndWait(tester);
    await tapVisible(tester, find.byKey(const Key('ingredient-row-대파')));

    final before = storage.readEvents();
    expect(before, isNotEmpty, reason: '지울 것이 없으면 취소 테스트가 공허하다');

    await openDebugFooter(tester);
    await tapVisible(tester, find.byKey(const Key('reset-record')));
    await tester.tap(find.byKey(const Key('reset-cancel')));
    await tester.pumpAndSettle();

    // 파괴적 동작이 숨은 화면 안의 단일 탭이면 오조작이 곧 데이터 손실이다 —
    // 확인 단계가 실제로 막아주는지가 이 테스트의 전부다.
    expect(storage.readEvents().length, before.length);
    expect(storage.readRecipes(), hasLength(1));
    // 화면도 그대로다 — 취소가 세션까지 되감지 않는다.
    expect(find.byKey(const Key('ingredient-row-대파')), findsOneWidget);
  });

  testWidgets('초기화 버튼은 푸터 안에만 있다 — 배우자에게는 도달 경로가 없다 (#144)', (tester) async {
    await pumpApp(tester);
    await uploadAndWait(tester);

    // 푸터를 열기 전에는 버튼이 트리에 없다. 배우자는 제스처를 모르므로 푸터를 못 열고,
    // 따라서 파일럿 데이터를 지울 방법 자체가 없다(ADR-0004 단일맹검).
    expect(find.byKey(const Key('reset-record')), findsNothing);

    await openDebugFooter(tester);
    expect(find.byKey(const Key('reset-record')), findsOneWidget);

    // 푸터를 도로 닫으면 버튼도 같이 사라진다.
    await openDebugFooter(tester);
    expect(find.byKey(const Key('reset-record')), findsNothing);
  });

  testWidgets('하단 탭 바로 레시피 북에 오가고 헤더 링크도 병행한다 (ADR-0007)', (tester) async {
    await pumpApp(tester);

    // Material 3 NavigationBar 하나(구식 BottomNavigationBar는 안 씀).
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byKey(const Key('recipe-book-link')));
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 레시피가 없어요.'), findsOneWidget);
  });
}
