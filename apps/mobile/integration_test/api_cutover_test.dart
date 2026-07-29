// 컷오버(#121) E2E — 서버 레시피 북 미러가 브라우저에서 보이는 것과 export에 남는 것을 검증한다.
// 실행: scripts/e2e.sh integration_test/api_cutover_test.dart  (chromedriver + flutter drive, core_loop와 동형)
//
// 서버는 FakeServerRecipeRepository, LLM은 FakeLlmGateway, 기기 세션은 FakeDeviceSession —
// 결정적 페이크 3개를 seam에 주입한다(#168로 2개 → 3개).
import 'dart:async';
import 'dart:convert';

import 'package:cookmark/app.dart';
import 'package:cookmark/auth/api_v1_device_session.dart';
import 'package:cookmark/auth/fake_device_session.dart';
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/backup.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
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

/// 실제 JPEG — 리사이즈 경로(dart:ui 디코더)를 브라우저에서 진짜로 태운다(core_loop 관용구).
XFile fridgePhotoFile() {
  final image = img.Image(width: 1600, height: 1200);
  for (var y = 0; y < 1200; y++) {
    for (var x = 0; x < 1600; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return XFile.fromData(img.encodeJpg(image), mimeType: 'image/jpeg');
}

/// 화면이 [ready]를 만족할 때까지 기다린다 — 프레임이 아니라 화면 상태를 기다린다(core_loop 관용구).
Future<void> waitForVisible(
  WidgetTester tester,
  bool Function() ready, {
  Duration limit = const Duration(seconds: 20),
}) async {
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

/// 이벤트가 스토리지에 실제로 도착할 때까지 기다린다(core_loop 관용구).
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

/// 서버 레시피 북 fixture — id는 Fake가 'srv-N'으로 발급한다.
const seedThree = [
  Recipe(url: 'https://youtu.be/1', title: '김치찌개', ingredients: ['김치', '돼지고기']),
  Recipe(url: 'https://youtu.be/2', title: '계란찜', ingredients: ['계란']),
  Recipe(url: 'https://youtu.be/3', title: '애호박볶음', ingredients: ['애호박']),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    storage = await Storage.open();
    // 브라우저 localStorage는 테스트 사이에 살아남는다 — 비우고 시작해야 결정적이다.
    await storage.clear();
  });

  /// 컷오버 엔트리(main_api_cutover)와 동형 조립 — 서버 repository 주입 + 부팅 하이드레이트 킥.
  ///
  /// [server]가 `ServerRecipeRepository` 타입인 이유(#168) — 대부분의 케이스는 페이크를 꽂지만
  /// 401 재등록만은 **실 구현 + 가짜 전송**으로 태워야 한다. 401 복구가 전송 초크에 살아서
  /// 경계 페이크로는 도달할 수 없기 때문이다.
  Future<void> pumpApp(
    WidgetTester tester, {
    required ServerRecipeRepository server,
    FakeLlmGateway? gateway,
    bool skipOnboarding = true,
  }) async {
    final llm = gateway ?? FakeLlmGateway();
    final controller = MainController(
      llm,
      storage,
      userAgent: () => 'Mozilla/5.0 Chrome/120.0.0.0 Mobile Safari/537.36',
    );
    final book = RecipeBookController(llm, storage, server: server);
    // 부팅 킥 — 기다리지 않는다. 지연·실패는 화면 상태(스켈레톤·에러 카드)로 가시화된다.
    unawaited(book.hydrate());
    await tester.pumpWidget(
      CookmarkApp(
        controller: controller,
        recipeBookController: book,
        backupController: BackupController(
          storage,
          server: server,
          // 미러가 ready가 아닌 동안 가져오기를 막는다 — 스테일 dedup 중복 등록 방지(#121, 엔트리와 동형).
          serverSyncState: () => book.syncState,
          // 확정 후 재수화도 같은 hydrate로 — 실패 시 error 전이로 게이트가 닫힌다(엔트리와 동형).
          serverRehydrate: book.hydrate,
        ),
        imagePicker: () async => fridgePhotoFile(),
      ),
    );
    await tester.pumpAndSettle();

    final skip = find.byKey(const Key('onboarding-skip'));
    if (skipOnboarding && skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }
  }

  /// 스크롤 안의 위젯은 뷰포트 밖이면 탭이 안 먹는다 — 올린 뒤 누른다.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openRecipeBook(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('recipe-book-link')));
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

  testWidgets('① 부팅 하이드레이트 — 서버에 3개면 온보딩 없이 카운트가 반영된다', (tester) async {
    final server = FakeServerRecipeRepository(seed: seedThree);
    await pumpApp(tester, server: server, skipOnboarding: false);

    // 서버 목록이 미러로 내려와 3개 — 온보딩 카드가 설 자리가 없다.
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );
    expect(find.byKey(const Key('onboarding-card')), findsNothing);
    expect(find.byKey(const Key('recipe-nudge-chip')), findsNothing);
    expect(server.fetchAllCallCount, 1, reason: '부팅 킥 1회뿐');

    await openRecipeBook(tester);
    expect(find.text('저장한 레시피 · 3'), findsOneWidget);
  });

  testWidgets('② 하이드레이트 동안 스켈레톤이 뜬다 — 스피너 없이, ready 후 리스트로', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: seedThree,
      latency: const Duration(seconds: 3),
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);

    // 정직한 로딩 — 곧 나타날 리스트의 모양이지 원형 스피너가 아니다(DESIGN.md §7).
    expect(find.byKey(const Key('recipe-list-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-list-skeleton')), findsNothing);
    expect(find.text('저장한 레시피 · 3'), findsOneWidget);
  });

  testWidgets('③ 401이면 리스트 자리 인라인 에러 — 다시 시도로 복구된다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: seedThree,
      failure: const RecipeApiFailure(RecipeApiFailureKind.unauthorized),
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);

    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-list-error'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('접속 정보가 유효하지 않아요.'), findsOneWidget);
    // 에러 동안 저장 폼도 잠긴다 — 컨트롤러가 버릴 입력을 받는 척하지 않는다.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recipe-url-field')))
          .enabled,
      isFalse,
    );

    // 서버가 살아났다 — 에러 카드의 "다시 시도"가 재수화를 건다.
    server.failure = null;
    await tapVisible(tester, find.byKey(const Key('recipe-list-error-retry')));
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-list-error')), findsNothing);
  });

  testWidgets('④ 저장 — 서버 create가 행·메인 탭에 반영되고 이벤트에 usage 키가 없다', (
    tester,
  ) async {
    final server = FakeServerRecipeRepository();
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(tester, () => _visible(find.text('아직 저장한 레시피가 없어요.')));

    await tester.enterText(
      find.byKey(const Key('recipe-url-field')),
      'https://youtu.be/abc',
    );
    await tester.enterText(find.byKey(const Key('recipe-title-field')), '김치찌개');
    await tester.tap(find.byKey(const Key('recipe-submit')));
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/abc'))),
    );
    await tester.pumpAndSettle();

    expect(server.recipes.single.url, 'https://youtu.be/abc');
    // 서버가 저장 시 추출한 재료가 행에 보인다.
    expect(find.textContaining('돼지고기'), findsOneWidget);

    final events = await waitForEvents(
      tester,
      storage,
      (events) => events.any((e) => e.type == AppEventType.recipeBookChanged),
    );
    final added = events.lastWhere(
      (e) => e.type == AppEventType.recipeBookChanged,
    );
    expect(added.data['action'], 'add');
    expect(
      added.data.containsKey('costUsd'),
      isFalse,
      reason: '추출은 서버 안에서 돌았다 — 클라이언트가 아는 usage가 없다',
    );

    // 메인 탭도 같은 미러를 읽는다 — 넛지 카운트가 따라온다.
    await tester.tap(find.text('메인'));
    await tester.pumpAndSettle();
    expect(find.text('믿고 보는 레시피 담기 1/3'), findsOneWidget);
  });

  testWidgets('⑤ 저장 실패(502=미저장) — 리스트 무변화, 실패 카드의 재시도로 성공한다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: 'https://youtu.be/x', title: '계란찜', ingredients: ['계란']),
      ],
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/x'))),
    );

    server.failure = const RecipeApiFailure(
      RecipeApiFailureKind.extractionFailed,
    );
    await tester.enterText(
      find.byKey(const Key('recipe-url-field')),
      'https://youtu.be/y',
    );
    await tester.enterText(find.byKey(const Key('recipe-title-field')), '김치찌개');
    await tester.tap(find.byKey(const Key('recipe-submit')));
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-add-failure-card'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('재료를 알아내지 못해 저장하지 못했어요'), findsOneWidget);
    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/y')),
      findsNothing,
    );
    expect(server.recipes, hasLength(1), reason: '서버도 미저장');

    // 서버가 살아났다 — 폼은 비워졌지만 failedAdd가 입력을 기억한다.
    server.failure = null;
    await tapVisible(tester, find.byKey(const Key('recipe-add-retry')));
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/y'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-add-failure-card')), findsNothing);
    expect(server.recipes, hasLength(2));
  });

  testWidgets('⑥ 삭제 — 행·서버·미러에서 함께 사라진다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
      ],
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/a'))),
    );

    await tapVisible(
      tester,
      find.byKey(const Key('recipe-remove-https://youtu.be/a')),
    );
    await waitForVisible(
      tester,
      () => !_visible(find.byKey(const Key('recipe-tile-https://youtu.be/a'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 저장한 레시피가 없어요.'), findsOneWidget);
    expect(server.recipes, isEmpty);
    expect((await Storage.open()).readRecipes(), isEmpty, reason: '미러도 비었다');
  });

  testWidgets('⑦ 가져오기 — newRecipes만 서버로 가고 남의 이벤트는 들어오지 않는다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
      ],
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/a'))),
    );

    // 다른 기기 백업 — 겹치는 a + 새 b + 남의 이벤트 1건.
    final incoming = jsonEncode(
      BackupData(
        recipes: const [
          Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
          Recipe(url: 'https://youtu.be/b', title: '계란찜', ingredients: ['계란']),
        ],
        events: [
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 13),
            bytes: 1,
            width: 768,
          ),
        ],
        exportedAt: DateTime.utc(2026, 7, 14),
      ).toJson(),
    );

    final field = find.byKey(const Key('backup-import-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, incoming);
    await tapVisible(tester, find.byKey(const Key('backup-preview')));
    expect(find.byKey(const Key('merge-preview')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('backup-confirm')));

    final events = await waitForEvents(
      tester,
      storage,
      (events) => events.any(
        (e) => e.type == AppEventType.backup && e.data['direction'] == 'import',
      ),
    );
    await tester.pumpAndSettle();

    // 서버엔 newRecipes만 도착 — 겹치는 a는 클라이언트 dedup이 걸렀다.
    expect(server.importBulkCallCount, 1);
    expect(server.lastImportBulk!.map((r) => r.url), ['https://youtu.be/b']);
    expect(server.recipes.map((r) => r.url), [
      'https://youtu.be/a',
      'https://youtu.be/b',
    ]);
    // 미러는 서버 재수화 정본이다.
    expect((await Storage.open()).readRecipes().map((r) => r.url), [
      'https://youtu.be/a',
      'https://youtu.be/b',
    ]);
    // 남의 이벤트는 0건 유입 — 인별 귀속(US 30)이 유지된다.
    expect(events.where((e) => e.type == AppEventType.photoUpload), isEmpty);
  });

  testWidgets('⑧ export = 서버 레시피 미러 + 이 기기의 이벤트 로그', (tester) async {
    final server = FakeServerRecipeRepository(seed: seedThree);
    await pumpApp(tester, server: server);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );
    // 로컬 이벤트를 만든다 — 사진 업로드 → 인식 완료.
    await uploadAndWait(tester);

    // 클립보드는 헤드리스에서 못 읽는다 — 컨트롤러로 export한다(#22 관용구).
    final exported =
        jsonDecode(await BackupController(storage).exportJson())
            as Map<String, Object?>;

    final recipes = (exported['recipes'] as List).cast<Map<String, Object?>>();
    expect(recipes.map((r) => r['url']), [
      'https://youtu.be/1',
      'https://youtu.be/2',
      'https://youtu.be/3',
    ]);
    expect(recipes.first['id'], isNotNull, reason: '서버 발급 id도 백업에 실린다');

    final types = (exported['events'] as List)
        .cast<Map<String, Object?>>()
        .map((e) => e['type'])
        .toSet();
    expect(types, containsAll(['photoUpload', 'recognitionDone']));
  });

  testWidgets('⑨ 매칭 입력은 미러다 — 서버 레시피가 LLM seam으로 넘어간다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(
          url: 'https://youtu.be/a',
          title: '김치찌개',
          ingredients: ['김치', '돼지고기'],
        ),
      ],
    );
    final gateway = FakeLlmGateway();
    await pumpApp(tester, server: server, gateway: gateway);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    expect(find.text('오늘 할 3개'), findsOneWidget);
    // 매칭에 넘어간 레시피 = 서버에서 내려온 미러 그대로.
    expect(gateway.lastMatchedRecipes!.map((r) => r.url), [
      'https://youtu.be/a',
    ]);
    expect(gateway.lastMatchedRecipes!.single.ingredients, ['김치', '돼지고기']);
  });

  testWidgets('⑩ 하이드레이트 loading 동안 저장 폼이 잠긴다 — 스켈레톤과 함께, 끝나면 풀린다', (
    tester,
  ) async {
    // fetchAll을 Completer로 붙잡아 loading을 고정한다 — latency와 달리 시간에 안 기댄다.
    final server = FakeServerRecipeRepository(seed: seedThree)
      ..fetchAllGate = Completer<void>();
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);

    // 스켈레톤이 서 있는 동안 폼은 입력을 받는 척하지 않는다 — 버릴 입력이기 때문이다.
    expect(find.byKey(const Key('recipe-list-skeleton')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recipe-url-field')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('recipe-submit')))
          .onPressed,
      isNull,
    );

    // 서버가 응답했다 — ready로 풀리면서 리스트가 서고 폼이 열린다.
    server.fetchAllGate!.complete();
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-list-skeleton')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recipe-url-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('recipe-submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('⑪ 하이드레이트 error — 가져오기는 미리보기부터 거절되고 온보딩 폼도 잠긴다', (tester) async {
    final server = FakeServerRecipeRepository(
      failure: const RecipeApiFailure(RecipeApiFailureKind.unavailable),
    );
    await pumpApp(tester, server: server, skipOnboarding: false);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-list-error'))),
    );
    await tester.pumpAndSettle();

    // 스테일 미러 기준 dedup은 성립하지 않는다 — 미리보기부터 받지 않고 서버 호출도 없다.
    final incoming = jsonEncode(
      BackupData(
        recipes: const [
          Recipe(url: 'https://youtu.be/b', title: '계란찜', ingredients: ['계란']),
        ],
        events: const [],
        exportedAt: DateTime.utc(2026, 7, 14),
      ).toJson(),
    );
    final field = find.byKey(const Key('backup-import-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, incoming);
    await tapVisible(tester, find.byKey(const Key('backup-preview')));

    expect(find.byKey(const Key('merge-preview')), findsNothing);
    expect(
      find.text('서버의 레시피 목록과 연결된 뒤 가져올 수 있어요. 잠시 후 다시 시도해주세요.'),
      findsOneWidget,
    );
    expect(server.importBulkCallCount, 0, reason: '거절은 클라이언트에서 끝난다 — 서버 무호출');

    // 메인 탭 온보딩 폼도 같은 이유로 잠긴다 — 버릴 저장 입력을 받는 척하지 않는다.
    await tester.tap(find.text('메인'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-card')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recipe-url-field')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('recipe-submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('⑫ 확정 중 재수화 순단 — 앱은 살아 있고, 재확정 길이 닫혀 중복 등록이 없다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
      ],
    );
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/a'))),
    );

    final incoming = jsonEncode(
      BackupData(
        recipes: const [
          Recipe(url: 'https://youtu.be/b', title: '계란찜', ingredients: ['계란']),
        ],
        events: const [],
        exportedAt: DateTime.utc(2026, 7, 14),
      ).toJson(),
    );
    final field = find.byKey(const Key('backup-import-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, incoming);
    await tapVisible(tester, find.byKey(const Key('backup-preview')));
    expect(find.byKey(const Key('merge-preview')), findsOneWidget);

    // 확정 직전에 재수화만 죽는다 — importBulk는 성공하고 fetchAll이 실패하는 순단.
    server.fetchAllFailure = const RecipeApiFailure(
      RecipeApiFailureKind.unavailable,
    );
    await tapVisible(tester, find.byKey(const Key('backup-confirm')));
    await waitForVisible(
      tester,
      () => _visible(
        find.text('가져오기는 서버에 저장됐어요. 목록을 새로 불러오지 못했으니, 앱을 새로고침하면 반영됩니다.'),
      ),
    );
    await tester.pumpAndSettle();

    // 가져오기 자체는 서버에 저장 완료 — 미러는 재수화 실패라 불변이다(가짜 성공 렌더 금지).
    expect(server.importBulkCallCount, 1);
    expect(server.recipes.map((r) => r.url), [
      'https://youtu.be/a',
      'https://youtu.be/b',
    ]);
    expect((await Storage.open()).readRecipes().map((r) => r.url), [
      'https://youtu.be/a',
    ]);

    // 커밋이 잠겼다 — 확정 버튼 자체가 사라져 같은 배치를 두 번 보낼 길이 없다.
    expect(find.byKey(const Key('merge-preview')), findsNothing);
    expect(find.byKey(const Key('backup-confirm')), findsNothing);
    expect(
      server.importBulkCallCount,
      1,
      reason: '재확정 무경로 — importBulk는 1회로 끝',
    );

    // 순단이어도 가져오기 기록은 남는다 — 재수화 성패와 무관한 계약이다.
    await waitForEvents(
      tester,
      storage,
      (events) => events.any(
        (e) => e.type == AppEventType.backup && e.data['direction'] == 'import',
      ),
    );
  });

  testWidgets('⑬ 하이드레이트 가드 — 빈 서버 목록이 로컬 미러를 덮지 않는다 (#165)', (tester) async {
    // 합류 시나리오 — 파일럿 기기가 서버 빌드로 갈아탄 직후. 로컬 북은 살아 있고 계정은 비어 있다.
    await storage.writeRecipes(seedThree);
    final server = FakeServerRecipeRepository();

    await pumpApp(tester, server: server, skipOnboarding: false);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );
    expect(server.fetchAllCallCount, 1, reason: '부팅 킥 1회');
    // 미러가 살아 있으니 온보딩 카드가 설 자리가 없다 — 사용자에겐 아무 일도 일어나지 않은 화면이다.
    expect(find.byKey(const Key('onboarding-card')), findsNothing);

    await openRecipeBook(tester);
    expect(find.text('저장한 레시피 · 3'), findsOneWidget);
    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/1')),
      findsOneWidget,
    );
    // 반쯤 죽은 상태가 아니다 — 에러 카드도 없고 저장 폼도 열려 있다.
    expect(find.byKey(const Key('recipe-list-error')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recipe-url-field')))
          .enabled,
      isTrue,
    );

    // 가드는 화면 안내를 만들지 않는다(안내는 런북이 한다) — 대신 이벤트 1건을 남긴다.
    final events = await waitForEvents(
      tester,
      storage,
      (events) => events.any((e) => e.type == AppEventType.errorShown),
    );
    final guard = events.where((e) => e.type == AppEventType.errorShown).single;
    expect(guard.data['kind'], 'emptyServerBook');
    expect(guard.data['stage'], 'hydrate');

    // 내보낼 원본이 남아 있다 — 이전 vehicle이 export 파일이기 때문이다.
    final exported =
        jsonDecode(await BackupController(storage).exportJson())
            as Map<String, Object?>;
    expect((exported['recipes'] as List), hasLength(3));
  });

  testWidgets('⑭ 가드 뒤 이전 — 자기 export를 가져오면 미러가 서버로 올라간다 (#165)', (
    tester,
  ) async {
    await storage.writeRecipes(seedThree);
    final server = FakeServerRecipeRepository();
    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-tile-https://youtu.be/1'))),
    );

    // 런북 합류 절차 ④ — 프록시 빌드에서 뽑아둔 백업 파일이 곧 이 파일이다.
    final mine = await BackupController(storage).exportJson();
    final field = find.byKey(const Key('backup-import-field'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, mine);
    await tapVisible(tester, find.byKey(const Key('backup-preview')));

    // 미러 기준 dedup이라 "새로 들어올 것"은 0인데, 올릴 것은 3개다 — 화면이 그걸 말한다.
    expect(find.byKey(const Key('merge-preview')), findsOneWidget);
    expect(find.text('아직 서버에 없는 레시피 3개도 함께 올립니다.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('backup-confirm')))
          .onPressed,
      isNotNull,
      reason: '확정이 잠겨 있으면 이전이 영원히 실행되지 않는다',
    );

    await tapVisible(tester, find.byKey(const Key('backup-confirm')));
    await waitForEvents(
      tester,
      storage,
      (events) => events.any(
        (e) => e.type == AppEventType.backup && e.data['direction'] == 'import',
      ),
    );
    await tester.pumpAndSettle();

    expect(server.importBulkCallCount, 1);
    expect(server.recipes.map((r) => r.url), [
      'https://youtu.be/1',
      'https://youtu.be/2',
      'https://youtu.be/3',
    ]);
    // 재수화된 미러 = 서버 정본(발급 id 포함) — 이제 다음 부팅이 지울 것이 없다.
    final mirror = (await Storage.open()).readRecipes();
    expect(mirror.map((r) => r.url), [
      'https://youtu.be/1',
      'https://youtu.be/2',
      'https://youtu.be/3',
    ]);
    expect(mirror.map((r) => r.id), everyElement(isNotNull));
  });

  testWidgets('⑮ 가드 뒤에도 코어 루프가 산다 — 지켜낸 미러가 매칭 입력이다 (#165)', (tester) async {
    await storage.writeRecipes(const [
      Recipe(
        url: 'https://youtu.be/a',
        title: '김치찌개',
        ingredients: ['김치', '돼지고기'],
      ),
    ]);
    final server = FakeServerRecipeRepository();
    final gateway = FakeLlmGateway();
    await pumpApp(tester, server: server, gateway: gateway);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );

    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);

    // 서버가 비어 있어도 제안이 나온다 — 매칭은 서버 북이 아니라 미러를 입력으로 받는다.
    expect(find.text('오늘 할 3개'), findsOneWidget);
    expect(gateway.lastMatchedRecipes!.map((r) => r.url), [
      'https://youtu.be/a',
    ]);
    expect(gateway.lastMatchedRecipes!.single.ingredients, ['김치', '돼지고기']);
  });

  // ⑯·⑰만 서버 레시피 북 자리에 **실 구현 + 가짜 전송**을 꽂는다(#168).
  // 등록·재등록은 전송 초크에 살아서 경계 페이크로는 도달할 수 없다 — 페이크 repository는
  // sendWithDeviceSession을 통째로 건너뛴다. 대신 이 둘이 등록 → 하이드레이트 가드 → 미러
  // 보존 → 코어 루프의 사슬을 실코드로 관통시킨다.

  /// 서버 RecipeResponse 모양 — 실 repository가 이걸 파싱한다.
  Map<String, Object?> wireRecipe(Recipe r, String id) => {
    'id': id,
    'url': r.url,
    'title': r.title,
    'ingredients': r.ingredients,
    'created_at': '2026-07-29T00:00:00Z',
  };

  http.Response jsonOk(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  testWidgets('⑯ 첫 실행에 로그인 화면이 없다 — 등록이 실 보안 저장소를 관통한다 (#168)', (tester) async {
    // 이 케이스만 기기 세션 경계도 **실 구현**이다. 목적이 둘이라서다 — ① 로그인 화면 0을 찍고
    // ② **등록 토큰이 Web 타깃의 보안 저장소에 실제로 써지고 다시 읽히는지**를 찍는다. 티켓이
    // 착수 전에 확인하라고 명시한 리스크가 후자이고, 페이크를 꽂으면 그 경로가 안 돈다.
    // (삭제만으로는 부족하다 — flutter_secure_storage_web의 delete는 removeItem 한 줄이라
    //  암복호를 안 탄다. 쓰기·읽기가 WebCrypto를 타는 쪽이다.)
    final devicePosts = <String?>[];
    final sentAuth = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/device') {
        devicePosts.add(request.headers['authorization']);
        return jsonOk({
          'token': 'sess-issued',
          'expires_at': '2026-08-28T00:00:00Z',
          'account': {
            'id': '5b9f1f1e-0000-4000-8000-000000000001',
            'iss': 'device',
            'sub': '9b1c0a5e-0000-4000-8000-000000000002',
            'created_at': '2026-07-29T00:00:00Z',
          },
        });
      }
      sentAuth.add(request.headers['authorization']);
      return jsonOk([
        for (final (i, r) in seedThree.indexed) wireRecipe(r, 'r$i'),
      ]);
    });
    // 갓 설치한 기기 — setUp의 clear()가 토큰까지 지웠다.
    expect(await storage.readDeviceToken(), isNull);

    final session = ApiV1DeviceSession(
      baseUrl: 'https://api.test',
      registerKey: 'e2e-register-key',
      storage: storage,
      client: client,
    );
    final server = ServerRecipeRepository(
      baseUrl: 'https://api.test',
      session: session,
      client: client,
    );

    await pumpApp(tester, server: server, skipOnboarding: false);

    // 코어 루프 진입점이 그냥 뜬다 — 앞을 막는 게이트가 없다.
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );

    // 등록이 실제로 일어났고, 등록 키가 실렸고, 발급 토큰이 다음 요청에 붙었다.
    expect(devicePosts, ['Bearer e2e-register-key']);
    expect(sentAuth, ['Bearer sess-issued']);

    // ★ 웹 타깃 보안 저장소 왕복 — 쓰기가 살아 있고, 새로 연 스토리지가 그 값을 읽는다.
    expect(await storage.readDeviceToken(), 'sess-issued');
    expect(await (await Storage.open()).readDeviceToken(), 'sess-issued');

    // 등록이 일어났다는 사실이 화면에 드러나지 않는다. 로그인·계정 표면이 0이라는 것이
    // ADR-0012가 사용자에게 약속한 전부다.
    for (final word in ['로그인', '계정', '세션', '등록', '가입', '로그아웃']) {
      expect(
        find.textContaining(word),
        findsNothing,
        reason: '"$word"가 화면에 보인다 — 익명 등록은 사용자에게 보이지 않아야 한다',
      );
    }

    // 서버 목록이 미러로 내려왔다 = 토큰이 실제로 통했다는 뜻이다.
    await openRecipeBook(tester);
    expect(find.text('저장한 레시피 · 3'), findsOneWidget);
  });

  testWidgets('⑰ 401 → 재등록 — 로컬 레시피가 살아남고 세션 만료 문구가 없다 (#168)', (tester) async {
    // 30일+ 비활성 뒤의 부팅. 미러엔 레시피가 있고 서버 세션은 죽어 있다.
    // 여긴 기기 세션 경계를 **페이크**로 꽂는다(스펙이 예고한 세 번째 E2E 페이크) — 재등록이
    // 몇 번 일어났는지가 이 케이스의 관측 대상이고, 실 등록 왕복은 ⑯이 이미 관통시켰다.
    await storage.writeRecipes(seedThree);
    final session = FakeDeviceSession(storedToken: 'tok-dead');
    final sentAuth = <String?>[];
    final server = ServerRecipeRepository(
      baseUrl: 'https://api.test',
      session: session,
      client: MockClient((request) async {
        sentAuth.add(request.headers['authorization']);
        // 죽은 토큰엔 401, 재등록해 온 토큰엔 **빈 새 계정**의 목록.
        if (request.headers['authorization'] == 'Bearer tok-dead') {
          return http.Response(jsonEncode({'detail': 'unauthorized'}), 401);
        }
        return jsonOk(const <Object>[]);
      }),
    );
    final gateway = FakeLlmGateway();

    await pumpApp(tester, server: server, gateway: gateway);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('upload-photo'))),
    );

    expect(session.registerCount, 1, reason: '재등록이 정확히 한 번');
    expect(sentAuth, ['Bearer tok-dead', 'Bearer ${session.currentToken}']);

    // 세션 만료를 사용자에게 설명하지 않는다 — 로그인이 없는 사람에게 성립하지 않는 개념이다.
    for (final word in ['만료', '로그인', '세션']) {
      expect(
        find.textContaining(word),
        findsNothing,
        reason: '"$word"가 메인 화면에 보인다 — 재등록은 조용해야 한다',
      );
    }

    // 루프가 이어진다 — 지켜낸 미러가 그대로 매칭 입력이다.
    await uploadAndWait(tester);
    await tapRequestSuggestions(tester);
    expect(find.text('오늘 할 3개'), findsOneWidget);
    expect(gateway.lastMatchedRecipes!.map((r) => r.url), [
      'https://youtu.be/1',
      'https://youtu.be/2',
      'https://youtu.be/3',
    ]);

    // 새 계정은 비어 있지만 하이드레이트 가드가 미러를 지킨다(#165) — 목록이 그대로 산다.
    await openRecipeBook(tester);
    expect(find.text('저장한 레시피 · 3'), findsOneWidget);
    expect(
      find.byKey(const Key('recipe-tile-https://youtu.be/1')),
      findsOneWidget,
    );
    // 반쯤 죽은 상태가 아니다 — 인라인 에러 카드도 없다.
    expect(find.byKey(const Key('recipe-list-error')), findsNothing);
    for (final word in ['만료', '로그인', '세션']) {
      expect(
        find.textContaining(word),
        findsNothing,
        reason: '"$word"가 레시피 북에 보인다 — 재등록은 조용해야 한다',
      );
    }
  });

  testWidgets('⑱ 인프라 502 — 추출 실패로 오분류되지 않고 신고 경로가 열린다 (#127)', (tester) async {
    // Cloud Run bad gateway가 전 라우트에 502를 낸다. 실 경계를 태워야 하는 이유 —
    // 이 케이스의 질문은 "상태 코드로부터 무엇이 화면에 뜨는가"이고, 경계 페이크에 kind를
    // 손으로 꽂으면 그 질문을 건너뛴다(#166이 남긴 교훈).
    await storage.writeRecipes(seedThree);
    final session = FakeDeviceSession(storedToken: 'tok-live');
    final server = ServerRecipeRepository(
      baseUrl: 'https://api.test',
      session: session,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'bad gateway'}), 502),
      ),
    );

    await pumpApp(tester, server: server);
    await openRecipeBook(tester);
    await waitForVisible(
      tester,
      () => _visible(find.byKey(const Key('recipe-list-error'))),
    );
    await tester.pumpAndSettle();

    // 502를 세션 문제로 읽지 않는다 — 재등록도 돌지 않았다.
    expect(session.registerCount, 0);
    expect(find.text('레시피 북을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('접속 정보가 유효하지 않아요.'), findsNothing);

    // ★ 서버 장애를 사용자가 넣은 URL 탓으로 돌리지 않는다.
    expect(
      find.textContaining('재료를 알아내지 못해'),
      findsNothing,
      reason: '인프라 502가 추출 실패로 오분류되면 사용자는 자기 레시피를 의심한다',
    );

    // ★ 파운더가 이 장애를 알 수 있는 유일한 경로가 열려 있다(스펙 #161 §G).
    expect(find.byKey(const Key('recipe-list-report-hint')), findsOneWidget);
    expect(find.textContaining('카톡으로 알려주세요'), findsOneWidget);

    // 서버가 살아나면 그냥 이어진다 — 502가 막다른 상태를 만들지 않는다(G1 #8).
    expect(find.byKey(const Key('recipe-list-error-retry')), findsOneWidget);
  });
}

