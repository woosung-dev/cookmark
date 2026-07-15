// 뭉뚱그림 항목의 수명주기 — 감지·치환·오탐 복귀·매칭 제외(ADR-0002).
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

  test('인식 결과의 뭉뚱그림 항목이 칩으로 분리된다', () async {
    final controller = await loadedController();

    // 페이크 fixture의 "반찬통" — P1 실측을 닮은 항목.
    expect(controller.vagueItems.map((i) => i.name), ['반찬통']);
  });

  test('뭉뚱그림 항목은 체크리스트 본문에 섞이지 않는다', () async {
    final controller = await loadedController();

    // ingredients에는 있지만 vagueItems로 갈린다 — 화면이 분리해 그린다.
    expect(controller.ingredients.map((i) => i.name), contains('반찬통'));
    expect(
      controller.ingredients.where((i) => !i.isVague).map((i) => i.name),
      isNot(contains('반찬통')),
    );
  });

  test('미치환 뭉뚱그림은 매칭 전송 대상에서 조용히 빠진다 (ADR-0002)', () async {
    final controller = await loadedController();

    expect(
      controller.matchableIngredients.map((i) => i.name),
      isNot(contains('반찬통')),
    );
    // 체크된 구체 재료는 간다.
    expect(controller.matchableIngredients.map((i) => i.name), contains('대파'));
    // 해제된 low도 안 간다.
    expect(
      controller.matchableIngredients.map((i) => i.name),
      isNot(contains('표고버섯')),
    );
  });

  group('인라인 치환', () {
    test('"반찬통" → "멸치볶음, 김"이면 칩이 사라지고 구체 재료가 들어온다', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '멸치볶음, 김');

      expect(controller.vagueItems, isEmpty);
      expect(controller.ingredients.map((i) => i.name), isNot(contains('반찬통')));
      expect(
        controller.ingredients.map((i) => i.name),
        containsAll(['멸치볶음', '김']),
      );
    });

    test('치환된 재료는 매칭에 간다 — 사용자의 재고 지식이 데이터가 된다', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '멸치볶음, 김');

      expect(
        controller.matchableIngredients.map((i) => i.name),
        containsAll(['멸치볶음', '김']),
      );
    });

    test('몇 개로 갈리든 1시퀀스 = 수동 수정 1회다 (ADR-0003)', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '멸치볶음, 김, 콩자반, 오이무침');

      expect(edits(), hasLength(1));
      expect(edits().single.data['kind'], 'substitute');
    });

    test('치환은 경로 vagueChip으로 남고 무엇으로 바꿨는지도 남는다', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '멸치볶음, 김');

      expect(edits().single.data, {
        'kind': 'substitute',
        'path': 'vagueChip',
        'name': '반찬통',
        'replacements': ['멸치볶음', '김'],
      });
    });

    test('빈 입력으로는 치환되지 않는다 — 칩이 그대로 남는다', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '   ');

      expect(controller.vagueItems.map((i) => i.name), ['반찬통']);
      expect(edits(), isEmpty);
    });

    test('이미 있는 이름으로 치환하면 줄이 늘지 않는다', () async {
      final controller = await loadedController();
      await controller.substituteVague('반찬통', '대파, 김');

      final names = controller.ingredients.map((i) => i.name).toList();
      expect(names.where((n) => n == '대파'), hasLength(1));
      expect(names, contains('김'));
    });

    test('뭉뚱그림이 아닌 항목은 치환되지 않는다', () async {
      final controller = await loadedController();
      await controller.substituteVague('대파', '쪽파');

      expect(controller.ingredients.map((i) => i.name), contains('대파'));
      expect(edits(), isEmpty);
    });
  });

  group('오탐 복귀', () {
    test('탭 1회로 일반 항목이 된다', () async {
      final controller = await loadedController();
      await controller.dismissVague('반찬통');

      expect(controller.vagueItems, isEmpty);
      expect(controller.ingredients.map((i) => i.name), contains('반찬통'));
    });

    test('복귀하면 매칭에도 간다 — 사용자가 맞다고 했으므로', () async {
      final controller = await loadedController();
      await controller.dismissVague('반찬통');

      expect(
        controller.matchableIngredients.map((i) => i.name),
        contains('반찬통'),
      );
    });

    test('별도 kind로 남는다 — 산식 판정이 미결이라 뭉뚱그려 세지 않는다', () async {
      final controller = await loadedController();
      await controller.dismissVague('반찬통');

      expect(edits().single.data['kind'], 'vagueDismiss');
      expect(edits().single.data['path'], 'vagueChip');
    });

    test('ADR-0003이 열거한 4종만 수동 수정으로 센다 — vagueDismiss는 빠져 있다', () {
      expect(EditKind.values.where((k) => k.countsAsManualEdit), [
        EditKind.uncheck,
        EditKind.recheck,
        EditKind.add,
        EditKind.substitute,
      ]);
      expect(EditKind.vagueDismiss.countsAsManualEdit, isFalse);
    });
  });

  test('뭉뚱그림 상태는 세션 복원 후에도 유지된다', () async {
    await loadedController();
    final restored = newController()..restoreSession();

    expect(restored.vagueItems.map((i) => i.name), ['반찬통']);
  });

  test('치환 결과도 세션 복원 후 유지된다', () async {
    final first = await loadedController();
    await first.substituteVague('반찬통', '멸치볶음, 김');

    final restored = newController()..restoreSession();
    expect(restored.vagueItems, isEmpty);
    expect(restored.ingredients.map((i) => i.name), containsAll(['멸치볶음', '김']));
  });
}
