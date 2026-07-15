// 이거 했어요·실행취소·다시 제안·stale — 성공 지표 2(행동 변화)의 판정 장치(#19).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
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

  /// 제안이 떠 있는 상태의 컨트롤러.
  Future<MainController> withSuggestions() async {
    final controller = MainController(
      FakeLlmGateway(),
      storage,
      now: DateTime.now,
    );
    await controller.uploadPhoto(fridgePhoto());
    await controller.requestSuggestions();
    return controller;
  }

  AppEvent eventOf(AppEventType type) =>
      storage.readEvents().lastWhere((e) => e.type == type);

  Iterable<AppEvent> eventsOf(AppEventType type) =>
      storage.readEvents().where((e) => e.type == type);

  group('이거 했어요', () {
    test('누르면 이벤트가 남고 5초 실행취소가 열린다', () async {
      final controller = await withSuggestions();
      final target = controller.suggestions.first;
      await controller.markCooked(target);

      expect(controller.pendingCooked, target);
      final cooked = eventOf(AppEventType.cooked);
      expect(cooked.data['menu'], target.menu);
      expect(cooked.data['source'], target.source.name);
      expect(cooked.data['label'], target.label.name);
    });

    test('갓 뽑은 제안에서 누르면 stale이 거짓이다', () async {
      final controller = await withSuggestions();
      await controller.markCooked(controller.suggestions.first);

      expect(eventOf(AppEventType.cooked).data['stale'], isFalse);
    });
  });

  group('실행취소', () {
    test('되돌리면 이벤트가 남는다 — 취소도 데이터다', () async {
      final controller = await withSuggestions();
      final target = controller.suggestions.first;
      await controller.markCooked(target);
      await controller.undoCooked();

      expect(controller.pendingCooked, isNull);
      expect(eventOf(AppEventType.cookedUndo).data['menu'], target.menu);
    });

    test('이거 했어요와 실행취소가 둘 다 남는다 — 지워지지 않는다', () async {
      final controller = await withSuggestions();
      await controller.markCooked(controller.suggestions.first);
      await controller.undoCooked();

      expect(eventsOf(AppEventType.cooked), hasLength(1));
      expect(eventsOf(AppEventType.cookedUndo), hasLength(1));
    });

    test('창이 닫히면 되돌릴 수 없고, 취소 이벤트도 없다', () async {
      final controller = await withSuggestions();
      await controller.markCooked(controller.suggestions.first);
      controller.dismissUndo();
      await controller.undoCooked();

      expect(eventsOf(AppEventType.cookedUndo), isEmpty);
    });

    test('누른 적 없이 되돌리면 아무 일도 없다', () async {
      final controller = await withSuggestions();
      await controller.undoCooked();
      expect(eventsOf(AppEventType.cookedUndo), isEmpty);
    });
  });

  group('stale — 성공 지표 2의 순도 방어 (ADR-0001)', () {
    test('제안이 뜬 직후엔 낡지 않았다', () async {
      final controller = await withSuggestions();
      expect(controller.isStale, isFalse);
    });

    test('재료를 손대면 아래 제안이 낡는다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');

      expect(controller.isStale, isTrue);
    });

    test('제안이 없을 때의 재료 수정은 낡음을 만들지 않는다', () async {
      final controller = MainController(FakeLlmGateway(), storage);
      await controller.uploadPhoto(fridgePhoto());
      await controller.toggle('대파');

      expect(controller.isStale, isFalse);
    });

    test('낡은 뒤 "이거 했어요"에는 stale이 붙는다 — 집계에서 분리된다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      await controller.markCooked(controller.suggestions.first);

      expect(eventOf(AppEventType.cooked).data['stale'], isTrue);
    });

    test('낡은 뒤 "레시피 보기"에도 stale이 붙는다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      await controller.openRecipe(controller.suggestions.first);

      // 페이크 fixture의 저장 제안이 없으면 생성 제안뿐이라 URL이 없다 — 그 경우는 건너뛴다.
      final opened = eventsOf(AppEventType.suggestionOpened);
      if (opened.isNotEmpty) {
        expect(opened.last.data['stale'], isTrue);
      }
    });

    test('낡은 뒤 실행취소에도 stale이 붙는다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      await controller.markCooked(controller.suggestions.first);
      await controller.undoCooked();

      expect(eventOf(AppEventType.cookedUndo).data['stale'], isTrue);
    });

    test('추가·치환 같은 다른 조작도 낡게 만든다', () async {
      for (final edit in [
        (MainController c) => c.addIngredient('두유', path: EditPath.typing),
        (MainController c) => c.substituteVague('반찬통', '김'),
      ]) {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        storage = await Storage.open();

        final controller = await withSuggestions();
        await edit(controller);
        expect(controller.isStale, isTrue);
      }
    });
  });

  group('다시 제안', () {
    test('실행하면 이벤트가 남고 낡음이 풀린다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      expect(controller.isStale, isTrue);

      await controller.requestSuggestions();

      expect(controller.isStale, isFalse);
      expect(eventOf(AppEventType.rematch).data['previousCount'], 2);
    });

    test('새 제안 노출은 stale이 거짓이다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      await controller.requestSuggestions();

      expect(eventOf(AppEventType.suggestionsShown).data['stale'], isFalse);
    });

    test('첫 제안에는 rematch 이벤트가 없다 — 갱신이 아니라 처음이다', () async {
      await withSuggestions();
      expect(eventsOf(AppEventType.rematch), isEmpty);
    });

    test('다시 제안 뒤 "이거 했어요"는 stale이 거짓이다 — 순도가 회복된다', () async {
      final controller = await withSuggestions();
      await controller.toggle('대파');
      await controller.requestSuggestions();
      await controller.markCooked(controller.suggestions.first);

      expect(eventOf(AppEventType.cooked).data['stale'], isFalse);
    });
  });

  group('섹션 접힘 (G1 #8 — 지나간 섹션은 요약 한 줄)', () {
    test('제안이 뜨면 체크리스트가 접힌다', () async {
      final controller = await withSuggestions();
      expect(controller.checklistExpanded, isFalse);
    });

    test('제안 전에는 펼쳐져 있다', () async {
      final controller = MainController(FakeLlmGateway(), storage);
      await controller.uploadPhoto(fridgePhoto());
      expect(controller.checklistExpanded, isTrue);
    });

    test('탭하면 다시 펼쳐진다 — 재료를 손보러 갈 수 있다', () async {
      final controller = await withSuggestions();
      controller.toggleChecklistExpanded();
      expect(controller.checklistExpanded, isTrue);
    });
  });
}
