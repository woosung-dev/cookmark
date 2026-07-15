// LLM 경계 유닛 — 프록시 응답 파싱·실패 처리·페이크의 결정성 검증
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookmark/llm/fake_recognizer.dart';
import 'package:cookmark/llm/gemini_proxy_recognizer.dart';
import 'package:cookmark/llm/recognizer.dart';
import 'package:cookmark/models/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final image = Uint8List.fromList([1, 2, 3]);

  GeminiProxyRecognizer recognizerReturning(
    Object body, {
    int status = 200,
    void Function(http.Request)? onRequest,
  }) {
    final client = MockClient((req) async {
      onRequest?.call(req);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return GeminiProxyRecognizer(
      client: client,
      endpoint: Uri.parse('/api/recognize'),
    );
  }

  group('프록시 응답 파싱 — P1에서 확정된 스키마', () {
    test('재료와 confidence를 초기 체크 상태까지 만들어 돌려준다', () async {
      final r = await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
          {'name': '두부', 'confidence': 'medium'},
          {'name': '트러플', 'confidence': 'low'},
        ],
        'usage': {
          'latencyMs': 1900,
          'inputTokens': 1064,
          'outputTokens': 48,
          'estimatedCostUsd': 0.0011,
        },
      }).recognize(image);

      expect(r.ingredients.map((i) => i.name), ['대파', '두부', '트러플']);
      expect(r.ingredients[0].checked, isTrue);
      expect(r.ingredients[1].checked, isTrue);
      expect(r.ingredients[2].checked, isFalse);
    });

    test('사용량 메타데이터를 보존한다 — 원가는 프록시가 계산해 회신한다', () async {
      final r = await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
        ],
        'usage': {
          'latencyMs': 1900,
          'inputTokens': 1157,
          'outputTokens': 295,
          'thinkingTokens': 0,
          'estimatedCostUsd': 0.00073,
        },
      }).recognize(image);

      expect(r.usage.inputTokens, 1157);
      expect(r.usage.outputTokens, 295);
      expect(r.usage.thinkingTokens, 0);
      expect(r.usage.estimatedCostUsd, 0.00073);
    });

    test('thinking 토큰을 보존한다 — T1 #6: 미기록 시 원가의 78%가 누락될 수 있다', () async {
      final r = await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
        ],
        'usage': {
          'inputTokens': 1157,
          'outputTokens': 294,
          'thinkingTokens': 1735,
        },
      }).recognize(image);

      expect(r.usage.thinkingTokens, 1735);
    });

    test('사용량이 이벤트 데이터로 그대로 실린다', () async {
      final r = await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
        ],
        'usage': {
          'latencyMs': 1900,
          'inputTokens': 1157,
          'outputTokens': 295,
          'thinkingTokens': 0,
          'estimatedCostUsd': 0.00073,
        },
      }).recognize(image);

      expect(r.usage.toEventData(), {
        'latencyMs': 1900,
        'inputTokens': 1157,
        'outputTokens': 295,
        'thinkingTokens': 0,
        'estimatedCostUsd': 0.00073,
      });
    });

    test('이미지를 base64로 실어 POST한다', () async {
      http.Request? seen;
      await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
        ],
        'usage': <String, dynamic>{},
      }, onRequest: (r) => seen = r).recognize(image);

      expect(seen!.method, 'POST');
      final sent = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(base64Decode(sent['imageBase64'] as String), image);
    });

    test('사용량이 비어도 인식 결과는 살린다 — 계측 결손이 루프를 막지 않는다', () async {
      final r = await recognizerReturning({
        'ingredients': [
          {'name': '대파', 'confidence': 'high'},
        ],
        'usage': <String, dynamic>{},
      }).recognize(image);

      expect(r.ingredients, hasLength(1));
      expect(r.usage.inputTokens, 0);
    });
  });

  group('실패 — 인라인 에러 카드로 이어질 신호', () {
    test('0개 인식은 empty 사유로 던진다', () async {
      final call = recognizerReturning({
        'ingredients': <dynamic>[],
        'usage': <String, dynamic>{},
      }).recognize(image);

      await expectLater(
        call,
        throwsA(
          isA<RecognitionException>().having(
            (e) => e.reason,
            'reason',
            FailureReason.empty,
          ),
        ),
      );
    });

    test('프록시 5xx는 server 사유로 던진다', () async {
      await expectLater(
        recognizerReturning({'error': 'boom'}, status: 502).recognize(image),
        throwsA(
          isA<RecognitionException>().having(
            (e) => e.reason,
            'reason',
            FailureReason.server,
          ),
        ),
      );
    });

    test('JSON이 아닌 응답도 server 사유로 흡수한다 — 앱이 파싱에서 죽지 않는다', () async {
      await expectLater(
        recognizerReturning('<html>gateway</html>').recognize(image),
        throwsA(
          isA<RecognitionException>().having(
            (e) => e.reason,
            'reason',
            FailureReason.server,
          ),
        ),
      );
    });

    test('30초를 넘기면 timeout 사유로 던진다', () async {
      final client = MockClient(
        (_) => Future.delayed(
          const Duration(seconds: 40),
          () => http.Response('{}', 200),
        ),
      );
      final recognizer = GeminiProxyRecognizer(
        client: client,
        endpoint: Uri.parse('/api/recognize'),
        timeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        recognizer.recognize(image),
        throwsA(
          isA<RecognitionException>().having(
            (e) => e.reason,
            'reason',
            FailureReason.timeout,
          ),
        ),
      );
    });
  });

  group('페이크 — E2E의 결정적 주입원', () {
    test('P1 실측을 닮은 high/medium/low 혼합을 돌려준다', () async {
      final r = await FakeRecognizer().recognize(image);
      final byConfidence = {
        for (final c in Confidence.values)
          c: r.ingredients.where((i) => i.confidence == c).length,
      };

      expect(byConfidence[Confidence.high], greaterThan(0));
      expect(byConfidence[Confidence.medium], greaterThan(0));
      expect(byConfidence[Confidence.low], greaterThan(0));
    });

    test('뭉뚱그림 항목을 포함한다 — #16이 붙을 자리', () async {
      final r = await FakeRecognizer().recognize(image);
      expect(r.ingredients.map((i) => i.name), contains('반찬통'));
    });

    test('두 번 불러도 같은 결과다', () async {
      final fake = FakeRecognizer();
      final a = await fake.recognize(image);
      final b = await fake.recognize(image);
      expect(a.ingredients, b.ingredients);
    });

    test('실패를 주입하면 그 사유로 던진다', () async {
      await expectLater(
        FakeRecognizer(failWith: FailureReason.timeout).recognize(image),
        throwsA(
          isA<RecognitionException>().having(
            (e) => e.reason,
            'reason',
            FailureReason.timeout,
          ),
        ),
      );
    });
  });
}