/// test/support의 FakeServerRecipeRepository와 동형 사본.
///
/// web 타깃은 엔트리포인트 디렉토리(integration_test/)가 컴파일 루트(org-dartlang-app:/)라
/// `../test/`를 import할 수 없다 — core_loop_test가 fixtures를 인라인한 것과 같은 제약이다.
class FakeServerRecipeRepository implements ServerRecipeRepository {
  FakeServerRecipeRepository({
    List<Recipe> seed = const [],
    this.latency = Duration.zero,
    this.failure,
  }) {
    recipes.addAll(seed.map(_ensureId));
  }

  /// 서버에 저장된 항목 — 삽입순. 테스트가 직접 들여다보거나 조작해도 된다.
  final List<Recipe> recipes = [];

  /// 응답 전 대기 — 로딩 상태를 테스트하려면 여기를 늘린다.
  final Duration latency;

  /// null이 아니면 모든 호출이 이 실패로 끝난다 — 도중에 끄면 성공이 재개된다.
  RecipeApiFailure? failure;

  /// null이 아니면 fetchAll만 이 실패로 끝난다 — importBulk 성공 뒤 재수화 순단을 재현한다(#121 수리).
  RecipeApiFailure? fetchAllFailure;

  /// null이 아니면 fetchAll이 complete될 때까지 응답을 멈춘다 — 하이드레이트 loading을 고정한다(E2E ⑩).
  Completer<void>? fetchAllGate;

