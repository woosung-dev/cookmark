// 이미지 리사이즈 유닛 — 768px 상한(지연 레버) 검증
import 'dart:typed_data';

import 'package:cookmark/image/resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List encodedImage(int w, int h) =>
      img.encodeJpg(img.Image(width: w, height: h));

  img.Image decode(Uint8List bytes) => img.decodeImage(bytes)!;

  group('768px 리사이즈 — Gemini는 해상도 무관 1,064토큰 고정이므로 원가가 아닌 지연 레버', () {
    test('가로가 긴 큰 사진은 긴 변이 768이 된다', () {
      final out = decode(resizeForRecognition(encodedImage(3024, 2016)));
      expect(out.width, 768);
      expect(out.height, 512); // 3:2 비율 보존
    });

    test('세로가 긴 큰 사진은 긴 변이 768이 된다 — 냉장고 사진의 기본 방향', () {
      final out = decode(resizeForRecognition(encodedImage(2016, 4032)));
      expect(out.height, 768);
      expect(out.width, 384);
    });

    test('768 이하 사진은 확대하지 않는다', () {
      final out = decode(resizeForRecognition(encodedImage(640, 480)));
      expect(out.width, 640);
      expect(out.height, 480);
    });

    test('정확히 768인 사진은 그대로 둔다', () {
      final out = decode(resizeForRecognition(encodedImage(768, 768)));
      expect(out.width, 768);
      expect(out.height, 768);
    });

    test('디코드할 수 없는 바이트는 ImageDecodeException으로 던진다 — 디코더 내부 Error도 흡수', () {
      expect(
        () => resizeForRecognition([0, 1, 2, 3]),
        throwsA(isA<ImageDecodeException>()),
      );
    });

    test('빈 바이트도 ImageDecodeException이다', () {
      expect(
        () => resizeForRecognition(const []),
        throwsA(isA<ImageDecodeException>()),
      );
    });
  });
}
