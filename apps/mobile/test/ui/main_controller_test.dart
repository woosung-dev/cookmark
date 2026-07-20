// 코어 루프의 상태 전이와 계측 — 사진 업로드부터 재료 체크리스트까지(#14).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/ingredient.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
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

  MainController controllerWith(FakeLlmGateway gateway) => MainController(
    gateway,
    storage,
    now: () => DateTime.utc(2026, 7, 15, 19),
  );

  test('처음엔 업로드 상태다', () {
    expect(controllerWith(FakeLlmGateway()).phase, MainPhase.upload);
  });

  test('사진을 올리면 재료 체크리스트로 간다', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    expect(controller.phase, MainPhase.checklist);
    expect(controller.ingredients, isNotEmpty);
  });

  test('인식 결과가 confidence 3단 초기 상태로 온다 (ADR-0003)', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    final byName = {for (final i in controller.ingredients) i.name: i};
    expect(byName['대파']!.checked, isTrue, reason: 'high는 체크');
    expect(byName['애호박']!.checked, isTrue, reason: 'medium도 체크');
    expect(byName['표고버섯']!.checked, isFalse, reason: 'low는 해제');
  });

  test('사진 업로드와 인식 완료가 이벤트로 남는다', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    expect(storage.readEvents().map((e) => e.type), [
      AppEventType.photoUpload,
      AppEventType.recognitionDone,
    ]);
  });

  test('업로드 이벤트는 리사이즈된 뒤의 크기를 기록한다 — 768px 레버가 먹었는지의 증거', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    final upload = storage.readEvents().first;
    expect(upload.data['width'], 768);
  });

  test('인식 완료 이벤트에 토큰·원가·모델 귀속이 붙는다', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    final done = storage.readEvents().last;
    expect(done.data['promptTokens'], 1157);
    expect(done.data['outputTokens'], 295);
    expect(done.data['imageTokens'], 1064);
    expect(done.data['costUsd'], 0.00073);
    expect(done.data['count'], 7);
    // thinking 모델로 갈아타면 여기가 원가의 대부분이 된다(T1 #6) — 필드 자체가 있어야 한다.
    expect(done.data.containsKey('thoughtTokens'), isTrue);
    expect(done.data['model'], 'fake-recognizer');
  });

  test('인식은 768px로 줄인 사진을 받는다 — 원본을 그대로 보내지 않는다', () async {
    final gateway = FakeLlmGateway();
    final controller = controllerWith(gateway);
    final original = fridgePhoto();
    await controller.uploadPhoto(original);

    expect(gateway.recognizeCallCount, 1);
    expect(storage.readEvents().first.data['bytes'], lessThan(original.length));
  });

  group('실패는 인라인으로 해소된다 (G1 #8 — 에러 화면 없음)', () {
    for (final kind in LlmFailureKind.values) {
      test('${kind.name} 실패는 failed 상태와 오류 이벤트를 남긴다', () async {
        final controller = controllerWith(
          FakeLlmGateway(failure: LlmFailure(kind)),
        );
        await controller.uploadPhoto(fridgePhoto());

        expect(controller.phase, MainPhase.failed);
        expect(controller.failure, kind);

        final error = storage.readEvents().last;
        expect(error.type, AppEventType.errorShown);
        expect(error.data['kind'], kind.name);
        expect(error.data['stage'], 'recognition');
      });
    }
  });

  test('"다시 시도"는 같은 사진으로 다시 부른다 — 리사이즈를 되풀이하지 않는다', () async {
    final gateway = FakeLlmGateway(
      failure: const LlmFailure(LlmFailureKind.error),
    );
    final controller = controllerWith(gateway);
    await controller.uploadPhoto(fridgePhoto());
    await controller.retryRecognition();

    expect(gateway.recognizeCallCount, 2);
    // 업로드 이벤트는 1건뿐 — 재시도는 새 업로드가 아니다(업로드 세션 이중 계상 방지).
    expect(
      storage.readEvents().where((e) => e.type == AppEventType.photoUpload),
      hasLength(1),
    );
  });

  test('"직접 입력으로 계속"은 빈 체크리스트로 루프를 이어간다', () async {
    final controller = controllerWith(
      FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty)),
    );
    await controller.uploadPhoto(fridgePhoto());
    controller.continueWithEmptyChecklist();

    expect(controller.phase, MainPhase.checklist);
    expect(controller.ingredients, isEmpty);
  });

  test('인식이 끝나면 사진을 들고 있지 않는다 — 사진은 보관하지 않는다(스펙 Out of scope)', () async {
    final controller = controllerWith(FakeLlmGateway());
    await controller.uploadPhoto(fridgePhoto());

    expect(controller.photo, isNull);
  });

  test('인식 중에는 사진을 들고 있다 — 스캔 시머를 얹을 대상', () async {
    final gateway = FakeLlmGateway(latency: const Duration(milliseconds: 200));
    final controller = controllerWith(gateway);
    final pending = controller.uploadPhoto(fridgePhoto());

    await waitFor(controller, () => controller.phase == MainPhase.recognizing);
    expect(controller.photo, isNotNull);

    await pending;
    expect(controller.phase, MainPhase.checklist);
  });

  test('빈 인식 결과는 페이크가 아니라 경계가 판정한다 — 0개면 empty 실패', () async {
    final controller = controllerWith(
      FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.empty)),
    );
    await controller.uploadPhoto(fridgePhoto());
    expect(controller.failure, LlmFailureKind.empty);
  });

  group('재업로드 — 첫 인식 뒤에도 코어 루프를 다시 시작할 수 있다 (T3)', () {
    test('startNewPhoto는 업로드 상태로 되돌리고 체크리스트를 비운다', () async {
      final controller = controllerWith(FakeLlmGateway());
      await controller.uploadPhoto(fridgePhoto());
      await controller.startNewPhoto();

      expect(controller.phase, MainPhase.upload);
      expect(controller.ingredients, isEmpty);
      expect(controller.photo, isNull);
    });

    test('startNewPhoto 뒤 세션 복원은 옛 체크리스트를 되살리지 않는다', () async {
      final controller = controllerWith(FakeLlmGateway());
      await controller.uploadPhoto(fridgePhoto());
      await controller.startNewPhoto();

      controller.restoreSession();
      expect(controller.phase, MainPhase.upload);
      expect(controller.ingredients, isEmpty);
    });

    test('startNewPhoto는 이벤트를 남기지 않는다 — photoUpload는 다음 사진에서 찍힌다', () async {
      final controller = controllerWith(FakeLlmGateway());
      await controller.uploadPhoto(fridgePhoto());
      final before = storage.readEvents().length;
      await controller.startNewPhoto();

      expect(storage.readEvents().length, before);
    });

    test('startNewPhoto는 떠 있던 제안·stale·접힘도 치운다', () async {
      final controller = controllerWith(FakeLlmGateway());
      await controller.uploadPhoto(fridgePhoto());
      await controller.requestSuggestions();
      await controller.toggle('대파');
      await controller.startNewPhoto();

      expect(controller.suggestions, isEmpty);
      expect(controller.isStale, isFalse);
      expect(controller.checklistExpanded, isTrue);
      expect(controller.pendingCooked, isNull);
    });
  });

  group('기록 초기화 — 갓 부팅 상태로 되감는다 (#144)', () {
    /// 관통 테스트가 남길 법한 것을 전부 만든다 — 이벤트·세션·체크리스트·제안·1회성 문구.
    Future<MainController> afterThroughputTest() async {
      final controller = controllerWith(FakeLlmGateway());
      await controller.uploadPhoto(fridgePhoto());
      await controller.toggle('대파');
      await controller.requestSuggestions();
      return controller;
    }

    test('메모리 상태가 화면에서 사라진다 — 영속 키만 지우면 리셋이 눈에 보이게 깨진다', () async {
      final controller = await afterThroughputTest();
      expect(controller.ingredients, isNotEmpty, reason: '지울 것이 있어야 공허하지 않다');
      expect(controller.suggestions, isNotEmpty);

      await controller.resetPilotRecord();

      expect(controller.phase, MainPhase.upload);
      expect(controller.ingredients, isEmpty);
      expect(controller.suggestions, isEmpty);
      expect(controller.isStale, isFalse);
      expect(controller.checklistExpanded, isTrue);
      expect(controller.pendingCooked, isNull);
      expect(controller.failure, isNull);
    });

    test('1회성 문구가 다시 뜬다 — 영속 플래그를 지웠으니 메모리도 같이 되감는다', () async {
      final controller = await afterThroughputTest();
      expect(storage.readExpectationNoteSeen(), isTrue);

      await controller.resetPilotRecord();
      expect(controller.showsExpectationNote, isFalse);

      // 지웠으므로 다음 인식에서 처음처럼 다시 뜬다 — 배우자의 첫 인식이 진짜 첫 인식이 된다.
      await controller.uploadPhoto(fridgePhoto());
      expect(controller.showsExpectationNote, isTrue);
    });

    test('이벤트는 0이고 레시피는 남는다 — 스토리지 경계를 그대로 통과한다', () async {
      await storage.writeRecipes([
        const Recipe(
          url: 'https://youtu.be/abc',
          title: '김치찌개',
          ingredients: ['김치'],
        ),
      ]);
      final controller = await afterThroughputTest();
      expect(storage.readEvents(), isNotEmpty);

      await controller.resetPilotRecord();

      expect(storage.readEvents(), isEmpty);
      expect(controller.debugMetrics.eventCount, 0);
      expect(controller.debugMetrics.manualEdits, 0);
      expect(storage.readRecipes(), hasLength(1));
      expect(controller.recipeCount, 1);
    });

    test('푸터는 열린 채로 남는다 — 파운더가 여기서 "이벤트 0"을 확인한다', () async {
      final controller = await afterThroughputTest();
      controller.toggleDebugFooter();
      expect(controller.showsDebugFooter, isTrue);

      await controller.resetPilotRecord();

      // 보존 경계의 유일한 예외다. 같이 닫으면 확인하려고 제스처를 다시 해야 한다.
      expect(controller.showsDebugFooter, isTrue);
    });

    test('초기화 자체는 이벤트를 남기지 않는다 — 0이 정상이라는 계약이 깨진다', () async {
      final controller = await afterThroughputTest();
      await controller.resetPilotRecord();

      // 웹에서는 재import가 backup/import 1건을 남겨 "이벤트 1"이 정상이었다(#41).
      // 네이티브에서 초기화가 자기 흔적을 남기면 그 반전이 무의미해진다.
      expect(storage.readEvents(), isEmpty);
    });

    test('날고 있던 인식이 초기화 뒤에 돌아와도 이벤트를 남기지 않는다', () async {
      // 실 Gemini 인식은 5~10초다 — 파운더가 기다리다 초기화하면 그 사이에 응답이 온다.
      // 원가 원장(US 28)은 버려진 호출도 기록하지만, **초기화는 그 호출이 속한 구간 자체를
      // 지운다** — 지워진 구간의 이벤트가 뒤늦게 되살아나면 파운더가 보는 수는 "이벤트 1"이다.
      final gateway = FakeLlmGateway(
        latency: const Duration(milliseconds: 300),
      );
      final controller = controllerWith(gateway);

      final inFlight = controller.uploadPhoto(fridgePhoto());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.resetPilotRecord();
      await inFlight;

      expect(
        storage.readEvents(),
        isEmpty,
        reason: '초기화 후 돌아온 응답이 이벤트를 남기면 "이벤트 0"이 깨진다',
      );
      expect(controller.phase, MainPhase.upload, reason: '화면도 안 덮는다');
    });

    test('취소·재업로드로 버려진 호출은 여전히 원장에 남는다 — 원가는 실제로 썼다', () async {
      // 초기화만 예외다. `startNewPhoto`는 구간을 지우지 않으므로 US 28이 그대로 산다 —
      // 이 테스트가 없으면 위 수정이 원가 원장을 조용히 망가뜨려도 아무도 모른다.
      final gateway = FakeLlmGateway(
        latency: const Duration(milliseconds: 300),
      );
      final controller = controllerWith(gateway);

      final inFlight = controller.uploadPhoto(fridgePhoto());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.startNewPhoto();
      await inFlight;

      expect(
        storage.readEvents().map((e) => e.type),
        contains(AppEventType.recognitionDone),
        reason: '토큰을 실제로 썼으므로 원장에는 남아야 한다(US 28)',
      );
    });
  });

  test('페이크 fixture는 P1 실측을 닮았다 — 3단 혼합 + 뭉뚱그림 항목', () {
    final confidences = defaultRecognitionFixture
        .map((i) => i.confidence)
        .toSet();
    expect(confidences, containsAll(Confidence.values));
    expect(defaultRecognitionFixture.map((i) => i.name), contains('반찬통'));
  });
}
