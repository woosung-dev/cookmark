// 서버 레시피 북(/api/v1/recipes·/api/v1/migration/recipes)의 유일한 HTTP 경계 — 컷오버 #121.
//
// ApiV1LlmGateway와 같은 관용구(Bearer 세션·snake_case·타임아웃 정규화)지만 독립 구현이다 —
// LLM seam과 레시피 북 경계는 서로 다른 seam이라 실패 타입도 따로 간다(RecipeApiFailure).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/device_session.dart';
import '../domain/recipe.dart';

/// 상한 30초 — 서버 create가 내부에서 LLM extract를 1회 돌므로 G1 #8의 인식 상한을 그대로 쓴다.
const _timeout = Duration(seconds: 30);

/// 서버 레시피 북 호출이 실패한 이유 — UI는 이 4종만 분기한다.
enum RecipeApiFailureKind {
  /// 401 — 세션이 없거나 만료됐다.
  unauthorized,

  /// **create의** 502 — 저장 시 재료 추출이 실패해 레시피가 저장되지 않았다.
  /// 다른 호출의 502는 인프라 502라 [unavailable]로 간다(#127, [_ensureStatus] 참조).
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
    required this._session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String _baseUrl;
  final DeviceSession _session;
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
    // 502가 "추출 실패=미저장"을 뜻하는 유일한 호출이다(#127) — 다른 넷은 인프라 502다.
    _ensureStatus(response, 201, extractionFailedOn502: true);
    return _parseObject(response);
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
    return _parseObject(response);
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
  ///
  /// 토큰을 싣고 401이면 재등록 후 1회 재전송하는 것은 [sendWithDeviceSession]이 한다(#168) —
  /// 그래서 [_ensureStatus]의 401은 **재등록마저 실패한 401**만 뜻하고, 그때 화면에 뜨는
  /// "접속 정보가 유효하지 않아요"가 정확한 문구가 된다.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    try {
      return await sendWithDeviceSession(
        _session,
        (token) => request({
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        }).timeout(_timeout),
      );
    } on DeviceSessionFailure catch (e) {
      // 등록 자체가 안 된다. **unauthorized가 아니라 unavailable이다** — 이 한 값이 등록 키 거부
      // (403)뿐 아니라 네트워크·타임아웃·응답 형식 불일치까지 덮는데, 앱은 그 넷을 못 가른다.
      // unauthorized 문구("접속 정보가 유효하지 않아요")로 내보내면 서버에 못 닿은 것을 자격증명
      // 문제로 오인시킨다 — 스펙 #161 §G가 가르라고 한 그 두 가지를 도로 뭉치는 셈이다(#166).
      // 진짜 401(재등록한 토큰으로도 거부)은 아래 _ensureStatus가 여전히 unauthorized로 낸다.
      throw RecipeApiFailure(RecipeApiFailureKind.unavailable, e.toString());
    } on Exception catch (e) {
      // TimeoutException도 Exception이다 — 타임아웃·네트워크 모두 같은 unavailable로 간다.
      throw RecipeApiFailure(RecipeApiFailureKind.unavailable, e.toString());
    }
  }

  /// 401·404만 전 엔드포인트 공통이다 — 나머지 비성공(400·422·5xx)은 전부 unavailable이다.
  ///
  /// **502는 create에서만 고유 의미를 가진다**([extractionFailedOn502], #127). 서버에서 502를
  /// 내는 recipes 라우트는 `POST /recipes` 하나뿐이고(추출 사다리 끝의 LLM 자체 다운), GET·PATCH·
  /// DELETE는 502를 내지 않으며 bulk 가져오기 실패는 500이다. 그러므로 그 넷에서 온 502는 인프라
  /// 502(Cloud Run bad gateway)이고, extractionFailed로 접으면 화면에 "재료를 알아내지 못해
  /// 저장하지 못했어요"가 떠 **서버 장애를 사용자가 넣은 URL 탓으로 읽히게** 한다 —
  /// 스펙 #161 §G가 닫으려던 인지 경로 구멍이 거기서 다시 열린다(#166과 같은 병리).
  void _ensureStatus(
    http.Response response,
    int expected, {
    bool extractionFailedOn502 = false,
  }) {
    final status = response.statusCode;
    if (status == expected) return;
    throw switch (status) {
      401 => const RecipeApiFailure(RecipeApiFailureKind.unauthorized),
      404 => const RecipeApiFailure(RecipeApiFailureKind.notFound),
      502 when extractionFailedOn502 => const RecipeApiFailure(
        RecipeApiFailureKind.extractionFailed,
      ),
      _ => RecipeApiFailure(RecipeApiFailureKind.unavailable, 'HTTP $status'),
    };
  }

  // 200인데 형식이 다른 본문의 TypeError(Error라 on Exception도 못 잡는다)가 이탈하면
  // hydrate가 loading에 고착된다(#25 arm을 죽인 결함 계열) — 두 파서 모두 unavailable로 정규화한다.
  // Recipe.fromJson의 캐스트 실패도 잡히도록 fromJson 호출을 try 범위 안에 둔다.

  Recipe _parseObject(http.Response response) {
    try {
      return Recipe.fromJson(
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, Object?>(),
      );
    } on FormatException catch (e) {
      throw RecipeApiFailure(
        RecipeApiFailureKind.unavailable,
        '응답 파싱 실패: ${e.message}',
      );
    } on TypeError catch (e) {
      throw RecipeApiFailure(RecipeApiFailureKind.unavailable, '응답 형식 불일치: $e');
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
    } on TypeError catch (e) {
      throw RecipeApiFailure(RecipeApiFailureKind.unavailable, '응답 형식 불일치: $e');
    }
  }
}
