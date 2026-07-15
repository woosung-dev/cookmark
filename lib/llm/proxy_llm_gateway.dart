// 운영용 LLM 경계 구현 — 서버리스 프록시를 호출한다. API 키는 클라이언트에 없다(스펙 #13).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/ingredient.dart';
import 'llm_gateway.dart';

/// 프록시 함수의 베이스 URL. 웹 빌드는 같은 오리진이므로 기본값이 빈 문자열이다.
const _baseUrl = String.fromEnvironment('COOKMARK_API_BASE');

/// 인식 호출의 상한 — 30초를 넘기면 사용자에게 타임아웃 인라인 카드를 띄운다(G1 #8).
const recognizeTimeout = Duration(seconds: 30);

class ProxyLlmGateway implements LlmGateway {
  ProxyLlmGateway({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<RecognitionResult> recognize(Uint8List jpegBytes) async {
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
  }

  @override
  Future<ExtractionResult> extractIngredients(String title) async {
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
      usage: LlmUsage.fromJson((body['usage']! as Map).cast<String, Object?>()),
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
