// 테스트용 결정적 기기 세션 경계 — E2E·유닛이 이 seam에 주입한다(스펙 Testing Decisions).
import 'device_session.dart';

/// 결정적 페이크. 등록 횟수를 세고, 실패를 주입해 등록이 안 되는 세계를 재현한다.
///
/// `lib/`에 사는 이유는 [FakeLlmGateway]와 같다 — 웹 타깃 E2E는 컴파일 루트가 `integration_test/`라
/// `test/`를 import할 수 없다.
class FakeDeviceSession implements DeviceSession {
  FakeDeviceSession({String? storedToken, this.failure})
    : _current = storedToken;

  String? _current;

  /// null이 아니면 등록이 이 실패로 끝난다.
  ///
  /// 가변인 이유는 [FakeLlmGateway.failure]와 같다 — "등록이 실패했다가 다음엔 된다"를
  /// 한 테스트 안에서 재현하려면 도중에 꺼야 한다.
  DeviceSessionFailure? failure;

  /// 실제로 등록 왕복이 일어난 횟수 — "로그인 화면 0"과 "401 → 재등록"은 둘 다 이 수로 찍힌다.
  int registerCount = 0;

  /// 지금 발급돼 있는 토큰. 등록한 적이 없으면 null이다.
  String? get currentToken => _current;

  @override
  Future<String> token() async => _current ?? _register();

  @override
  Future<String> reregister(String usedToken) async {
    if (_current case final current? when current != usedToken) return current;
    return _register();
  }

  String _register() {
    if (failure case final f?) throw f;
    registerCount++;
    return _current = 'fake-session-$registerCount';
  }
}
