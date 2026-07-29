// 서버 레시피 북 경계가 계약(snake_case RecipeResponse·상태 코드)을 어떻게 읽는지 — 컷오버 #121.
import 'dart:async';
import 'dart:convert';

import 'package:cookmark/auth/device_session.dart';
import 'package:cookmark/auth/fake_device_session.dart';
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 기존 테스트가 기대하는 고정 토큰 — 세션이 이미 등록돼 있는 상태다.
FakeDeviceSession sessionWithToken() =>
    FakeDeviceSession(storedToken: 'tok-123');

ServerRecipeRepository repoWith(MockClient client, {DeviceSession? session}) =>
    ServerRecipeRepository(
      baseUrl: 'https://api.test',
      session: session ?? sessionWithToken(),
      client: client,
    );

ServerRecipeRepository repoReturning(Object body, {int status = 200}) =>
    repoWith(
      MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

/// 서버 RecipeResponse 그대로 — created_at이 실려 오지만 앱은 버린다.
Map<String, Object?> serverRecipe({
  required String id,
  required String url,
  required String title,
  List<String> ingredients = const [],
}) => {
  'id': id,
  'url': url,
  'title': title,
  'ingredients': ingredients,
  'created_at': '2026-07-18T00:00:00Z',
};

Matcher failsWith(RecipeApiFailureKind kind) =>
    throwsA(isA<RecipeApiFailure>().having((e) => e.kind, 'kind', kind));

void main() {
  group('fetchAll', () {
    test('삽입순 그대로 파싱하고 id를 매핑한다 — created_at은 버린다', () async {
      final repo = repoReturning([
        serverRecipe(
          id: 'aaa',
          url: 'https://r.test/1',
          title: '김치찌개',
          ingredients: ['김치', '두부'],
        ),
        serverRecipe(id: 'bbb', url: 'https://r.test/2', title: '계란찜'),
      ]);

      final recipes = await repo.fetchAll();

      expect(recipes.map((r) => r.id), ['aaa', 'bbb']);
      expect(recipes.map((r) => r.title), ['김치찌개', '계란찜']);
      expect(recipes.first.ingredients, ['김치', '두부']);
    });

    test('빈 배열은 빈 목록이다 — 실패가 아니다', () async {
      expect(await repoReturning(<Object>[]).fetchAll(), isEmpty);
    });

    test('망가진 JSON은 unavailable — 파싱 실패로 죽지 않는다', () async {
      final repo = repoWith(
        MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(
        repo.fetchAll(),
        failsWith(RecipeApiFailureKind.unavailable),
      );
    });

    test(
      '200인데 List가 아닌 본문도 unavailable — TypeError로 이탈하지 않는다(#25 계열)',
      () async {
        await expectLater(
          repoReturning(<String, Object?>{}).fetchAll(),
          failsWith(RecipeApiFailureKind.unavailable),
        );
      },
    );

    test('항목의 필드 결손도 unavailable — Recipe.fromJson 캐스트 실패까지 정규화한다', () async {
      await expectLater(
        repoReturning([
          {'id': 'aaa', 'title': '김치찌개'}, // url 결손.
        ]).fetchAll(),
        failsWith(RecipeApiFailureKind.unavailable),
      );
    });
  });

  group('create', () {
    test('201을 파싱한다 — id와 서버가 추출한 ingredients가 실려 온다', () async {
      final repo = repoReturning(
        serverRecipe(
          id: 'srv-uuid',
          url: 'https://r.test/1',
          title: '김치찌개',
          ingredients: ['김치', '돼지고기'],
        ),
        status: 201,
      );

      final recipe = await repo.create(url: 'https://r.test/1', title: '김치찌개');

      expect(recipe.id, 'srv-uuid');
      expect(recipe.ingredients, ['김치', '돼지고기']);
    });

    test(
      '201인데 필드가 결손된 본문은 unavailable — TypeError로 이탈하지 않는다(#25 계열)',
      () async {
        await expectLater(
          repoReturning({
            'id': 'srv-uuid', // url·title 결손.
          }, status: 201).create(url: 'https://r.test/1', title: '김치찌개'),
          failsWith(RecipeApiFailureKind.unavailable),
        );
      },
    );

    test('502는 extractionFailed — 레시피는 저장되지 않았다', () async {
      await expectLater(
        repoReturning({
          'detail': '재료 추출에 실패해 저장하지 않았다',
        }, status: 502).create(url: 'https://r.test/1', title: '김치찌개'),
        failsWith(RecipeApiFailureKind.extractionFailed),
      );
    });

    test('재등록 뒤에도 401이면 unauthorized — 무한 재등록하지 않는다', () async {
      // 이 페이크는 **모든** 요청에 401을 준다. 재등록이 붙은 뒤(#168) 여기 도달한다는 것은
      // 갓 발급받은 토큰으로도 401이었다는 뜻이고, 그건 세션 만료가 아니라 서버 쪽 사건이다.
      await expectLater(
        repoReturning({
          'detail': 'unauthorized',
        }, status: 401).create(url: 'https://r.test/1', title: '김치찌개'),
        failsWith(RecipeApiFailureKind.unauthorized),
      );
    });

    test('타임아웃은 unavailable — 실제 30초를 기다리지 않고 전송 실패 경로를 태운다', () async {
      final repo = repoWith(
        MockClient((_) async => throw TimeoutException('요청 상한 초과')),
      );
      await expectLater(
        repo.create(url: 'https://r.test/1', title: '김치찌개'),
        failsWith(RecipeApiFailureKind.unavailable),
      );
    });

    test('경로·Bearer·본문이 계약대로다 — 본문은 {url, title}만', () async {
      http.Request? sent;
      final repo = repoWith(
        MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(
              serverRecipe(id: 'x', url: 'https://r.test/1', title: '김치찌개'),
            ),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await repo.create(url: 'https://r.test/1', title: '김치찌개');

      expect(sent!.url.toString(), 'https://api.test/api/v1/recipes');
      expect(sent!.headers['authorization'], 'Bearer tok-123');
      expect(jsonDecode(sent!.body), {
        'url': 'https://r.test/1',
        'title': '김치찌개',
      });
    });
  });

  group('patchIngredients', () {
    test('200을 파싱한다', () async {
      final repo = repoReturning(
        serverRecipe(
          id: 'aaa',
          url: 'https://r.test/1',
          title: '김치찌개',
          ingredients: ['김치', '두부', '대파'],
        ),
      );

      final recipe = await repo.patchIngredients(
        id: 'aaa',
        ingredients: ['김치', '두부', '대파'],
      );
      expect(recipe.ingredients, ['김치', '두부', '대파']);
    });

    test('404는 notFound — 남의 것도 같은 응답이다', () async {
      await expectLater(
        repoReturning({
          'detail': '레시피를 찾을 수 없다',
        }, status: 404).patchIngredients(id: 'ghost', ingredients: ['김치']),
        failsWith(RecipeApiFailureKind.notFound),
      );
    });

    test('본문은 {ingredients}만 — url·title을 실으면 계약 위반이다', () async {
      http.Request? sent;
      final repo = repoWith(
        MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(
              serverRecipe(
                id: 'aaa',
                url: 'https://r.test/1',
                title: '김치찌개',
                ingredients: ['김치'],
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await repo.patchIngredients(id: 'aaa', ingredients: ['김치']);

      expect(sent!.method, 'PATCH');
      expect(sent!.url.toString(), 'https://api.test/api/v1/recipes/aaa');
      expect(jsonDecode(sent!.body), {
        'ingredients': ['김치'],
      });
    });
  });

  group('delete', () {
    test('204면 조용히 끝난다', () async {
      http.Request? sent;
      final repo = repoWith(
        MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await repo.delete('aaa');

      expect(sent!.method, 'DELETE');
      expect(sent!.url.toString(), 'https://api.test/api/v1/recipes/aaa');
    });

    test('404는 notFound', () async {
      await expectLater(
        repoReturning({'detail': '레시피를 찾을 수 없다'}, status: 404).delete('ghost'),
        failsWith(RecipeApiFailureKind.notFound),
      );
    });
  });

  group('importBulk', () {
    const localRecipes = [
      Recipe(
        id: 'stale-id',
        url: 'https://r.test/1',
        title: '김치찌개',
        ingredients: ['김치', '두부'],
      ),
      Recipe(url: 'https://r.test/2', title: '계란찜', ingredients: ['계란']),
    ];

    test('요청 본문에 id·created_at이 없다 — additionalProperties:false 가드', () async {
      http.Request? sent;
      final repo = repoWith(
        MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode([
              serverRecipe(
                id: 'srv-1',
                url: 'https://r.test/1',
                title: '김치찌개',
                ingredients: ['김치', '두부'],
              ),
              serverRecipe(
                id: 'srv-2',
                url: 'https://r.test/2',
                title: '계란찜',
                ingredients: ['계란'],
              ),
            ]),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await repo.importBulk(localRecipes);

      expect(sent!.url.toString(), 'https://api.test/api/v1/migration/recipes');
      expect(jsonDecode(sent!.body), {
        'recipes': [
          {
            'url': 'https://r.test/1',
            'title': '김치찌개',
            'ingredients': ['김치', '두부'],
          },
          {
            'url': 'https://r.test/2',
            'title': '계란찜',
            'ingredients': ['계란'],
          },
        ],
      });
    });

    test('201을 파싱한다 — 서버가 발급한 id가 실려 온다', () async {
      final repo = repoReturning([
        serverRecipe(
          id: 'srv-1',
          url: 'https://r.test/1',
          title: '김치찌개',
          ingredients: ['김치', '두부'],
        ),
        serverRecipe(
          id: 'srv-2',
          url: 'https://r.test/2',
          title: '계란찜',
          ingredients: ['계란'],
        ),
      ], status: 201);

      final saved = await repo.importBulk(localRecipes);
      expect(saved.map((r) => r.id), ['srv-1', 'srv-2']);
    });

    test('500은 unavailable — 아무것도 저장되지 않았으니 로컬을 유지한다', () async {
      await expectLater(
        repoReturning({
          'detail': '가져오기에 실패해 아무것도 저장하지 않았다',
        }, status: 500).importBulk(localRecipes),
        failsWith(RecipeApiFailureKind.unavailable),
      );
    });
  });

  group('502의 의미는 엔드포인트에 달렸다 (#127)', () {
    // 서버에서 502를 내는 recipes 라우트는 POST /recipes 하나뿐이다(UpstreamLLMError =
    // Gemini 자체 다운). GET·PATCH·DELETE는 502를 내지 않고 bulk 가져오기 실패는 500이다.
    // 그러므로 create 밖의 502는 전부 인프라 502(Cloud Run bad gateway)이고,
    // "재료를 알아내지 못해 저장하지 못했어요"로 뜨면 서버 장애를 사용자 입력 탓으로 돌린다.
    const someRecipes = [
      Recipe(url: 'https://r.test/1', title: '김치찌개', ingredients: ['김치']),
    ];

    test('create의 502만 extractionFailed다', () async {
      await expectLater(
        repoReturning({
          'detail': '재료 추출에 실패해 저장하지 않았다',
        }, status: 502).create(url: 'https://r.test/1', title: '김치찌개'),
        failsWith(RecipeApiFailureKind.extractionFailed),
      );
    });

    for (final (name, call) in <(String, Future<void> Function())>[
      ('fetchAll', () => repoReturning({}, status: 502).fetchAll()),
      (
        'patchIngredients',
        () => repoReturning(
          {},
          status: 502,
        ).patchIngredients(id: 'srv-uuid', ingredients: ['김치']),
      ),
      ('delete', () => repoReturning({}, status: 502).delete('srv-uuid')),
      (
        'importBulk',
        () => repoReturning({}, status: 502).importBulk(someRecipes),
      ),
    ]) {
      test('$name의 502는 unavailable — 인프라 502이지 추출 실패가 아니다', () async {
        await expectLater(call(), failsWith(RecipeApiFailureKind.unavailable));
      });
    }
  });

  group('401 → 재등록 (#168)', () {
    /// 첫 요청만 401을 주고 그다음부터 [ok]를 준다 — 세션이 죽어 있던 상황.
    MockClient expiredOnce(Object ok, {int status = 200}) {
      var calls = 0;
      return MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(jsonEncode({'detail': 'unauthorized'}), 401);
        }
        return http.Response(
          jsonEncode(ok),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
    }

    test('401이면 재등록 후 1회 재전송하고, 사용자에겐 실패가 아니다', () async {
      final session = sessionWithToken();
      final repo = repoWith(
        expiredOnce([
          serverRecipe(id: 'r1', url: 'https://r.test/1', title: '김치찌개'),
        ]),
        session: session,
      );

      expect(await repo.fetchAll(), hasLength(1));
      expect(session.registerCount, 1, reason: '재등록이 정확히 한 번 일어난다');
    });

    test('재전송은 **새 토큰**을 싣는다 — 죽은 토큰을 다시 보내지 않는다', () async {
      final sent = <String?>[];
      var calls = 0;
      final session = sessionWithToken();
      final repo = repoWith(
        MockClient((request) async {
          sent.add(request.headers['authorization']);
          calls++;
          if (calls == 1) return http.Response('{}', 401);
          return http.Response(
            jsonEncode(<Object>[]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        session: session,
      );

      await repo.fetchAll();
      expect(sent.first, 'Bearer tok-123');
      expect(sent.last, 'Bearer ${session.currentToken}');
      expect(sent.last, isNot(sent.first));
      expect(calls, 2, reason: '재전송은 딱 1회다');
    });

    test('등록 자체가 실패하면 unavailable — 자격증명 문제로 오인시키지 않는다', () async {
      // DeviceSessionFailure 한 값이 403·네트워크·타임아웃·형식 불일치를 다 덮는다. 앱이 그 넷을
      // 못 가르므로, 서버에 못 닿은 것을 "접속 정보가 유효하지 않아요"로 내보내면 안 된다(#166 · §G).
      final session = FakeDeviceSession(
        storedToken: 'tok-123',
        failure: const DeviceSessionFailure('HTTP 403'),
      );
      final repo = repoWith(
        MockClient((_) async => http.Response('{}', 401)),
        session: session,
      );

      await expectLater(
        repo.fetchAll(),
        failsWith(RecipeApiFailureKind.unavailable),
      );
    });

    test('토큰이 아예 없으면 첫 요청 전에 등록한다 — 401을 기다리지 않는다', () async {
      final session = FakeDeviceSession();
      String? sentAuth;
      final repo = repoWith(
        MockClient((request) async {
          sentAuth = request.headers['authorization'];
          return http.Response(
            jsonEncode(<Object>[]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        session: session,
      );

      await repo.fetchAll();
      expect(session.registerCount, 1);
      expect(sentAuth, 'Bearer ${session.currentToken}');
    });

    test('401이 아닌 실패에는 재등록하지 않는다 — 502는 세션 문제가 아니다', () async {
      final session = sessionWithToken();
      final repo = repoWith(
        MockClient((_) async => http.Response('{}', 502)),
        session: session,
      );

      await expectLater(
        repo.create(url: 'https://r.test/1', title: '김치찌개'),
        failsWith(RecipeApiFailureKind.extractionFailed),
      );
      expect(session.registerCount, 0);
    });
  });

  group('Recipe.id — 수송 메타데이터', () {
    const withId = Recipe(
      id: 'aaa',
      url: 'https://r.test/1',
      title: '김치찌개',
      ingredients: ['김치'],
    );
    const withoutId = Recipe(
      url: 'https://r.test/1',
      title: '김치찌개',
      ingredients: ['김치'],
    );

    test('copyWith가 id를 보존한다', () {
      expect(withId.copyWith(ingredients: ['김치', '두부']).id, 'aaa');
      expect(withId.copyWith().id, 'aaa');
    });

    test('toJson은 id가 있을 때만 싣는다 — 기존 백업 JSON 하위호환', () {
      expect(withId.toJson()['id'], 'aaa');
      expect(withoutId.toJson().containsKey('id'), isFalse);
    });

    test('fromJson 왕복이 id를 보존한다', () {
      expect(Recipe.fromJson(withId.toJson()), withId);
      expect(Recipe.fromJson(withId.toJson()).id, 'aaa');
      expect(Recipe.fromJson(withoutId.toJson()).id, isNull);
    });

    test('==는 id를 무시한다 — 같은 내용·다른 id는 동등하다(정체성은 url)', () {
      expect(withId, withoutId);
      expect(
        withId,
        const Recipe(
          id: 'bbb',
          url: 'https://r.test/1',
          title: '김치찌개',
          ingredients: ['김치'],
        ),
      );
      expect(withId.hashCode, withoutId.hashCode);
    });
  });
}
