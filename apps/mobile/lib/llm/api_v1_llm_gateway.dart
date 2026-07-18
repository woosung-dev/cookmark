// 로컬 통합 스파이크 전용 LLM 경계 — apps/api FastAPI(/api/v1/llm/*)에 Bearer 세션으로 붙는다.
//
// ProxyLlmGateway(루트 .mjs 프록시)와 다른 점 세 가지 — (1) 경로가 /api/v1/llm/*, (2) 세션 필수라
// Authorization: Bearer 를 싣는다, (3) FastAPI 응답이 snake_case(low_quality·prompt_tokens)다.
// 파일럿 빌드(main.dart)엔 들어가지 않는다 — main_api_spike.dart 로만 조립된다.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/ingredient.dart';
import '../domain/recipe.dart';
import '../domain/suggestion.dart';
import 'llm_gateway.dart';

/// 인식 호출의 상한 — ProxyLlmGateway와 동일(G1 #8).
const _timeout = Duration(seconds: 30);

class ApiV1LlmGateway implements LlmGateway {
  ApiV1LlmGateway({
    required this._baseUrl,
    required this._sessionToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String _baseUrl;
  final String _sessionToken;
  final http.Client _client;

  @override
  Future<RecognitionResult> recognize(Uint8List jpegBytes) async {
    final body = await _post('/api/v1/llm/recognize', {
      'image_base64': base64Encode(jpegBytes),
    });

    if (body['low_quality'] == true) {
      throw const LlmFailure(LlmFailureKind.lowQuality);
    }

    final raw = body['ingredients'] as List<Object?>? ?? const [];
    final ingredients = <Ingredient>[
      for (final item in raw)
        ?_parseIngredient((item! as Map).cast<String, Object?>()),
    ];
    if (ingredients.isEmpty) throw const LlmFailure(LlmFailureKind.empty);

    return RecognitionResult(
      ingredients: ingredients,
      usage: _usage((body['usage']! as Map).cast<String, Object?>()),
    );
  }

  @override
  Future<ExtractionResult> extractIngredients(String title) async {
    final body = await _post('/api/v1/llm/extract', {'title': title});

    final raw = body['ingredients'] as List<Object?>? ?? const [];
    final ingredients = <String>[
      for (final item in raw)
        if ((item as String?)?.trim() case final name? when name.isNotEmpty)
          name,
    ];
    if (ingredients.isEmpty) throw const LlmFailure(LlmFailureKind.empty);

    return ExtractionResult(
      ingredients: ingredients,
      usage: _usage((body['usage']! as Map).cast<String, Object?>()),
    );
  }

  @override
  Future<MatchResult> match({
    required List<String> ingredients,
    required List<Recipe> recipes,
  }) async {
    final body = await _post('/api/v1/llm/match', {
      'ingredients': ingredients,
      'recipes': [
        for (final r in recipes)
          {'title': r.title, 'ingredients': r.ingredients},
      ],
    });

    final raw = body['suggestions'] as List<Object?>? ?? const [];
    final suggestions = <Suggestion>[
      for (final item in raw)
        ?_parseSuggestion((item! as Map).cast<String, Object?>(), recipes),
    ];
    if (suggestions.isEmpty) throw const LlmFailure(LlmFailureKind.empty);

    // 저장 제안은 출처 URL의 og:image를 카드 히어로 사진으로 붙인다(#102). AI 제안은 URL이 없어 건너뛴다.
    final enriched = await Future.wait(
      suggestions.map((s) async {
        final url = s.recipeUrl;
        if (s.source == SuggestionSource.saved && url != null) {
          return s.copyWith(imageUrl: await _fetchOgImage(url));
        }
        return s;
      }),
    );

    return MatchResult(
      suggestions: enriched,
      usage: _usage((body['usage']! as Map).cast<String, Object?>()),
    );
  }

  /// 출처 페이지의 og:image URL. 실패·부재는 조용히 null — 사진이 없으면 틴트로 폴백한다.
  Future<String?> _fetchOgImage(String recipeUrl) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/v1/og-image',
      ).replace(queryParameters: {'url': recipeUrl});
      final response = await _client
          .get(uri, headers: {'authorization': 'Bearer $_sessionToken'})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, Object?>();
      return body['image_url'] as String?;
    } on Exception {
      return null;
    }
  }

  /// 서버가 match_score를 실산출하지만 스파이크는 카드 렌더에 쓰지 않는다 — 무시하고 버린다.
  static Suggestion? _parseSuggestion(
    Map<String, Object?> json,
    List<Recipe> recipes,
  ) {
    final menu = (json['menu'] as String?)?.trim();
    final source = SuggestionSource.parse(json['source'] as String?);
    if (menu == null || menu.isEmpty || source == null) return null;

    final missing = <MissingIngredient>[
      for (final m in json['missing'] as List<Object?>? ?? const [])
        if (((m! as Map).cast<String, Object?>()['name'] as String?)?.trim()
            case final name? when name.isNotEmpty)
          MissingIngredient(
            name: name,
            substitute: (m as Map)['substitute'] as String?,
          ),
    ];

    final url = source == SuggestionSource.saved
        ? recipes.where((r) => r.title == menu).firstOrNull?.url
        : null;

    return Suggestion(
      menu: menu,
      source: source == SuggestionSource.saved && url == null
          ? SuggestionSource.generated
          : source,
      missing: missing,
      reason: (json['reason'] as String?)?.trim() ?? '',
      recipeUrl: url,
    );
  }

  /// FastAPI LLMUsage는 snake_case다 — camelCase를 기대하는 LlmUsage.fromJson을 쓰지 않고 직접 매핑한다.
  static LlmUsage _usage(Map<String, Object?> j) => LlmUsage(
    promptTokens: (j['prompt_tokens']! as num).toInt(),
    outputTokens: (j['output_tokens']! as num).toInt(),
    thoughtTokens: (j['thought_tokens'] as num?)?.toInt() ?? 0,
    imageTokens: (j['image_tokens'] as num?)?.toInt() ?? 0,
    costUsd: (j['cost_usd']! as num).toDouble(),
    model: j['model']! as String,
  );

  static Ingredient? _parseIngredient(Map<String, Object?> json) {
    final name = (json['name'] as String?)?.trim();
    final confidence = Confidence.parse(json['confidence'] as String?);
    if (name == null || name.isEmpty || confidence == null) return null;
    return Ingredient.recognized(name: name, confidence: confidence);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $_sessionToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException catch (e) {
      throw LlmFailure(LlmFailureKind.timeout, e.toString());
    } on Exception catch (e) {
      throw LlmFailure(LlmFailureKind.error, e.toString());
    }

    if (response.statusCode != 200) {
      throw LlmFailure(LlmFailureKind.error, 'HTTP ${response.statusCode}');
    }

    try {
      return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, Object?>();
    } on FormatException catch (e) {
      throw LlmFailure(LlmFailureKind.error, '응답 파싱 실패: ${e.message}');
    }
  }
}