  int fetchAllCallCount = 0;
  int createCallCount = 0;
  int patchCallCount = 0;
  int deleteCallCount = 0;
  int importBulkCallCount = 0;
  List<Recipe>? lastImportBulk;

  /// 서버 create가 저장 시 1회 추출하는 것을 흉내 낸다 — 제목 → 재료(FakeLlmGateway.extractions와 동일).
  final Map<String, List<String>> extractions = {
    '김치찌개': ['김치', '돼지고기', '두부', '대파', '고춧가루'],
    '애호박볶음': ['애호박', '대파', '소금', '식용유'],
    '계란찜': ['계란', '대파', '새우젓'],
  };

  static const _fallbackExtraction = ['소금', '식용유'];

  int _idSeq = 0;

  @override
  Future<List<Recipe>> fetchAll() async {
    fetchAllCallCount++;
    final gate = fetchAllGate;
    if (gate != null) await gate.future;
    await _gate();
    final fail = fetchAllFailure;
    if (fail != null) throw fail;
    return List.of(recipes);
  }

  @override
  Future<Recipe> create({required String url, required String title}) async {
    createCallCount++;
    await _gate();
    final recipe = Recipe(
      id: _newId(),
      url: url,
      title: title,
      ingredients: extractions[title] ?? _fallbackExtraction,
    );
    recipes.add(recipe);
    return recipe;
  }

