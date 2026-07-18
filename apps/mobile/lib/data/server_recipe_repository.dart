// 서버 레시피 북(/api/v1/recipes·/api/v1/migration/recipes)의 유일한 HTTP 경계 — 컷오버 #121.
//
// ApiV1LlmGateway와 같은 관용구(Bearer 세션·snake_case·타임아웃 정규화)지만 독립 구현이다 —
// LLM seam과 레시피 북 경계는 서로 다른 seam이라 실패 타입도 따로 간다(RecipeApiFailure).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/recipe.dart';

/// 상한 30초 — 서버 create가 내부에서 LLM extract를 1회 돌므로 G1 #8의 인식 상한을 그대로 쓴다.
const _timeout = Duration(seconds: 30);

/// 서버 레시피 북 호출이 실패한 이유 — UI는 이 4종만 분기한다.
enum RecipeApiFailureKind {
  /// 401 — 세션이 없거나 만료됐다.
  unauthorized,

  /// 502 — 저장 시 재료 추출이 실패해 레시피가 저장되지 않았다.
  extractionFailed,

  /// 404 — 없는 항목(남의 것도 같은 응답이다 — 존재를 노출하지 않는다).
  notFound,

  /// 그 외 전부 — 타임아웃·네트워크·파싱·나머지 상태 코드.
  unavailable,
}

class RecipeApiFailure implements Exception {
  const RecipeApiFailure(this.kind, [this.detail]);

  final RecipeApiFailureKind kind;
  final String? detail;

  @override
  String toString() =>
      'RecipeApiFailure(${kind.name}${detail == null ? '' : ', $detail'})';
}

/// 서버 레시피 북 CRUD + 이전(bulk 가져오기). 응답은 snake_case RecipeResponse
/// `{id, url, title, ingredients, created_at}`이고 created_at은 버린다 — 앱이 쓸 곳이 없다.
class ServerRecipeRepository {
  ServerRecipeRepository({
    required this._baseUrl,
    required this._sessionToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String _baseUrl;
  final String _sessionToken;
  final http.Client _client;

  /// GET /api/v1/recipes — 서버가 삽입순으로 준 순서를 그대로 유지한다.
  Future<List<Recipe>> fetchAll() async {
    final response = await _send(
      (headers) =>
          _client.get(Uri.parse('$_baseUrl/api/v1/recipes'), headers: headers),
    );
    _ensureStatus(response, 200);
    return _parseRecipeList(response);
  }

  /// POST /api/v1/recipes → 201. 재료 추출은 서버가 저장 시 1회 수행한다 —
  /// 본문에 ingredients를 실으면 422다(extra=forbid).
  Future<Recipe> create({required String url, required String title}) async {
    final response = await _send(
      (headers) => _client.post(
        Uri.parse('$_baseUrl/api/v1/recipes'),
        headers: headers,
        body: jsonEncode({'url': url, 'title': title}),
      ),
    );
    _ensureStatus(response, 201);
    return Recipe.fromJson(_parseObject(response));
  }

  /// PATCH /api/v1/recipes/{id} → 200. url은 불변이라 ingredients만 보낸다.
  Future<Recipe> patchIngredients({
    required String id,
    required List<String> ingredients,
  }) async {
    final response = await _send(
      (headers) => _client.patch(
        Uri.parse('$_baseUrl/api/v1/recipes/$id'),
        headers: headers,
        body: jsonEncode({'ingredients': ingredients}),
      ),
    );
    _ensureStatus(response, 200);
    return Recipe.fromJson(_parseObject(response));
  }

  /// DELETE /api/v1/recipes/{id} → 204.
  Future<void> delete(String id) async {
    final response = await _send(
      (headers) => _client.delete(
        Uri.parse('$_baseUrl/api/v1/recipes/$id'),
        headers: headers,
      ),
    );
    _ensureStatus(response, 204);
  }

  /// POST /api/v1/migration/recipes → 201. 재추출 없는 원자적 등록 — 전량 성공 또는 전량 실패(#104).
  ///
  /// 서버 스키마가 additionalProperties:false라 id·created_at이 실리면 422다 —
  /// toJson()을 재사용하지 않고 3필드만 명시 직렬화한다. 빈 리스트는 호출부 책임이다(서버가 422를 낸다).
  Future<List<Recipe>> importBulk(List<Recipe> recipes) async {
    assert(recipes.isNotEmpty, '빈 가져오기는 호출부에서 걸러야 한다 — 서버는 422를 낸다');
    final response = await _send(
      (headers) => _client.post(
        Uri.parse('$_baseUrl/api/v1/migration/recipes'),
        headers: headers,
        body: jsonEncode({
          'recipes': [
            for (final r in recipes)
              {'url': r.url, 'title': r.title, 'ingredients': r.ingredients},
          ],
        }),
      ),
    );
    _ensureStatus(response, 201);
    return _parseRecipeList(response);
  }

  /// 전송 실패(타임아웃·네트워크)를 unavailable로 정규화한다 — 상태 코드 매핑은 [_ensureStatus]가 한다.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    try {
      return await request({
        'content-type': 'application/json',
        'authorization': 'Bearer $_sessionToken',
      }).timeout(_timeout);
    } on Exception catch (e) {
      // TimeoutException도 Exception이다 — 타임아웃·네트워크 모두 같은 unavailable로 간다.
      throw RecipeApiFailure(RecipeApiFailureKind.unavailable, e.toString());
    }
  }

  /// 401·404·502만 고유 의미가 있다 — 나머지 비성공(400·422·5xx)은 전부 unavailable이다.
  void _ensureStatus(http.Response response, int expected) {
    final status = response.statusCode;
    if (status == expected) return;
    throw switch (status) {
      401 => const RecipeApiFailure(RecipeApiFailureKind.unauthorized),
      404 => const RecipeApiFailure(RecipeApiFailureKind.notFound),
      502 => const RecipeApiFailure(RecipeApiFailureKind.extractionFailed),
      _ => RecipeApiFailure(RecipeApiFailureKind.unavailable, 'HTTP $status'),
    };
  }

  Map<String, Object?> _parseObject(http.Response response) {
    try {
      return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, Object?>();
    } on FormatException catch (e) {
      throw RecipeApiFailure(
        RecipeApiFailureKind.unavailable,
        '응답 파싱 실패: ${e.message}',
      );
    }
  }

  List<Recipe> _parseRecipeList(http.Response response) {
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes)) as List<Object?>;
      return [
        for (final item in raw)
          Recipe.fromJson((item! as Map).cast<String, Object?>()),
      ];
    } on FormatException catch (e) {
      throw RecipeApiFailure(
        RecipeApiFailureKind.unavailable,
        '응답 파싱 실패: ${e.message}',
      );
    }
  }
}
