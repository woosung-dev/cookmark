// 768px 리사이즈 — 업로드 지연을 깎는 레버가 실제로 동작하는지(스펙 #13 · #14 AC).
import 'dart:typed_data';

import 'package:cookmark/image/resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 지정한 크기의 JPEG을 만든다 — 균일한 색이면 압축이 과해 디코더가 게을러질 수 있어 무늬를 넣는다.
Uint8List _jpegOf({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return img.encodeJpg(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('큰 사진은 가로 768px로 줄어든다', () async {
    final resized = await resizeForRecognition(
      _jpegOf(width: 1600, height: 1200),
    );
    expect(resized.width, recognitionWidth);
  });

  test('가로세로비가 유지된다 — 4:3이 4:3으로', () async {
    final resized = await resizeForRecognition(
      _jpegOf(width: 1600, height: 1200),
    );
    expect(resized.height, closeTo(768 * 3 / 4, 1));
  });

  test('세로 사진도 가로 기준으로 줄어든다', () async {
    final resized = await resizeForRecognition(
      _jpegOf(width: 3000, height: 4000),
    );
    expect(resized.width, recognitionWidth);
    expect(resized.height, closeTo(768 * 4 / 3, 1));
  });

  test('768px보다 작은 사진은 확대하지 않는다 — 용량만 늘고 인식엔 보탬이 없다', () async {
    final resized = await resizeForRecognition(
      _jpegOf(width: 400, height: 300),
    );
    expect(resized.width, 400);
    expect(resized.height, 300);
  });

  test('768px 정각은 그대로 둔다', () async {
    final resized = await resizeForRecognition(
      _jpegOf(width: 768, height: 512),
    );
    expect(resized.width, 768);
  });

  test('결과는 원본보다 작은 JPEG이다', () async {
    final original = _jpegOf(width: 2400, height: 1800);
    final resized = await resizeForRecognition(original);
    expect(resized.bytes.length, lessThan(original.length));
    // JPEG SOI 매직 — 프록시가 image/jpeg로 보낼 수 있어야 한다.
    expect(resized.bytes.sublist(0, 2), [0xFF, 0xD8]);
  });
}