  @override
  Future<Recipe> patchIngredients({
    required String id,
    required List<String> ingredients,
  }) async {
    patchCallCount++;
    await _gate();
    final index = recipes.indexWhere((r) => r.id == id);
    if (index < 0) throw const RecipeApiFailure(RecipeApiFailureKind.notFound);
    final updated = recipes[index].copyWith(ingredients: ingredients);
    recipes[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCallCount++;
    await _gate();
    final index = recipes.indexWhere((r) => r.id == id);
    if (index < 0) throw const RecipeApiFailure(RecipeApiFailureKind.notFound);
    recipes.removeAt(index);
  }

  @override
  Future<List<Recipe>> importBulk(List<Recipe> recipes) async {
    importBulkCallCount++;
    lastImportBulk = recipes;
    await _gate();
    // 서버가 id를 발급한다 — 들어온 id는 버리고 새로 단다(실서버 계약과 동일).
    final saved = [
      for (final r in recipes)
        Recipe(
          id: _newId(),
          url: r.url,
          title: r.title,
          ingredients: r.ingredients,
        ),
    ];
    this.recipes.addAll(saved);
    return saved;
  }

  Future<void> _gate() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final fail = failure;
    if (fail != null) throw fail;
  }

  String _newId() => 'srv-${++_idSeq}';

  Recipe _ensureId(Recipe r) => r.id != null
      ? r
      : Recipe(
          id: _newId(),
          url: r.url,
          title: r.title,
          ingredients: r.ingredients,
        );
}
