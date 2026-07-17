// 수동 수정 계측 — ADR-0003 산식. 이게 흔들리면 P2 킬 기준의 2주 데이터가 비교 불가가 된다.
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/ingredient.dart';
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

  MainController newController() =>
      MainController(FakeLlmGateway(), storage, now: DateTime.now);

  Future<MainController> loadedController() async {
    final controller = newController();
    await controller.uploadPhoto(fridgePhoto());
    return controller;
  }

  List<AppEvent> edits() => storage
      .readEvents()
      .where((e) => e.type == AppEventType.checklistEdit)
      .toList();

  group('행 탭 토글 (유일한 제스처)', () {
    test('체크된 항목을 탭하면 해제되고 uncheck가 경로 row로 남는다', () async {
      final controller = await loadedController();
      await controller.toggle('대파');

      expect(
        controller.ingredients.firstWhere((i) => i.name == '대파').checked,
        isFalse,
      );
      expect(edits().single.data, {
        'kind': 'uncheck',
        'path': 'row',
        'name': '대파',
      });
    });

    test('해제된 low 항목을 탭하면 재체크되고 recheck로 남는다', () async {
      final controller = await loadedController();
      await controller.toggle('표고버섯');

      expect(
        controller.ingredients.firstWhere((i) => i.name == '표고버섯').checked,
        isTrue,
      );
      expect(edits().single.data['kind'], 'recheck');
    });

    test('해제·재체크가 각각 1회씩 계측된다 — 되돌려도 0이 되지 않는다', () async {
      final controller = await loadedController();
      await controller.toggle('대파');
      await controller.toggle('대파');

      // 마찰 측정이므로 손이 간 횟수를 전부 센다(ADR-0003).
      expect(edits().map((e) => e.data['kind']), ['uncheck', 'recheck']);
    });

    test('없는 이름을 토글하면 아무 일도 없다', () async {
      final controller = await loadedController();
      await controller.toggle('없는재료');
      expect(edits(), isEmpty);
    });

    test('low 환각을 그냥 두면 0회다 — 무시가 곧 정답인 경우', () async {
      await loadedController();
      expect(edits(), isEmpty);
    });
  });

  group('직접 추가', () {
    test('타이핑 추가는 경로 typing으로 남는다', () async {
      final controller = await loadedController();
      await controller.addIngredient('두유', path: EditPath.typing);

      expect(edits().single.data, {
        'kind': 'add',
        'path': 'typing',
        'name': '두유',
      });
      expect(controller.ingredients.last.name, '두유');
    });

    test('칩 추가는 경로 frequentChip으로 남는다 — 타이핑과 갈린다', () async {
      final controller = await loadedController();
      await controller.addIngredient('두유', path: EditPath.frequentChip);

      expect(edits().single.data['path'], 'frequentChip');
    });

    test('직접 추가한 재료는 confidence가 없고 체크된 상태다', () async {
      final controller = await loadedController();
      await controller.addIngredient('두유', path: EditPath.typing);

      final added = controller.ingredients.firstWhere((i) => i.name == '두유');
      expect(added.confidence, isNull);
      expect(added.checked, isTrue);
    });

    test('앞뒤 공백은 다듬는다', () async {
      final controller = await loadedController();
      await controller.addIngredient('  두유  ', path: EditPath.typing);
      expect(controller.ingredients.last.name, '두유');
    });

    test('빈 문자열은 무시한다 — 계측도 없다', () async {
      final controller = await loadedController();
      await controller.addIngredient('   ', path: EditPath.typing);
      expect(edits(), isEmpty);
    });

    test('이미 체크된 이름을 또 추가하면 줄이 늘지 않고 계측도 없다', () async {
      final controller = await loadedController();
      final before = controller.ingredients.length;
      await controller.addIngredient('대파', path: EditPath.typing);

      expect(
        controller.ingredients.length,
        before,
        reason: '같은 재료가 두 줄이면 매칭이 오염된다',
      );
      expect(edits(), isEmpty);
    });

    test('해제된 이름을 추가하면 재체크로 되살아나고 recheck로 남는다', () async {
      final controller = await loadedController();
      await controller.addIngredient('표고버섯', path: EditPath.typing);

      expect(
        controller.ingredients.firstWhere((i) => i.name == '표고버섯').checked,
        isTrue,
      );
      expect(edits().single.data['kind'], 'recheck');
    });
  });

  group('자주 쓰는 재료 칩 (빈도 기반)', () {
    test('이력이 없으면 칩이 없다 — 빈도는 이력에서만 나온다', () async {
      final controller = await loadedController();
      expect(controller.frequentIngredients, isEmpty);
    });

    test('추가·재체크가 쌓인 만큼 빈도가 올라간다', () async {
      final first = await loadedController();
      await first.addIngredient('두유', path: EditPath.typing);
      await first.addIngredient('김', path: EditPath.typing);
      await first.toggle('두유'); // uncheck — 빈도에 안 들어간다
      await first.toggle('두유'); // recheck — 들어간다

      // 새 세션에서 칩을 본다.
      final next = newController();
      expect(next.frequentIngredients, ['두유', '김']);
    });

    test('해제만 한 재료는 칩이 되지 않는다 — 없다는 진술이다', () async {
      final first = await loadedController();
      await first.toggle('대파'); // uncheck

      final next = newController();
      expect(next.frequentIngredients, isEmpty);
    });

    test('이미 체크리스트에 있는 재료는 칩에서 빠진다', () async {
      final first = await loadedController();
      await first.addIngredient('두유', path: EditPath.typing);

      // 같은 재료가 이미 목록에 있는 새 컨트롤러.
      final next = newController();
      await next.uploadPhoto(fridgePhoto());
      await next.addIngredient('두유', path: EditPath.typing);
      expect(next.frequentIngredients, isNot(contains('두유')));
    });

    test('칩은 8개를 넘지 않는다', () async {
      final controller = await loadedController();
      for (var i = 0; i < 12; i++) {
        await controller.addIngredient('재료$i', path: EditPath.typing);
      }

      final next = newController();
      expect(next.frequentIngredients, hasLength(8));
    });
  });

  group('세션 복원', () {
    test('브라우저를 닫았다 열면 마지막 체크리스트로 돌아간다', () async {
      final first = await loadedController();
      await first.toggle('대파');
      await first.addIngredient('두유', path: EditPath.typing);

      final restored = newController()..restoreSession();

      expect(restored.phase, MainPhase.checklist);
      expect(
        restored.ingredients.firstWhere((i) => i.name == '대파').checked,
        isFalse,
        reason: '해제 상태까지 복원된다',
      );
      expect(restored.ingredients.map((i) => i.name), contains('두유'));
    });

    test('저장된 세션이 없으면 업로드 상태로 시작한다', () {
      final controller = newController()..restoreSession();
      expect(controller.phase, MainPhase.upload);
    });

    test('confidence가 복원돼야 흐린 그룹이 유지된다', () async {
      await loadedController();
      final restored = newController()..restoreSession();

      expect(
        restored.ingredients.firstWhere((i) => i.name == '표고버섯').confidence,
        Confidence.low,
      );
    });

    test('세션 복원은 이벤트를 만들지 않는다 — 사용자가 한 조작이 아니다', () async {
      await loadedController();
      final before = storage.readEvents().length;

      newController().restoreSession();
      expect(storage.readEvents(), hasLength(before));
    });
  });

  test('수정 카운터는 컨트롤러가 화면에 내놓지 않는다 — 로그에만 있다 (ADR-0004 단일맹검)', () async {
    final controller = await loadedController();
    await controller.toggle('대파');

    // 조작 수를 세는 공개 API가 없다. 배우자에게 계측을 노출하지 않는다.
    expect(edits(), hasLength(1), reason: '로그에는 남는다');
  });
}
