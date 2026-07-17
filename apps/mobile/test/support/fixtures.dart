// 테스트가 공유하는 fixture — 진짜 JPEG 바이트가 필요한 곳(리사이즈·업로드 관통)에 쓴다.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 지정한 크기의 JPEG. 균일한 색이면 압축이 과해지므로 무늬를 넣는다.
Uint8List jpegOf({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return img.encodeJpg(image);
}

/// 냉장고 사진 한 장에 해당하는 기본 fixture.
Uint8List fridgePhoto() => jpegOf(width: 1600, height: 1200);
