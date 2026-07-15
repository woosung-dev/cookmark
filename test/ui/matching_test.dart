// 매칭 — 확정 재료가 무엇으로 넘어가고, 무엇이 로그에 남는가(#18).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/suggestion.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fixtures.dart';
import '../support/wait_for.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
  });

  Future<MainController> loadedWith(FakeLlmGateway gateway) async {
    final controller = MainController(gateway, storage, now: DateTime.now);
    await controller.uploadPhoto(fridgePhoto());
    return controller;
  }

  AppEvent eventOf(AppEventType type) =>
      storage.readEvents().lastWhere((e) => e.type == type);

  group('매칭에 무엇을 보내는가', () {
    test('체크된 구체 재료만 간다 — 해제된 것과 미치환 뭉뚱그림은 빠진다', () async {
      final gateway = FakeLlmGateway();
      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();

      final sent = gateway.lastMatchedIngredients!;
      expect(sent, containsAll(['대파', '계란', '두부', '애호박']));
      expect(sent, isNot(contains('반찬통')), reason: '미치환 뭉뚱그림(ADR-0002)');
      expect(sent, isNot(contains('표고버섯')), reason: '해제된 low');
      expect(sent, isNot(contains('고추장')), reason: '해제된 low');
    });

    test('치환된 재료는 간다', () async {
      final gateway = FakeLlmGateway();
      final controller = await loadedWith(gateway);
      await controller.substituteVague('반찬통', '멸치볶음, 김');
      await controller.requestSuggestions();

      expect(gateway.lastMatchedIngredients, containsAll(['멸치볶음', '김']));
    });

    test('레시피 북 전체가 함께 간다 — 저장 레시피가 매칭의 근거다', () async {
      final gateway = FakeLlmGateway();
      await RecipeBookController(
        gateway,
        storage,
      ).add(url: 'https://youtu.be/abc', title: '김치찌개');

      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();

      expect(gateway.lastMatchedRecipes!.single.title, '김치찌개');
      expect(gateway.lastMatchedRecipes!.single.ingredients, contains('돼지고기'));
    });

    test('보낼 재료가 없으면 호출하지 않는다', () async {
      final gateway = FakeLlmGateway();
      final controller = MainController(gateway, storage);
      await controller.continueWithEmptyChecklist();
      await controller.requestSuggestions();

      expect(gateway.matchCallCount, 0);
      expect(controller.phase, MainPhase.checklist);
    });

    test('한 번의 호출로 끝낸다 — 레시피마다 부르지 않는다', () async {
      final gateway = FakeLlmGateway();
      final book = RecipeBookController(gateway, storage);
      await book.add(url: 'https://youtu.be/1', title: '김치찌개');
      await book.add(url: 'https://youtu.be/2', title: '계란찜');

      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();

      expect(gateway.matchCallCount, 1);
    });
  });

  group('상태 전이', () {
    test('제안을 요청하면 매칭 상태를 거쳐 제안 상태로 간다', () async {
      final gateway = FakeLlmGateway(
        latency: const Duration(milliseconds: 100),
      );
      final controller = await loadedWith(gateway);
      final pending = controller.requestSuggestions();

      await waitFor(controller, () => controller.phase == MainPhase.matching);
      await pending;
      expect(controller.phase, MainPhase.suggestions);
    });

    test('"재료 다시 보기"로 체크리스트로 돌아간다 — 화면 전환 없이', () async {
      final controller = await loadedWith(FakeLlmGateway());
      await controller.requestSuggestions();
      controller.backToChecklist();

      expect(controller.phase, MainPhase.checklist);
    });

    test('앞선 매칭이 날고 있는데 다시 요청하면 앞선 응답은 버려진다 — 로그에도 안 남는다', () async {
      final gateway = FakeLlmGateway(
        latency: const Duration(milliseconds: 100),
      );
      final controller = await loadedWith(gateway);

      // "다시 제안"이 인플라이트 중에 겹쳐 눌린 상황 — 응답 둘이 경합한다.
      final first = controller.requestSuggestions();
      await waitFor(controller, () => controller.phase == MainPhase.matching);
      final second = controller.requestSuggestions();
      await Future.wait([first, second]);

      // 버려진 호출은 화면에도 로그에도 없다 — 인식(_recognizeGeneration)과 같은 계약.
      expect(
        storage.readEvents().where((e) => e.type == AppEventType.matchingDone),
        hasLength(1),
      );
    });
  });

  group('계측', () {
    test('매칭 완료에 지연·토큰·원가·제외 수가 붙는다 (#18 AC)', () async {
      final controller = await loadedWith(FakeLlmGateway());
      await controller.requestSuggestions();

      final done = eventOf(AppEventType.matchingDone);
      expect(done.data['latencyMs'], isA<int>());
      expect(done.data['promptTokens'], 395);
      expect(done.data['outputTokens'], 225);
      expect(done.data['costUsd'], 0.00044);
      expect(done.data['model'], 'fake-matcher');
      expect(done.data['excludedCount'], 0);
      expect(done.data['shownCount'], 2);
    });

    test('제안 노출에 라벨·출처 분포가 붙는다 (#18 AC)', () async {
      final controller = await loadedWith(FakeLlmGateway());
      await controller.requestSuggestions();

      final shown = eventOf(AppEventType.suggestionsShown);
      // 페이크 fixture — 부족 1개(식용유)와 대체 해소(우유→두유).
      expect(shown.data['labels'], ['buyOne', 'maybe']);
      expect(shown.data['sources'], ['generated', 'generated']);
      expect(shown.data['menus'], ['애호박볶음', '두부조림']);
    });

    test('제외된 메뉴 수가 이벤트에 남는다', () async {
      final gateway = FakeLlmGateway()
        ..suggestions = [
          const Suggestion(
            menu: '괜찮',
            source: SuggestionSource.generated,
            missing: [],
            reason: '',
          ),
          const Suggestion(
            menu: '뚱뚱',
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
      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();

      expect(eventOf(AppEventType.matchingDone).data['excludedCount'], 1);
      expect(controller.excludedCount, 1);
      expect(controller.suggestions.map((s) => s.menu), ['괜찮']);
    });

    test('"레시피 보기"가 선택 이벤트로 남는다 — 저장 카드만', () async {
      final gateway = FakeLlmGateway();
      await RecipeBookController(
        gateway,
        storage,
      ).add(url: 'https://youtu.be/abc', title: '김치찌개');

      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();

      final saved = controller.suggestions.firstWhere(
        (s) => s.source == SuggestionSource.saved,
      );
      await controller.openRecipe(saved);

      final opened = eventOf(AppEventType.suggestionOpened);
      expect(opened.data['menu'], '김치찌개');
      expect(opened.data['source'], 'saved');
      expect(opened.data['url'], 'https://youtu.be/abc');
      expect(opened.data['label'], 'ready');
    });

    test('URL 없는 AI 제안은 열 수 없다 — 선택 이벤트도 없다', () async {
      final controller = await loadedWith(FakeLlmGateway());
      await controller.requestSuggestions();

      final generated = controller.suggestions.first;
      expect(generated.recipeUrl, isNull);
      await controller.openRecipe(generated);

      expect(
        storage.readEvents().where(
          (e) => e.type == AppEventType.suggestionOpened,
        ),
        isEmpty,
      );
    });
  });

  group('매칭 실패', () {
    test('실패는 매칭 단계의 인라인 카드로 해소된다 — 인식은 성공한 채로', () async {
      final controller = await loadedWith(
        FakeLlmGateway(matchFailure: const LlmFailure(LlmFailureKind.empty)),
      );
      // 인식은 됐다 — 체크리스트까지 왔다.
      expect(controller.phase, MainPhase.checklist);

      await controller.requestSuggestions();
      expect(controller.phase, MainPhase.failed);
      expect(controller.failureStage, FailureStage.matching);
      expect(controller.failure, LlmFailureKind.empty);
    });

    test('오류 이벤트의 단계가 matching이다 — 인식 실패와 갈린다', () async {
      final controller = await loadedWith(
        FakeLlmGateway(matchFailure: const LlmFailure(LlmFailureKind.timeout)),
      );
      // 인식은 성공했으니 여기까진 오류가 없다.
      expect(
        storage.readEvents().where((e) => e.type == AppEventType.errorShown),
        isEmpty,
      );

      await controller.requestSuggestions();

      final error = eventOf(AppEventType.errorShown);
      expect(error.data['stage'], 'matching');
      expect(error.data['kind'], 'timeout');
    });

    test('매칭 실패 후 "다시 시도"는 매칭만 다시 부른다 — 사진을 다시 올리지 않는다', () async {
      final gateway = FakeLlmGateway(
        matchFailure: const LlmFailure(LlmFailureKind.error),
      );
      final controller = await loadedWith(gateway);
      await controller.requestSuggestions();
      await controller.requestSuggestions();

      expect(gateway.matchCallCount, 2);
      expect(gateway.recognizeCallCount, 1);
    });
  });

  test('매칭 로딩 문구에 쓸 레시피 수를 안다 — "레시피 북 N개와 맞춰보는 중"', () async {
    final gateway = FakeLlmGateway();
    await RecipeBookController(
      gateway,
      storage,
    ).add(url: 'https://youtu.be/abc', title: '김치찌개');

    expect(MainController(gateway, storage).matchingRecipeCount, 1);
  });
}
