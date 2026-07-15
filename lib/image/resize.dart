// 전송 전 이미지 리사이즈 — 긴 변 768px 상한(지연 레버, 스펙 #13)
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../llm/recognizer.dart';

/// 인식 호출의 이미지 상한. Gemini는 해상도와 무관하게 이미지당 1,064토큰 고정이라
/// 이 값은 원가가 아니라 업로드·지연을 줄이는 레버다(T1 #6 실측 1.9s).
const recognitionMaxEdge = 768;

/// 긴 변이 [recognitionMaxEdge]를 넘으면 비율을 지켜 줄인다. 이미 작으면 그대로 둔다
/// — 확대는 지연만 늘리고 인식에 보탬이 없다.
///
/// 디코드에 실패하면 [RecognitionException]([FailureReason.lowQuality])을 던진다.
Uint8List resizeForRecognition(List<int> bytes) {
  // decodeImage는 형식을 못 맞추면 null을 주기도 하고, 손상된 헤더를 만나면
  // 디코더 내부에서 RangeError를 던지기도 한다(Exception이 아니라 Error다).
  // 둘 다 사용자에겐 "사진을 못 읽었다" 하나이므로 저품질 실패로 모은다.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(Uint8List.fromList(bytes));
  } catch (e) {
    throw RecognitionException(FailureReason.lowQuality, '이미지를 읽지 못했습니다: $e');
  }
  if (decoded == null) {
    throw const RecognitionException(FailureReason.lowQuality, '이미지를 읽지 못했습니다');
  }

  final longEdge = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  if (longEdge <= recognitionMaxEdge) return img.encodeJpg(decoded);

  final resized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? recognitionMaxEdge : null,
    height: decoded.height > decoded.width ? recognitionMaxEdge : null,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(resized, quality: 85);
}
