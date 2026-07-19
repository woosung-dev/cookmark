// 레시피 북 서버 모드(#121) — hydrate·미러 계약·add/재추출/삭제의 서버 분기.
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_server_recipe_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
  });

  RecipeBookController bookWith(
    FakeServerRecipeRepository server, {
    FakeLlmGateway? gateway,
  }) => RecipeBookController(
    gateway ?? FakeLlmGateway(),
    storage,
    server: server,
  );

  List<AppEvent> bookEvents() => storage
      .readEvents()
      .where((e) => e.type == AppEventType.recipeBookChanged)
      .toList();

  List<AppEvent> errorEvents() => storage
      .readEvents()
      .where((e) => e.type == AppEventType.errorShown)
      .toList();

  const seedRecipe = Recipe(
    url: 'https://youtu.be/seed',
    title: '계란찜',
    ingredients: ['계란'],
  );

  group('hydrate', () {
    test('loading에서 시작해 서버 목록을 미러에 쓰고 ready가 된다', () async {
      final server = FakeServerRecipeRepository(
        seed: const [seedRecipe],
        latency: const Duration(milliseconds: 50),
      );
      final book = bookWith(server);
      expect(book.syncState, RecipeSyncState.loading, reason: '서버 모드 초기 상태');

      final pending = book.hydrate();
      expect(book.syncState, RecipeSyncState.loading);
      await pending;

      expect(book.syncState, RecipeSyncState.ready);
      // 미러 계약 — recipes getter는 storage를 읽고, storage엔 서버 응답이 그대로 있다.
      expect(book.recipes, storage.readRecipes());
      expect(storage.readRecipes().single.url, seedRecipe.url);
      expect(storage.readRecipes().single.id, isNotNull, reason: '서버 발급 id 보존');
    });

    test('실패하면 error + syncFailure가 남는다 — 미러는 쓰지 않는다', () async {
      final server = FakeServerRecipeRepository(
        failure: const RecipeApiFailure(RecipeApiFailureKind.unauthorized),
      );
      final book = bookWith(server);
      await book.hydrate();

      expect(book.syncState, RecipeSyncState.error);
      expect(book.syncFailure, RecipeApiFailureKind.unauthorized);
      expect(storage.readRecipes(), isEmpty);
    });

    test('실패 후 다시 시도해 성공하면 ready로 전환된다', () async {
      final server = FakeServerRecipeRepository(
        seed: const [seedRecipe],
        failure: const RecipeApiFailure(RecipeApiFailureKind.unavailable),
      );
      final book = bookWith(server);
      await book.hydrate();
      expect(book.syncState, RecipeSyncState.error, reason: '전제');

      // 서버가 살아났다 — 에러 카드의 "다시 시도"가 이 경로다.
      server.failure = null;
      await book.hydrate();

      expect(book.syncState, RecipeSyncState.ready);
      expect(book.syncFailure, isNull);
      expect(book.recipes, hasLength(1));
    });
  });

  group('저장 (서버 분기)', () {
    test('성공하면 서버 응답이 미러에 붙고 이벤트에 usage가 없다', () async {
      final server = FakeServerRecipeRepository();
      final book = bookWith(server);
      await book.hydrate();

      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(server.createCallCount, 1);
      final saved = book.recipes.single;
      expect(saved.ingredients, contains('돼지고기'), reason: '서버 추출 재료');
      expect(saved.id, isNotNull, reason: '서버 발급 id가 미러에 보존된다');

      final event = bookEvents().single;
      expect(event.data['action'], 'add');
      expect(event.data['ingredientCount'], 5);
      // 추출은 서버 안에서 돌았다 — 클라이언트가 아는 usage가 없다.
      expect(event.data.containsKey('costUsd'), isFalse);
      expect(event.data.containsKey('model'), isFalse);
    });

    test('실패(extractionFailed)하면 미러 무변화 + 실패 카드 상태 + errorShown', () async {
      final server = FakeServerRecipeRepository();
      final book = bookWith(server);
      await book.hydrate();
      server.failure = const RecipeApiFailure(
        RecipeApiFailureKind.extractionFailed,
      );

      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(book.recipes, isEmpty, reason: '502=미저장이 서버 정책이다');
      expect(book.addFailure, RecipeApiFailureKind.extractionFailed);
      expect(book.failedAdd, (url: 'https://youtu.be/abc', title: '김치찌개'));
      expect(bookEvents(), isEmpty, reason: '저장 안 됐으니 add 이벤트도 없다');

      final error = errorEvents().single;
      expect(error.data['kind'], 'extractionFailed');
      expect(error.data['stage'], 'extraction');
    });

    test('failedAdd로 재시도해 성공하면 실패 상태가 걷힌다', () async {
      final server = FakeServerRecipeRepository();
      final book = bookWith(server);
      await book.hydrate();
      server.failure = const RecipeApiFailure(
        RecipeApiFailureKind.extractionFailed,
      );
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      expect(book.failedAdd, isNotNull, reason: '전제');

      // 서버가 살아났다 — 실패 카드의 "다시 시도"가 이 경로다(폼은 이미 비워졌다).
      server.failure = null;
      final failed = book.failedAdd!;
      await book.add(url: failed.url, title: failed.title);

      expect(book.recipes.single.title, '김치찌개');
      expect(book.addFailure, isNull);
      expect(book.failedAdd, isNull);
      expect(bookEvents().single.data['action'], 'add');
    });

    test('저장 중 더블탭은 서버까지 가지 않는다 — create는 1회다', () async {
      final server = FakeServerRecipeRepository(
        latency: const Duration(milliseconds: 50),
      );
      final book = bookWith(server);
      await book.hydrate();

      final first = book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      final second = book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      await Future.wait([first, second]);

      expect(server.createCallCount, 1);
      expect(book.recipes, hasLength(1));
    });

    test('같은 URL은 서버까지 가지 않는다 — dedup 가드는 분기 앞 공통', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();

      await book.add(url: seedRecipe.url, title: '다른 이름');

      expect(server.createCallCount, 0);
      expect(book.recipes, hasLength(1));
    });

    test('syncState error에서 add는 실패 카드로 표면화된다 — 무음 폐기 금지', () async {
      final server = FakeServerRecipeRepository(
        failure: const RecipeApiFailure(RecipeApiFailureKind.unauthorized),
      );
      final book = bookWith(server);
      await book.hydrate();
      expect(book.syncState, RecipeSyncState.error, reason: '전제');

      // 서버가 살아나도 재수화 전이면 미러가 정확하지 않다 — 저장은 받지 않되 표면화한다.
      server.failure = null;
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(server.createCallCount, 0, reason: '서버 호출 자체가 없다');
      expect(book.recipes, isEmpty, reason: '미러 무변화');
      expect(
        book.addFailure,
        RecipeApiFailureKind.unauthorized,
        reason: '하이드레이트 실패 이유 그대로',
      );
      expect(book.failedAdd, (url: 'https://youtu.be/abc', title: '김치찌개'));
      expect(storage.readEvents(), isEmpty, reason: '서버 호출이 없었으니 이벤트도 없다');
    });

    test('syncState loading에서 add도 실패 카드로 표면화된다', () async {
      final server = FakeServerRecipeRepository();
      final book = bookWith(server);
      expect(book.syncState, RecipeSyncState.loading, reason: '전제 — 하이드레이트 전');

      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(server.createCallCount, 0);
      expect(book.recipes, isEmpty);
      expect(
        book.addFailure,
        RecipeApiFailureKind.unavailable,
        reason: 'syncFailure 없으면 unavailable 폴백',
      );
      expect(book.failedAdd, (url: 'https://youtu.be/abc', title: '김치찌개'));
      expect(storage.readEvents(), isEmpty);
    });
  });

  group('재추출 (서버 분기)', () {
    test('LLM 추출 1회 + PATCH 1회 — 응답으로 미러가 갱신되고 usage가 남는다', () async {
      const empty = Recipe(
        url: 'https://youtu.be/abc',
        title: '김치찌개',
        ingredients: [],
      );
      final server = FakeServerRecipeRepository(seed: const [empty]);
      final gateway = FakeLlmGateway();
      final book = bookWith(server, gateway: gateway);
      await book.hydrate();

      await book.retryExtraction('https://youtu.be/abc');

      expect(gateway.extractCallCount, 1, reason: '추출은 LLM seam으로 직접');
      expect(
        gateway.lastExtractUrl,
        'https://youtu.be/abc',
        reason: '재추출은 url도 넘긴다 — 서버 경계가 URL 사다리를 탈 수 있게(#123)',
      );
      expect(server.patchCallCount, 1);
      expect(book.recipes.single.ingredients, contains('돼지고기'));
      expect(
        server.recipes.single.ingredients,
        contains('돼지고기'),
        reason: '서버도 갱신됐다',
      );

      final event = bookEvents().single;
      expect(event.data['action'], 'reextract');
      expect(event.data['costUsd'], isNotNull, reason: 'LLM을 불렀으니 원가가 남는다');
    });

    test('PATCH가 죽으면 미러는 갱신되지 않고 errorShown만 남는다', () async {
      const empty = Recipe(
        url: 'https://youtu.be/abc',
        title: '김치찌개',
        ingredients: [],
      );
      final server = FakeServerRecipeRepository(seed: const [empty]);
      final book = bookWith(server);
      await book.hydrate();
      server.failure = const RecipeApiFailure(RecipeApiFailureKind.unavailable);

      await book.retryExtraction('https://youtu.be/abc');

      expect(book.recipes.single.ingredients, isEmpty, reason: '미러 미갱신');
      expect(bookEvents(), isEmpty);
      expect(errorEvents().single.data['kind'], 'unavailable');
    });
  });

  group('삭제 (서버 분기)', () {
    test('DELETE 후 미러에서 빠지고 이벤트가 남는다', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();

      await book.remove(seedRecipe.url);

      expect(server.deleteCallCount, 1);
      expect(server.recipes, isEmpty);
      expect(book.recipes, isEmpty);
      expect(bookEvents().single.data['action'], 'remove');
    });

    test('서버에 이미 없으면(404) 성공 취급 — 부재가 곧 목표 상태다', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();
      server.recipes.clear(); // 서버에선 이미 사라졌다.

      await book.remove(seedRecipe.url);

      expect(book.recipes, isEmpty, reason: '미러도 지운다');
      expect(bookEvents().single.data['action'], 'remove');
      expect(errorEvents(), isEmpty);
    });

    test('그 외 실패면 미러를 유지한다 — 화면에서만 지우면 하이드레이트에 되살아난다', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();
      server.failure = const RecipeApiFailure(RecipeApiFailureKind.unavailable);

      await book.remove(seedRecipe.url);

      expect(book.recipes, hasLength(1));
      expect(bookEvents(), isEmpty);
      expect(errorEvents().single.data['stage'], 'remove');
    });

    test('실패(비-404)는 removeFailure로 표면화되고 재시도 성공 시 걷힌다', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();
      server.failure = const RecipeApiFailure(RecipeApiFailureKind.unavailable);

      await book.remove(seedRecipe.url);

      expect(book.removeFailure, RecipeApiFailureKind.unavailable);
      expect(book.recipes, hasLength(1), reason: '미러 유지 — 타일이 남는 이유가 보인다');

      // 서버가 살아났다 — 다시 X를 누르면 실패 상태가 걷히고 지워진다.
      server.failure = null;
      await book.remove(seedRecipe.url);

      expect(book.removeFailure, isNull);
      expect(book.recipes, isEmpty);
    });

    test('서버 모드 삭제는 실행취소 창을 열지 않는다 — undo는 재-POST 재추출이라 범위 밖', () async {
      final server = FakeServerRecipeRepository(seed: const [seedRecipe]);
      final book = bookWith(server);
      await book.hydrate();

      await book.remove(seedRecipe.url);

      expect(book.pendingRemove, isNull);
    });
  });
}
