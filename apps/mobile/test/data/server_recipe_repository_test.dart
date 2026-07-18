// 서버 레시피 북 경계가 계약(snake_case RecipeResponse·상태 코드)을 어떻게 읽는지 — 컷오버 #121.
import 'dart:async';
import 'dart:convert';

import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ServerRecipeRepository repoWith(MockClient client) => ServerRecipeRepository(
  baseUrl: 'https://api.test',
  sessionToken: 'tok-123',
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

    test('401은 unauthorized', () async {
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
