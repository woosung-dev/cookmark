// 인앱 브라우저 경고와 기대 세팅 문구 — 외길의 나머지 상태들(#21).
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/in_app_browser.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fixtures.dart';

/// 실제 카톡 인앱 브라우저가 보내는 모양.
const _kakaoUa =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36 KAKAOTALK 10.4.5';

const _chromeUa =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Mobile Safari/537.36';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
  });

  MainController controllerWith({String userAgent = _chromeUa}) =>
      MainController(FakeLlmGateway(), storage, userAgent: () => userAgent);

  group('카톡 인앱 브라우저 감지 (#21)', () {
    test('카톡 UA면 경고가 뜬다', () {
      expect(isKakaoInAppBrowser(_kakaoUa), isTrue);
      expect(
        controllerWith(userAgent: _kakaoUa).showsInAppBrowserWarning,
        isTrue,
      );
    });

    test('일반 크롬이면 경고가 없다', () {
      expect(isKakaoInAppBrowser(_chromeUa), isFalse);
      expect(controllerWith().showsInAppBrowserWarning, isFalse);
    });

    test('대소문자를 가리지 않는다 — UA 표기가 버전마다 흔들린다', () {
      expect(isKakaoInAppBrowser('... kakaotalk 10.4.5'), isTrue);
      expect(isKakaoInAppBrowser('... KakaoTalk/10.4.5'), isTrue);
    });

    test('웹이 아닌 타깃(빈 UA)에서는 경고가 없다', () {
      expect(isKakaoInAppBrowser(''), isFalse);
    });

    test('경고는 끌 수 없다 — 끄는 API가 존재하지 않는다', () {
      final controller = controllerWith(userAgent: _kakaoUa);
      // 2주치 기록이 걸린 문제라 사용자가 치울 수 있게 두지 않는다.
      expect(controller.showsInAppBrowserWarning, isTrue);
      expect(controller.showsInAppBrowserWarning, isTrue);
    });
  });

  group('기대 세팅 문구 (1회성, B 이식)', () {
    test('업로드 전에는 없다', () {
      expect(controllerWith().showsExpectationNote, isFalse);
    });

    test('첫 인식 결과 위에 뜬다', () async {
      final controller = controllerWith();
      await controller.uploadPhoto(fridgePhoto());

      expect(controller.showsExpectationNote, isTrue);
    });

    test('두 번째 세션에는 안 뜬다 — 1회성이다', () async {
      await controllerWith().uploadPhoto(fridgePhoto());

      final next = controllerWith();
      await next.uploadPhoto(fridgePhoto());
      expect(next.showsExpectationNote, isFalse);
    });

    test('인식이 실패하면 문구도 안 뜨고, 소진되지도 않는다', () async {
      final failing = MainController(
        FakeLlmGateway(failure: const LlmFailure(LlmFailureKind.error)),
        storage,
        userAgent: () => _chromeUa,
      );
      await failing.uploadPhoto(fridgePhoto());
      expect(failing.showsExpectationNote, isFalse);

      // 다음에 성공하면 그때 뜬다 — 첫 "인식 결과"가 이제야 나왔으므로.
      final next = controllerWith();
      await next.uploadPhoto(fridgePhoto());
      expect(next.showsExpectationNote, isTrue);
    });
  });

  group('실패 4종 × 두 단계 — 전부 인라인으로 해소된다 (G1 #8)', () {
    for (final kind in LlmFailureKind.values) {
      test('인식 ${kind.name}은 인식 섹션의 카드다', () async {
        final controller = MainController(
          FakeLlmGateway(failure: LlmFailure(kind)),
          storage,
          userAgent: () => _chromeUa,
        );
        await controller.uploadPhoto(fridgePhoto());

        expect(controller.phase, MainPhase.failed);
        expect(controller.failureStage, FailureStage.recognition);
        expect(storage.readEvents().last.data['stage'], 'recognition');
      });

      test('매칭 ${kind.name}은 매칭 섹션의 카드다', () async {
        final controller = MainController(
          FakeLlmGateway(matchFailure: LlmFailure(kind)),
          storage,
          userAgent: () => _chromeUa,
        );
        await controller.uploadPhoto(fridgePhoto());
        await controller.requestSuggestions();

        expect(controller.phase, MainPhase.failed);
        expect(controller.failureStage, FailureStage.matching);
        expect(storage.readEvents().last.data['stage'], 'matching');
        expect(storage.readEvents().last.data['kind'], kind.name);
      });
    }
  });
}
