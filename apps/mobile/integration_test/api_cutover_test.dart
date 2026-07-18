// 컷오버(#121) E2E — 서버 레시피 북 미러가 브라우저에서 보이는 것과 export에 남는 것을 검증한다.
// 실행: scripts/e2e.sh integration_test/api_cutover_test.dart  (chromedriver + flutter drive, core_loop와 동형)
//
// 서버는 FakeServerRecipeRepository, LLM은 FakeLlmGateway — 결정적 페이크 2개를 seam에 주입한다.
import 'dart:async';
import 'dart:convert';

import 'package:cookmark/app.dart';
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
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeServerRecipeRepository server,
    FakeLlmGateway? gateway,
    bool skipOnboarding = true,
  }) async {
    final llm = gateway ?? FakeLlmGateway();
    final controller = MainController(
      llm,
      storage,
      userAgent: () => 'Mozilla/5.0 Chrome/120.0.0.0 Mobile Safari/537.36',
      debugEnabled: () => false,
    );
    final book = RecipeBookController(llm, storage, server: server);
    // 부팅 킥 — 기다리지 않는다. 지연·실패는 화면 상태(스켈레톤·에러 카드)로 가시화된다.
    unawaited(book.hydrate());
    await tester.pumpWidget(
      CookmarkApp(
        controller: controller,
        recipeBookController: book,
        backupController: BackupController(storage, server: server),
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
    await _gate();
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
