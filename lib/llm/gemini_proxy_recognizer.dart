// 실제 인식 구현 — 서버리스 프록시(/api/recognize)를 호출한다. API 키는 클라이언트에 없다.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/ingredient.dart';
import 'recognizer.dart';

/// 앱과 분리된 서버리스 프록시를 경유해 재료를 인식한다(ADR-0005).
/// 프록시가 API 키를 쥐고 Gemini를 호출한 뒤 재료 배열과 사용량을 회신한다.
class GeminiProxyRecognizer implements IngredientRecognizer {
  GeminiProxyRecognizer({
    required this.client,
    required this.endpoint,
    this.timeout = const Duration(seconds: 30),
  });

  /// 배포된 앱이 쓰는 기본 구성 — 프록시는 같은 오리진의 `/api/recognize`다.
  factory GeminiProxyRecognizer.forApp({http.Client? client}) =>
      GeminiProxyRecognizer(
        client: client ?? http.Client(),
        endpoint: Uri.parse('/api/recognize'),
      );

  final http.Client client;
  final Uri endpoint;

  /// G1 #8의 단계식 문구가 30초에서 타임아웃을 알리므로 경계도 30초로 맞춘다.
  final Duration timeout;

  @override
  Future<RecognitionResult> recognize(Uint8List imageBytes) async {
    final http.Response response;
    try {
      response = await client
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'imageBase64': base64Encode(imageBytes)}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const RecognitionException(FailureReason.timeout);
    } catch (e) {
      throw RecognitionException(FailureReason.server, '$e');
    }

    if (response.statusCode != 200) {
      throw RecognitionException(FailureReason.server, 'HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      // 게이트웨이 HTML 등 JSON이 아닌 응답 — 파싱 실패로 앱이 죽지 않게 흡수한다.
      throw RecognitionException(FailureReason.server, '응답을 읽지 못했습니다');
    }

    final ingredients = (body['ingredients'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(
          (e) => Ingredient.fromRecognition(
            name: e['name'] as String,
            confidence: Confidence.parse(e['confidence'] as String?),
          ),
        )
        .toList();

    if (ingredients.isEmpty) {
      throw const RecognitionException(FailureReason.empty);
    }

    return RecognitionResult(
      ingredients: ingredients,
      usage: RecognitionUsage.fromJson(
        Map<String, dynamic>.from(body['usage'] as Map? ?? const {}),
      ),
    );
  }
}
