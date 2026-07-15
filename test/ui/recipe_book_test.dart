// 레시피 북 — URL 저장·삭제, 제목 기반 재료 추출, 미인식 칩(#17).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:flutter_test/flutter_test.dart';
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

  RecipeBookController bookWith(FakeLlmGateway gateway) =>
      RecipeBookController(gateway, storage, now: DateTime.now);

  List<AppEvent> bookEvents() => storage
      .readEvents()
      .where((e) => e.type == AppEventType.recipeBookChanged)
      .toList();

  group('저장', () {
    test('URL과 제목을 저장하고 제목에서 재료를 추론한다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      final saved = book.recipes.single;
      expect(saved.url, 'https://youtu.be/abc');
      expect(saved.title, '김치찌개');
      expect(saved.ingredients, contains('돼지고기'));
    });

    test('추출은 제목만 받는다 — 본문·자막을 긁지 않는다', () async {
      final gateway = _RecordingGateway();
      final book = RecipeBookController(gateway, storage);
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(gateway.extractedTitles, ['김치찌개']);
    });

    test('같은 URL은 두 번 담기지 않는다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      await book.add(url: 'https://youtu.be/abc', title: '다른 이름');

      expect(book.recipes, hasLength(1));
      expect(book.recipes.single.title, '김치찌개');
    });

    test('URL이나 제목이 비면 저장하지 않는다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: '  ', title: '김치찌개');
      await book.add(url: 'https://youtu.be/abc', title: '   ');

      expect(book.recipes, isEmpty);
    });

    test('앞뒤 공백은 다듬는다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: '  https://youtu.be/abc  ', title: '  김치찌개  ');

      expect(book.recipes.single.url, 'https://youtu.be/abc');
      expect(book.recipes.single.title, '김치찌개');
    });

    test('저장이 이벤트로 남는다 — 토큰·원가까지 (#17 AC)', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      final event = bookEvents().single;
      expect(event.data['action'], 'add');
      expect(event.data['url'], 'https://youtu.be/abc');
      expect(event.data['title'], '김치찌개');
      expect(event.data['ingredientCount'], 5);
      // 추출도 LLM 호출이므로 원가가 붙는다(T1 #6이 ingest를 원가에 넣은 이유).
      expect(event.data['costUsd'], 0.00044);
      expect(event.data['model'], 'fake-extractor');
      expect(event.data['imageTokens'], 0, reason: '텍스트 온리 호출이다');
    });

    test('저장 중에는 saving이 참이다 — 폼이 잠긴다', () async {
      final book = bookWith(
        FakeLlmGateway(latency: const Duration(milliseconds: 100)),
      );
      final pending = book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(book.saving, isTrue);
      await pending;
      expect(book.saving, isFalse);
    });
  });

  group('추출 실패', () {
    test('추출이 죽어도 레시피는 저장된다 — 재료 없는 레시피가 없는 레시피보다 낫다', () async {
      final book = bookWith(
        FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.error)),
      );
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(book.recipes, hasLength(1));
      expect(book.recipes.single.ingredients, isEmpty);
      expect(book.failure, LlmFailureKind.error);
    });

    test('추출 실패가 오류 이벤트로 남는다 — 단계는 extraction', () async {
      final book = bookWith(
        FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.error)),
      );
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');

      final error = storage.readEvents().firstWhere(
        (e) => e.type == AppEventType.errorShown,
      );
      expect(error.data['stage'], 'extraction');
      expect(error.data['kind'], 'error');
    });
  });

  group('삭제', () {
    test('URL로 지운다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      await book.remove('https://youtu.be/abc');

      expect(book.recipes, isEmpty);
    });

    test('삭제가 이벤트로 남는다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.add(url: 'https://youtu.be/abc', title: '김치찌개');
      await book.remove('https://youtu.be/abc');

      expect(bookEvents().map((e) => e.data['action']), ['add', 'remove']);
    });

    test('없는 URL을 지우면 아무 일도 없다', () async {
      final book = bookWith(FakeLlmGateway());
      await book.remove('https://youtu.be/nope');
      expect(bookEvents(), isEmpty);
    });
  });

  group('온보딩·넛지', () {
    test('레시피 북이 비면 온보딩 상태다', () {
      expect(MainController(FakeLlmGateway(), storage).showsOnboarding, isTrue);
    });

    test('건너뛰면 온보딩이 사라진다 — 빈 레시피 북으로도 루프는 돈다', () {
      final main = MainController(FakeLlmGateway(), storage)..skipOnboarding();
      expect(main.showsOnboarding, isFalse);
    });

    test('레시피가 하나라도 있으면 온보딩이 사라진다', () async {
      final gateway = FakeLlmGateway();
      await bookWith(gateway).add(url: 'https://youtu.be/abc', title: '김치찌개');

      expect(MainController(gateway, storage).showsOnboarding, isFalse);
    });

    test('3개 미만이면 넛지가 상시로 남는다', () async {
      final gateway = FakeLlmGateway();
      final book = bookWith(gateway);
      await book.add(url: 'https://youtu.be/1', title: '김치찌개');
      await book.add(url: 'https://youtu.be/2', title: '계란찜');

      final main = MainController(gateway, storage);
      expect(main.recipeCount, 2);
      expect(main.showsRecipeNudge, isTrue);
    });

    test('3개를 채우면 넛지가 사라진다', () async {
      final gateway = FakeLlmGateway();
      final book = bookWith(gateway);
      for (final (i, title) in ['김치찌개', '계란찜', '애호박볶음'].indexed) {
        await book.add(url: 'https://youtu.be/$i', title: title);
      }

      expect(MainController(gateway, storage).showsRecipeNudge, isFalse);
    });
  });

  group('미인식 칩 (질문 2 검증 확률을 올리는 장치)', () {
    test('레시피 북 재료 중 체크리스트에 없는 것만 칩이 된다', () async {
      final gateway = FakeLlmGateway();
      await bookWith(gateway).add(url: 'https://youtu.be/abc', title: '김치찌개');

      final main = MainController(gateway, storage);
      await main.uploadPhoto(fridgePhoto());

      // 김치찌개 재료 = 김치·돼지고기·두부·대파·고춧가루.
      // 두부·대파는 인식됐으니 빠지고 나머지가 칩이 된다.
      expect(main.unrecognizedFromRecipeBook, ['김치', '돼지고기', '고춧가루']);
    });

    test('칩을 탭해 추가하면 경로 recipeBookChip으로 계측된다 (#17 AC)', () async {
      final gateway = FakeLlmGateway();
      await bookWith(gateway).add(url: 'https://youtu.be/abc', title: '김치찌개');

      final main = MainController(gateway, storage);
      await main.uploadPhoto(fridgePhoto());
      await main.addIngredient('김치', path: EditPath.recipeBookChip);

      final edit = storage.readEvents().lastWhere(
        (e) => e.type == AppEventType.checklistEdit,
      );
      expect(edit.data, {
        'kind': 'add',
        'path': 'recipeBookChip',
        'name': '김치',
      });
      expect(main.unrecognizedFromRecipeBook, isNot(contains('김치')));
    });

    test('레시피 북이 비면 칩도 없다', () async {
      final main = MainController(FakeLlmGateway(), storage);
      await main.uploadPhoto(fridgePhoto());
      expect(main.unrecognizedFromRecipeBook, isEmpty);
    });

    test('여러 레시피가 같은 재료를 써도 칩은 하나다', () async {
      final gateway = FakeLlmGateway();
      final book = bookWith(gateway);
      await book.add(url: 'https://youtu.be/1', title: '김치찌개');
      await book.add(url: 'https://youtu.be/2', title: '계란찜');

      final main = MainController(gateway, storage);
      await main.uploadPhoto(fridgePhoto());

      // 두 레시피 모두 대파를 쓰지만 대파는 이미 인식돼 빠진다. 중복은 없어야 한다.
      final chips = main.unrecognizedFromRecipeBook;
      expect(chips.toSet(), hasLength(chips.length));
    });

    test('재료를 못 뽑은 레시피는 칩을 만들지 않는다', () async {
      final gateway = FakeLlmGateway(
        failure: const LlmFailure(LlmFailureKind.error),
      );
      await bookWith(gateway).add(url: 'https://youtu.be/abc', title: '김치찌개');

      final main = MainController(FakeLlmGateway(), storage);
      await main.uploadPhoto(fridgePhoto());
      expect(main.unrecognizedFromRecipeBook, isEmpty);
    });
  });
}

/// 무엇이 추출 경계로 넘어갔는지 기록한다 — "제목만 보낸다"를 검증할 유일한 방법.
class _RecordingGateway extends FakeLlmGateway {
  final extractedTitles = <String>[];

  @override
  Future<ExtractionResult> extractIngredients(String title) {
    extractedTitles.add(title);
    return super.extractIngredients(title);
  }
}
