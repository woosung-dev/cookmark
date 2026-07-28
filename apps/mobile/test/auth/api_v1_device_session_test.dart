// 기기 세션 경계의 HTTP 계약 — 등록 키 운반·토큰 영속·실패 정규화(#168).
//
// 관용구는 test/llm/api_v1_llm_gateway_test.dart 그대로다: MockClient로 요청을 붙잡고,
// 200인데 모양이 다른 본문이 경계 밖으로 새지 않는지를 교차곱으로 확인한다(#142).
import 'dart:async';
import 'dart:convert';

import 'package:cookmark/auth/api_v1_device_session.dart';
import 'package:cookmark/auth/device_session.dart';
import 'package:cookmark/data/storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _baseUrl = 'http://localhost:8099';
const _registerKey = 'test-register-key';
const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// 서버가 실제로 주는 모양 — `SessionResponse`(#167).
Map<String, Object?> _session(String token) => {
  'token': token,
  'expires_at': '2026-08-28T00:00:00Z',
  'account': {
    'id': '5b9f1f1e-0000-4000-8000-000000000001',
    'iss': 'device',
    'sub': '9b1c0a5e-0000-4000-8000-000000000002',
    'created_at': '2026-07-29T00:00:00Z',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // 등록 토큰의 보안 저장소를 인메모리로 갈아끼운다 — 유닛 테스트엔 플러그인 채널이 없다.
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<ApiV1DeviceSession> sessionWith(MockClient client) async =>
      ApiV1DeviceSession(
        baseUrl: _baseUrl,
        registerKey: _registerKey,
        storage: await Storage.open(),
        client: client,
      );

  Future<ApiV1DeviceSession> sessionReturning(
    Object body, {
    int status = 200,
  }) => sessionWith(
    MockClient(
      (_) async =>
          http.Response(jsonEncode(body), status, headers: _jsonHeaders),
    ),
  );

  group('등록 요청 — POST /api/v1/auth/device', () {
    test('등록 키를 Bearer로 싣고 본문 없이 나간다', () async {
      http.Request? sent;
      final session = await sessionWith(
        MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(_session('sess-1')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      expect(await session.token(), 'sess-1');
      expect(sent!.method, 'POST');
      expect(sent!.url.toString(), '$_baseUrl/api/v1/auth/device');
      // 등록 키는 사용자 자격증명이 아니라 **빌드 자격증명**이다(#167 파운더 확정 계약 ①).
      expect(sent!.headers['authorization'], 'Bearer $_registerKey');
      expect(sent!.body, isEmpty);
    });

    test('발급 토큰이 스토리지에 남는다 — 다시 열어도 읽힌다', () async {
      final session = await sessionReturning(_session('sess-1'));
      await session.token();

      final reopened = await Storage.open();
      expect(await reopened.readDeviceToken(), 'sess-1');
    });

    test('저장된 토큰이 있으면 등록하지 않는다 — 1빌드=N계정이지 1실행=N계정이 아니다', () async {
      await (await Storage.open()).writeDeviceToken('sess-stored');
      var calls = 0;
      final session = await sessionWith(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode(_session('sess-new')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      expect(await session.token(), 'sess-stored');
      expect(calls, 0);
    });

    test('토큰이 없으면 등록은 딱 1회다 — 두 번 물어도 재사용한다', () async {
      var calls = 0;
      final session = await sessionWith(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode(_session('sess-$calls')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      expect(await session.token(), 'sess-1');
      expect(await session.token(), 'sess-1');
      expect(calls, 1);
    });

    test('부팅에서 동시에 물어도 계정이 하나만 난다 — 등록 요청이 합류한다', () async {
      var calls = 0;
      final gate = Completer<void>();
      final session = await sessionWith(
        MockClient((_) async {
          calls++;
          await gate.future;
          return http.Response(
            jsonEncode(_session('sess-1')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      // 하이드레이트와 다른 호출이 같은 프레임에 붙는 상황 — 계정이 둘 나면 하나가 즉시 고아다.
      final both = Future.wait([session.token(), session.token()]);
      gate.complete();

      expect(await both, ['sess-1', 'sess-1']);
      expect(calls, 1);
    });
  });

  group('재등록 — 401을 받았을 때', () {
    test('저장된 토큰이 있어도 새로 등록하고 덮어쓴다', () async {
      await (await Storage.open()).writeDeviceToken('sess-dead');
      final session = await sessionReturning(_session('sess-fresh'));

      expect(await session.reregister('sess-dead'), 'sess-fresh');
      expect(await session.token(), 'sess-fresh');
      expect(await (await Storage.open()).readDeviceToken(), 'sess-fresh');
    });

    test('다른 경계가 이미 갈아끼웠으면 등록하지 않는다 — 고아 계정을 안 만든다', () async {
      var calls = 0;
      final session = await sessionWith(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode(_session('sess-$calls')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      expect(await session.token(), 'sess-1'); // 첫 등록
      expect(await session.reregister('sess-1'), 'sess-2'); // 경계 A가 401
      // 경계 B가 같은 죽은 토큰으로 401을 받았다 — 이미 새 토큰이 있으므로 등록하지 않는다.
      expect(await session.reregister('sess-1'), 'sess-2');
      expect(calls, 2);
    });
  });

  group('실패 정규화 — 밖으로 나가는 것은 DeviceSessionFailure뿐이다', () {
    test('403(등록 키 거부)은 정규화된 실패다 — 재시도로 못 고친다', () async {
      final session = await sessionReturning({
        'detail': '등록 키가 없거나 유효하지 않다',
      }, status: 403);
      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));
    });

    test('거부되면 토큰이 저장되지 않는다 — 다음 실행이 빈 상태로 시작한다', () async {
      final session = await sessionReturning(<String, Object?>{}, status: 403);
      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));

      expect(await (await Storage.open()).readDeviceToken(), isNull);
    });

    test('실패한 등록은 캐시되지 않는다 — 다음 호출이 다시 시도한다', () async {
      var calls = 0;
      final session = await sessionWith(
        MockClient((_) async {
          calls++;
          if (calls == 1) return http.Response('{}', 503);
          return http.Response(
            jsonEncode(_session('sess-1')),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));
      expect(await session.token(), 'sess-1');
    });

    test('네트워크 예외는 정규화된 실패다', () async {
      final session = await sessionWith(
        MockClient((_) async => throw const _SocketExceptionStub()),
      );
      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));
    });

    test('망가진 JSON은 정규화된 실패다', () async {
      final session = await sessionWith(
        MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));
    });

    test('token이 빈 문자열이면 실패다 — 빈 Bearer는 서버가 401로 돌려준다', () async {
      final session = await sessionReturning(_session(''));
      await expectLater(session.token(), throwsA(isA<DeviceSessionFailure>()));
    });

    // 아래 목록은 오늘 아는 모양이다. 계약은 그보다 넓다 — 서버가 바뀌면 내일은 다른 모양이 온다.
    test('어떤 오형식 200 본문이든 DeviceSessionFailure 밖으로 새지 않는다 (#142)', () async {
      const malformed = <Object>[
        <Object>[],
        'just a string',
        42,
        <String, Object?>{},
        {'token': null},
        {'token': 42},
        {'token': <String>[]},
        {'tokens': 'sess-1'},
        {'token': '', 'expires_at': '2026-08-28T00:00:00Z'},
        {
          'token': {'value': 'sess-1'},
        },
      ];

      for (final body in malformed) {
        for (final call in <(String, Future<Object?> Function(DeviceSession))>[
          ('token', (s) => s.token()),
          ('reregister', (s) => s.reregister('sess-dead')),
        ]) {
          final session = await sessionReturning(body);
          await expectLater(
            call.$2(session),
            throwsA(isA<DeviceSessionFailure>()),
            reason: '${call.$1}이 $body에서 DeviceSessionFailure가 아닌 것을 던졌다',
          );
        }
      }
    });
  });
}

/// dart:io 없이 네트워크 예외를 흉내 낸다 — 웹 빌드에는 SocketException이 없다.
class _SocketExceptionStub implements Exception {
  const _SocketExceptionStub();
}
