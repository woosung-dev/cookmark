// 컨트롤러 유닛 — 인식 제한 시간이 구현이 아니라 호출 경계에서 지켜지는지 검증
import 'dart:async';
import 'dart:typed_data';

import 'package:cookmark/data/app_storage.dart';
import 'package:cookmark/llm/recognizer.dart';
import 'package:cookmark/models/app_event.dart';
import 'package:cookmark/screens/main_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = img.encodeJpg(img.Image(width: 100, height: 100));

  Future<MainController> controllerWith(IngredientRecognizer recognizer) async {
    SharedPreferences.setMockInitialValues({});
    return MainController(
      storage: await AppStorage.open(),
      recognizer: recognizer,
      recognitionTimeout: const Duration(milliseconds: 50),
    );
  }

  group('제한 시간 — 타이머 없는 구현이 부엌 앞 사용자를 무한히 기다리게 두지 않는다', () {
    test('제 타이머가 없는 recognizer도 경계에서 끊긴다', () async {
      final c = await controllerWith(const _NeverReturningRecognizer());

      await c.recognizeBytes(photo);

      expect(c.state, MainState.failed);
      expect(c.failure, FailureReason.timeout);
    });

    test('타임아웃도 오류 이벤트로 남는다', () async {
      final c = await controllerWith(const _NeverReturningRecognizer());

      await c.recognizeBytes(photo);

      final errors = c.storage.events.where(
        (e) => e.type == EventType.errorShown,
      );
      expect(errors, hasLength(1));
      expect(errors.single.data['reason'], 'timeout');
    });
  });

  group('읽을 수 없는 사진', () {
    test('디코드 실패는 저품질 실패로 이어진다 — 앱이 죽지 않는다', () async {
      final c = await controllerWith(const _NeverReturningRecognizer());

      await c.recognizeBytes(Uint8List.fromList([0, 1, 2, 3]));

      expect(c.state, MainState.failed);
      expect(c.failure, FailureReason.lowQuality);
    });
  });
}

/// 영원히 끝나지 않는 인식 — 제한 시간을 구현에 맡겼을 때의 최악을 흉내 낸다.
class _NeverReturningRecognizer implements IngredientRecognizer {
  const _NeverReturningRecognizer();

  @override
  Future<RecognitionResult> recognize(Uint8List imageBytes) =>
      Completer<RecognitionResult>().future;
}
