// 프록시 경계가 응답을 어떻게 읽는지 — 모델이 스키마를 벗어나도 화면이 살아야 한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookmark/domain/ingredient.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/llm/proxy_llm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ProxyLlmGateway gatewayReturning(Object body, {int status = 200}) {
  return ProxyLlmGateway(
    client: MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
}

// T1 #6 실측표의 flash-lite 기본·768px 행.
const _usage = {
  'promptTokens': 1157,
  'outputTokens': 295,
  'thoughtTokens': 0,
  'imageTokens': 1064,
  'costUsd': 0.00073,
  'model': 'gemini-3.1-flash-lite',
};

final _photo = Uint8List.fromList([1, 2, 3]);

void main() {
  test('P1 스키마를 읽어 재료 체크리스트 초기 상태를 만든다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '대파', 'confidence': 'high'},
        {'name': '애호박', 'confidence': 'medium'},
        {'name': '표고버섯', 'confidence': 'low'},
      ],
      'usage': _usage,
    });

    final result = await gateway.recognize(_photo);

    expect(result.ingredients.map((i) => i.name), ['대파', '애호박', '표고버섯']);
    expect(result.ingredients.map((i) => i.checked), [true, true, false]);
  });

  test('사용량 메타데이터가 모델 귀속과 함께 온다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '대파', 'confidence': 'high'},
      ],
      'usage': _usage,
    });

    final usage = (await gateway.recognize(_photo)).usage;
    expect(usage.promptTokens, 1157);
    expect(usage.outputTokens, 295);
    expect(usage.thoughtTokens, 0);
    expect(usage.imageTokens, 1064);
    expect(usage.costUsd, 0.00073);
    expect(usage.model, 'gemini-3.1-flash-lite');
    expect(usage.billedTokens, 1157 + 295);
  });

  test('스키마를 벗어난 항목은 버리고 나머지는 살린다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '대파', 'confidence': 'high'},
        {'name': '', 'confidence': 'high'},
        {'name': '계란', 'confidence': 'very-high'},
        {'confidence': 'high'},
        {'name': '두부', 'confidence': 'medium'},
      ],
      'usage': _usage,
    });

    final result = await gateway.recognize(_photo);
    expect(result.ingredients.map((i) => i.name), ['대파', '두부']);
  });

  test('이름 앞뒤 공백은 다듬는다 — 매칭에서 다른 재료로 갈리면 안 된다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '  대파 ', 'confidence': 'high'},
      ],
      'usage': _usage,
    });

    expect((await gateway.recognize(_photo)).ingredients.single.name, '대파');
  });

  test('한글이 깨지지 않는다 — UTF-8로 디코드한다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '멸치볶음', 'confidence': 'high'},
      ],
      'usage': _usage,
    });

    expect((await gateway.recognize(_photo)).ingredients.single.name, '멸치볶음');
  });

  group('실패', () {
    test('인식 0개는 empty', () async {
      final gateway = gatewayReturning({
        'ingredients': <Object>[],
        'usage': _usage,
      });
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.empty),
        ),
      );
    });

    test('전부 스키마를 벗어나 남는 게 없어도 empty', () async {
      final gateway = gatewayReturning({
        'ingredients': [
          {'name': '계란', 'confidence': 'maybe'},
        ],
        'usage': _usage,
      });
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.empty),
        ),
      );
    });

    test('저품질 플래그는 lowQuality', () async {
      final gateway = gatewayReturning({'lowQuality': true});
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having(
            (e) => e.kind,
            'kind',
            LlmFailureKind.lowQuality,
          ),
        ),
      );
    });

    test('HTTP 오류는 error', () async {
      final gateway = gatewayReturning({'message': 'boom'}, status: 500);
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.error),
        ),
      );
    });

    test('망가진 JSON은 error — 파싱 실패로 죽지 않는다', () async {
      final gateway = ProxyLlmGateway(
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.error),
        ),
      );
    });

    test('네트워크 예외는 error', () async {
      final gateway = ProxyLlmGateway(
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.error),
        ),
      );
    });
  });

  test('사진은 base64로 실려 간다', () async {
    String? sentBody;
    final gateway = ProxyLlmGateway(
      client: MockClient((request) async {
        sentBody = request.body;
        return http.Response(
          jsonEncode({
            'ingredients': [
              {'name': '대파', 'confidence': 'high'},
            ],
            'usage': _usage,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await gateway.recognize(Uint8List.fromList([0xFF, 0xD8, 0xFF]));
    expect(jsonDecode(sentBody!), {
      'imageBase64': base64Encode([0xFF, 0xD8, 0xFF]),
    });
  });

  test('confidence 3단 전부가 초기 상태로 반영된다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        for (final c in Confidence.values)
          {'name': c.name, 'confidence': c.name},
      ],
      'usage': _usage,
    });

    final byName = {
      for (final i in (await gateway.recognize(_photo)).ingredients) i.name: i,
    };
    expect(byName['high']!.confidence, Confidence.high);
    expect(byName['medium']!.confidence, Confidence.medium);
    expect(byName['low']!.confidence, Confidence.low);
  });
}

/// dart:io 없이 네트워크 예외를 흉내 낸다 — 웹 빌드에는 SocketException이 없다.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
