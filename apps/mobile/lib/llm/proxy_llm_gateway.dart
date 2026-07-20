// 운영용 LLM 경계 구현 — 서버리스 프록시를 호출한다. API 키는 클라이언트에 없다(스펙 #13).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/ingredient.dart';
import '../domain/recipe.dart';
import '../domain/suggestion.dart';
import 'llm_gateway.dart';

/// 프록시 함수의 베이스 URL. 웹 빌드는 같은 오리진이므로 기본값이 빈 문자열이다.
const _baseUrl = String.fromEnvironment('COOKMARK_API_BASE');

/// 인식 호출의 상한 — 30초를 넘기면 사용자에게 타임아웃 인라인 카드를 띄운다(G1 #8).
const recognizeTimeout = Duration(seconds: 30);

class ProxyLlmGateway implements LlmGateway {
  ProxyLlmGateway({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<RecognitionResult> recognize(
    Uint8List jpegBytes,
  ) => normalizeLlmFailures(() async {
    final body = await _post('/api/recognize', {
      'imageBase64': base64Encode(jpegBytes),
    });

    if (body['lowQuality'] == true) {
      throw const LlmFailure(LlmFailureKind.lowQuality);
    }

    final raw = (body['ingredients'] as List<Object?>? ?? const []);
    final ingredients = <Ingredient>[
      for (final item in raw) ?_parse((item! as Map).cast<String, Object?>()),
    ];

    if (ingredients.isEmpty) throw const LlmFailure(LlmFailureKind.empty);

    return RecognitionResult(
      ingredients: ingredients,
      usage: LlmUsage.fromJson((body['usage']! as Map).cast<String, Object?>()),
    );
  });

  /// [url]은 무시한다 — 파일럿 프록시는 제목 기반 그대로다(#123, 행동 0 변화).
  @override
  Future<ExtractionResult> extractIngredients(String title, {String? url}) =>
      normalizeLlmFailures(() async {
        final body = await _post('/api/extract', {'title': title});

        final raw = body['ingredients'] as List<Object?>? ?? const [];
        final ingredients = <String>[
          for (final item in raw)
            if ((item as String?)?.trim() case final name? when name.isNotEmpty)
              name,
        ];

        if (ingredients.isEmpty) throw const LlmFailure(LlmFailureKind.empty);

        return ExtractionResult(
          ingredients: ingredients,
          usage: LlmUsage.fromJson(
            (body['usage']! as Map).cast<String, Object?>(),
          ),
        );
      });

  @override
  Future<MatchResult> match({
    required List<String> ingredients,
    required List<Recipe> recipes,
  }) => normalizeLlmFailures(() async {
    final body = await _post('/api/match', {
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

    return MatchResult(
      suggestions: suggestions,
      usage: LlmUsage.fromJson((body['usage']! as Map).cast<String, Object?>()),
    );
  });

  /// 메뉴명·출처가 없으면 카드로 세울 수 없다 — 버린다.
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

    // 저장 제안의 URL은 LLM이 아니라 우리 레시피 북에서 온다 — 모델이 URL을 지어내게 두지 않는다.
    final url = source == SuggestionSource.saved
        ? recipes.where((r) => r.title == menu).firstOrNull?.url
        : null;

    return Suggestion(
      menu: menu,
      // 저장이라 했는데 레시피 북에 없으면 생성으로 본다 — 출처 라벨이 거짓이면 신뢰가 깨진다.
      source: source == SuggestionSource.saved && url == null
          ? SuggestionSource.generated
          : source,
      missing: missing,
      reason: (json['reason'] as String?)?.trim() ?? '',
      recipeUrl: url,
    );
  }

  /// 프록시 호출의 공통부 — 타임아웃·HTTP 오류·파싱 실패를 전부 LlmFailure로 정규화한다.
  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(recognizeTimeout);
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

  /// 이름이 비었거나 confidence가 3단 밖이면 버린다 — 모델이 스키마를 벗어나도 화면은 살아야 한다.
  static Ingredient? _parse(Map<String, Object?> json) {
    final name = (json['name'] as String?)?.trim();
    final confidence = Confidence.parse(json['confidence'] as String?);
    if (name == null || name.isEmpty || confidence == null) return null;
    return Ingredient.recognized(name: name, confidence: confidence);
  }
}
