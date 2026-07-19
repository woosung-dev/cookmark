// 코어 루프의 상태 전이와 계측 — 사진 업로드부터 재료 체크리스트까지(#14).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/ingredient.dart';
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

  test('페이크 fixture는 P1 실측을 닮았다 — 3단 혼합 + 뭉뚱그림 항목', () {
    final confidences = defaultRecognitionFixture
        .map((i) => i.confidence)
        .toSet();
    expect(confidences, containsAll(Confidence.values));
    expect(defaultRecognitionFixture.map((i) => i.name), contains('반찬통'));
  });
}
