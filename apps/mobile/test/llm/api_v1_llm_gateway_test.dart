// apps/api 경계가 응답을 어떻게 읽는지 — snake_case·Bearer 세션이 프록시 경계와 갈리는 지점을 못박는다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookmark/domain/ingredient.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/domain/suggestion.dart';
import 'package:cookmark/llm/api_v1_llm_gateway.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://localhost:8099';
const _token = 'test-session-token';
const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

ApiV1LlmGateway gatewayWith(MockClient client) =>
    ApiV1LlmGateway(baseUrl: _baseUrl, sessionToken: _token, client: client);

ApiV1LlmGateway gatewayReturning(Object body, {int status = 200}) =>
    gatewayWith(
      MockClient(
        (_) async =>
            http.Response(jsonEncode(body), status, headers: _jsonHeaders),
      ),
    );

// T1 #6 실측표의 flash-lite 기본·768px 행 — FastAPI LLMUsage는 snake_case로 회신한다.
const _usage = {
  'prompt_tokens': 1157,
  'output_tokens': 295,
  'thought_tokens': 0,
  'image_tokens': 1064,
  'cost_usd': 0.00073,
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

  test('usage는 snake_case 키를 직접 매핑한다', () async {
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

  test('usage에 thought_tokens·image_tokens가 없으면 0으로 폴백한다', () async {
    final gateway = gatewayReturning({
      'ingredients': [
        {'name': '대파', 'confidence': 'high'},
      ],
      'usage': {
        'prompt_tokens': 1157,
        'output_tokens': 295,
        'cost_usd': 0.00073,
        'model': 'gemini-3.1-flash-lite',
      },
    });

    final usage = (await gateway.recognize(_photo)).usage;
    expect(usage.thoughtTokens, 0);
    expect(usage.imageTokens, 0);
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

    test('low_quality 플래그는 lowQuality — 트리거는 snake_case 키다', () async {
      final gateway = gatewayReturning({'low_quality': true});
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

      // camelCase(lowQuality)는 이 경계의 키가 아니다 — 무시되어 empty로 떨어진다.
      final camel = gatewayReturning({'lowQuality': true});
      await expectLater(
        camel.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.empty),
        ),
      );
    });

    test('HTTP 오류는 error — 401(세션 거부)도 마찬가지다', () async {
      for (final status in [401, 500]) {
        final gateway = gatewayReturning({'detail': 'boom'}, status: status);
        await expectLater(
          gateway.recognize(_photo),
          throwsA(
            isA<LlmFailure>().having(
              (e) => e.kind,
              'kind',
              LlmFailureKind.error,
            ),
          ),
        );
      }
    });

    test('망가진 JSON은 error — 파싱 실패로 죽지 않는다', () async {
      final gateway = gatewayWith(
        MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.error),
        ),
      );
    });

    test('네트워크 예외는 error', () async {
      final gateway = gatewayWith(
        MockClient((_) async => throw const SocketExceptionStub()),
      );
      await expectLater(
        gateway.recognize(_photo),
        throwsA(
          isA<LlmFailure>().having((e) => e.kind, 'kind', LlmFailureKind.error),
        ),
      );
    });
  });

  test('요청은 /api/v1/llm/recognize에 image_base64 본문·Bearer 헤더로 나간다', () async {
    http.Request? sent;
    final gateway = gatewayWith(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'ingredients': [
              {'name': '대파', 'confidence': 'high'},
            ],
            'usage': _usage,
          }),
          200,
          headers: _jsonHeaders,
        );
      }),
    );

    await gateway.recognize(Uint8List.fromList([0xFF, 0xD8, 0xFF]));
    expect(sent!.url.toString(), '$_baseUrl/api/v1/llm/recognize');
    expect(jsonDecode(sent!.body), {
      'image_base64': base64Encode([0xFF, 0xD8, 0xFF]),
    });
    expect(sent!.headers['authorization'], 'Bearer $_token');
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

  group('match', () {
    const savedRecipe = Recipe(
      url: 'https://www.youtube.com/watch?v=ZsvevWrQ6M0',
      title: '가지볶음',
      ingredients: ['가지', '양파'],
    );

    Map<String, Object?> matchBody(List<Map<String, Object?>> suggestions) => {
      'suggestions': suggestions,
      'usage': _usage,
    };

    // og-image 응답만 갈아끼워 match를 태운다 — 실패 유형별 테스트가 공유하는 배선.
    Future<MatchResult> matchWithOgHandler(
      Future<http.Response> Function(http.Request) ogHandler,
    ) {
      final gateway = gatewayWith(
        MockClient((request) async {
          if (request.url.path == '/api/v1/og-image') return ogHandler(request);
          return http.Response(
            jsonEncode(
              matchBody([
                {
                  'menu': '가지볶음',
                  'source': 'saved',
                  'missing': <Object>[],
                  'reason': '재료가 다 있어요',
                },
              ]),
            ),
            200,
            headers: _jsonHeaders,
          );
        }),
      );
      return gateway.match(ingredients: ['가지', '양파'], recipes: [savedRecipe]);
    }

    test('saved 제안은 /api/v1/og-image 경유로 사진이 붙고 generated는 호출하지 않는다', () async {
      final ogRequests = <http.Request>[];
      final gateway = gatewayWith(
        MockClient((request) async {
          if (request.url.path == '/api/v1/og-image') {
            ogRequests.add(request);
            return http.Response(
              jsonEncode({'image_url': 'https://img.example/gaji.jpg'}),
              200,
              headers: _jsonHeaders,
            );
          }
          return http.Response(
            jsonEncode(
              matchBody([
                {
                  'menu': '가지볶음',
                  'source': 'saved',
                  'missing': <Object>[],
                  'reason': '재료가 다 있어요',
                  'match_score': 0.92, // 서버가 실산출하지만 카드 렌더에 안 쓴다 — 무시돼야 한다.
                },
                {
                  'menu': '가지전',
                  'source': 'generated',
                  'missing': [
                    {'name': '부침가루'},
                  ],
                  'reason': '가지만 있으면 돼요',
                },
              ]),
            ),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      final result = await gateway.match(
        ingredients: ['가지', '양파'],
        recipes: [savedRecipe],
      );

      final saved = result.suggestions[0];
      expect(saved.source, SuggestionSource.saved);
      expect(saved.recipeUrl, savedRecipe.url);
      expect(saved.imageUrl, 'https://img.example/gaji.jpg');

      final generated = result.suggestions[1];
      expect(generated.source, SuggestionSource.generated);
      expect(generated.imageUrl, isNull);
      expect(generated.missing.single.name, '부침가루');

      // og-image는 saved 1건만 나간다 — 요청 URL·Bearer 헤더까지 확인한다.
      final og = ogRequests.single;
      expect(og.url.queryParameters['url'], savedRecipe.url);
      expect(og.headers['authorization'], 'Bearer $_token');
    });

    test('og-image 비200은 조용히 null — 제안은 살아남는다', () async {
      final result = await matchWithOgHandler(
        (_) async => http.Response('bad gateway', 502),
      );
      final s = result.suggestions.single;
      expect(s.menu, '가지볶음');
      expect(s.imageUrl, isNull);
    });

    test('og-image 예외도 조용히 null — 제안은 살아남는다', () async {
      final result = await matchWithOgHandler(
        (_) async => throw const SocketExceptionStub(),
      );
      final s = result.suggestions.single;
      expect(s.menu, '가지볶음');
      expect(s.imageUrl, isNull);
    });

    test('saved인데 요청 recipes에 같은 제목이 없으면 generated로 강등된다', () async {
      final requests = <http.Request>[];
      final gateway = gatewayWith(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              matchBody([
                {
                  'menu': '없는 레시피',
                  'source': 'saved',
                  'missing': <Object>[],
                  'reason': '북에 있다고 주장한다',
                },
              ]),
            ),
            200,
            headers: _jsonHeaders,
          );
        }),
      );

      final result = await gateway.match(
        ingredients: ['가지'],
        recipes: [savedRecipe],
      );

      final s = result.suggestions.single;
      expect(s.source, SuggestionSource.generated);
      expect(s.recipeUrl, isNull);
      // 강등됐으니 og-image 호출도 없다 — match POST 1건이 전부다.
      expect(requests.single.url.path, '/api/v1/llm/match');
    });
  });
}

/// dart:io 없이 네트워크 예외를 흉내 낸다 — 웹 빌드에는 SocketException이 없다.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
