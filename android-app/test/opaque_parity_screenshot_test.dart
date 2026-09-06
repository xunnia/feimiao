import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

import '../tooling/opaque_parity_screenshot.dart';

void main() {
  test('composites transparent pixels onto the warm page gradient', () {
    final source = image_lib.Image(width: 2, height: 2, numChannels: 4);
    source.setPixelRgba(0, 0, 0, 0, 0, 0);
    source.setPixelRgba(1, 0, 255, 0, 0, 255);
    source.setPixelRgba(0, 1, 0, 0, 255, 128);
    source.setPixelRgba(1, 1, 255, 255, 255, 255);

    final result = image_lib.decodePng(
      Uint8List.fromList(
          makeOpaqueParityScreenshot(image_lib.encodePng(source))),
    );

    expect(result, isNotNull);
    expect(result!.numChannels, 3);
    expect(result.getPixel(0, 0).a, 255);
    expect(result.getPixel(0, 0).r, 250);
    expect(result.getPixel(0, 0).g, 224);
    expect(result.getPixel(0, 0).b, 176);
    expect(result.getPixel(1, 0).r, 255);
    expect(result.getPixel(1, 0).g, 0);
    expect(result.getPixel(1, 0).b, 0);
  });

  test('keeps already opaque screenshots byte-for-byte unchanged', () {
    final source = image_lib.Image(width: 1, height: 1, numChannels: 3);
    source.setPixelRgb(0, 0, 12, 34, 56);
    final bytes = image_lib.encodePng(source);

    expect(makeOpaqueParityScreenshot(bytes), orderedEquals(bytes));
  });
}
