// 운영 기기 세션 경계 — apps/api의 POST /api/v1/auth/device로 익명 계정·세션을 받는다(#168).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/storage.dart';
import 'device_session.dart';

/// 등록 호출의 상한 — 다른 서버 경계와 동일(G1 #8).
const _timeout = Duration(seconds: 30);

/// 익명 기기 등록의 실 HTTP 구현.
///
/// 계약은 전부 상류가 정했다(#167 · ADR-0012) — 경로 `/api/v1/auth/device` · **본문 없는 POST** ·
/// 등록 키를 `Authorization: Bearer`로 · 거부는 **403**(401이 아니다. 401이면 이 클래스가 스스로
/// 재등록을 부르는 부팅 루프가 된다) · 응답은 로그인 콜백과 같은 세션 스키마.
///
/// 응답의 `expires_at`·`account`는 **읽지 않는다.** 서버의 슬라이딩 갱신이 만료를 계속 뒤로 밀어
/// 발급 시점 값이 곧 낡고, 계정 식별자는 앱이 쓸 곳이 없다(로그인 화면·탭·설정 항목 0).
/// 만료의 신호는 401 하나뿐이다.
class ApiV1DeviceSession implements DeviceSession {
  ApiV1DeviceSession({
    required this._baseUrl,
    required this._registerKey,
    required this._storage,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String _baseUrl;
  final String _registerKey;
  final Storage _storage;
  final http.Client _client;

  /// 지금 유효하다고 믿는 토큰. 스토리지가 정본이고 이건 왕복을 아끼는 사본이다.
  String? _current;

  /// 진행 중인 등록. 부팅에서 두 소비자가 같은 프레임에 물으면 계정이 둘 나고 하나가 즉시
  /// 고아가 된다 — 고아 파기는 파운더 수동이라(ADR-0012) 안 만드는 편이 싸다.
  Future<String>? _registering;

  @override
  Future<String> token() => normalizeDeviceSessionFailures(() async {
    if (_current case final cached?) return cached;
    if (await _storage.readDeviceToken() case final stored?
        when stored.isNotEmpty) {
      return _current = stored;
    }
    return _register();
  });

  @override
  Future<String> reregister(String usedToken) =>
      normalizeDeviceSessionFailures(() async {
        // 다른 경계가 이미 갈아끼웠다 — 같은 죽은 토큰으로 각자 401을 받은 경우다.
        if (_current case final current? when current != usedToken) {
          return current;
        }
        return _register();
      });

  /// 등록 왕복 1회. 동시 호출은 하나로 합류시킨다.
  Future<String> _register() async {
    if (_registering case final inFlight?) return inFlight;
    final started = _requestRegistration();
    _registering = started;
    try {
      return await started;
    } finally {
      // 실패도 캐시하지 않는다 — 다음 호출이 다시 시도할 수 있어야 한다.
      _registering = null;
    }
  }

  Future<String> _requestRegistration() async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/auth/device'),
            // 본문 없는 POST다 — 등록 키가 유일한 입력이고 그건 헤더로 간다.
            headers: {'authorization': 'Bearer $_registerKey'},
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      // TimeoutException도 Exception이다 — 타임아웃·네트워크 모두 같은 실패로 간다.
      throw DeviceSessionFailure(e.toString());
    }

    if (response.statusCode != 200) {
      throw DeviceSessionFailure('HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw DeviceSessionFailure('응답 파싱 실패: ${e.message}');
    }

    // 본문이 JSON 객체가 아닐 때의 캐스트 실패는 호출부의 normalizeDeviceSessionFailures가
    // 잡는다 — 유형 열거를 여기 남기면 계약이 두 곳으로 갈린다(LLM 경계와 동형).
    final token = (decoded! as Map).cast<String, Object?>()['token'] as String?;
    if (token == null || token.isEmpty) {
      // 빈 토큰을 받아들이면 빈 Bearer로 요청이 나가고 서버가 401을 내 재등록이 돈다.
      throw const DeviceSessionFailure('응답에 토큰이 없다');
    }

    await _storage.writeDeviceToken(token);
    return _current = token;
  }
}
