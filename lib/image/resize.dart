// 냉장고 사진을 인식 호출 전에 768px로 줄인다 — Gemini는 해상도와 무관하게 이미지 1,064토큰 고정이므로
// 이건 원가 레버가 아니라 지연 레버다(스펙 #13, P1 실측 1.9s).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 인식에 보내는 가로 폭.
const recognitionWidth = 768;

/// 지연이 목적이므로 화질은 인식에 지장 없는 선까지만 떨어뜨린다.
const _jpegQuality = 85;

class ResizedPhoto {
  const ResizedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// 디코드·축소는 플랫폼 디코더(dart:ui)가 하고, JPEG 재인코딩만 image 패키지가 한다.
/// 순수 Dart로 디코드하면 12MP 사진에서 수 초가 날아가는데, 그건 이 리사이즈가 없애려던 지연이다.
Future<ResizedPhoto> resizeForRecognition(Uint8List original) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(original);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    // 원본이 이미 768px 이하면 확대하지 않는다 — 확대는 용량만 늘리고 인식엔 보탬이 없다.
    getTargetSize: (intrinsicWidth, intrinsicHeight) =>
        intrinsicWidth <= recognitionWidth
        ? const ui.TargetImageSize()
        : const ui.TargetImageSize(width: recognitionWidth),
  );

  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      throw StateError('사진 디코드 실패 — rawRgba를 얻지 못했다');
    }
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgba.buffer,
        numChannels: 4,
      ),
      quality: _jpegQuality,
    );
    return ResizedPhoto(bytes: jpeg, width: image.width, height: image.height);
  } finally {
    image.dispose();
    codec.dispose();
  }
}
