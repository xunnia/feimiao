import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;

/// Converts the transparent pixels produced by Flutter's Android screenshot
/// surface to the same warm page gradient used by the app.
///
/// The integration_test Android surface can return transparent pixels for a
/// transparent Scaffold or modal barrier. PNG viewers commonly render those
/// pixels as black, which makes a valid page look broken in CI artifacts.
List<int> makeOpaqueParityScreenshot(List<int> bytes) {
  final decoded = image_lib.decodePng(Uint8List.fromList(bytes));
  if (decoded == null) return bytes;

  var hasTransparency = false;
  for (final pixel in decoded) {
    if (pixel.a < 255) {
      hasTransparency = true;
      break;
    }
  }
  if (!hasTransparency) return bytes;

  final output = image_lib.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 3,
  );
  final denominator = decoded.height > 1 ? decoded.height - 1 : 1;
  for (var y = 0; y < decoded.height; y++) {
    // AppColors.warmBackground keeps the bottom color after 85% of the page.
    final progress = (y / denominator / 0.85).clamp(0.0, 1.0).toDouble();
    final background = <double>[
      _lerp(250, 255, progress),
      _lerp(224, 253, progress),
      _lerp(176, 247, progress),
    ];
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      final alpha = (pixel.a.toDouble() / 255).clamp(0.0, 1.0);
      output.setPixelRgb(
        x,
        y,
        _blend(pixel.r.toDouble(), background[0], alpha),
        _blend(pixel.g.toDouble(), background[1], alpha),
        _blend(pixel.b.toDouble(), background[2], alpha),
      );
    }
  }
  return image_lib.encodePng(output, level: 6);
}

double _lerp(double start, double end, double progress) =>
    start + (end - start) * progress;

int _blend(double source, double background, double alpha) =>
    (source * alpha + background * (1 - alpha)).round().clamp(0, 255);
