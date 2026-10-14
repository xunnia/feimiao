import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qingji/core/media/ai_image_preparation.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('feimiao_image_prepare_');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<File> file(String name, List<int> bytes) async =>
      File('${temp.path}/$name').writeAsBytes(bytes);

  test('小字截图不重复编码，原图字节和 MIME 不变', () async {
    final image = img.Image(width: 900, height: 180);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(image, 'Invoice 2026-10-04  Total 128.56',
        font: img.arial14, x: 8, y: 40, color: img.ColorRgb8(0, 0, 0));
    final original = Uint8List.fromList(img.encodePng(image));
    final source = await file('wrong-extension.jpg', original);
    final result = await AiImagePreparation.prepare(source.path);
    expect(result.bytes, original);
    expect(result.mimeType, 'image/png');
    expect(await source.readAsBytes(), original);
    expect(result.path, source.path);
  });

  test('大截图保留整幅内容和透明度，副本缓存和重试字节稳定', () async {
    final image = img.Image(width: 4200, height: 120, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 120));
    img.drawString(image, 'FIRST Invoice 128.56 LAST',
        font: img.arial24, x: 8, y: 30, color: img.ColorRgba8(0, 0, 0, 255));
    image.setPixelRgba(4199, 119, 25, 90, 200, 255);
    final source = await file('large.png', img.encodePng(image));
    final hash = sha256.convert(await source.readAsBytes());
    final first = await AiImagePreparation.prepare(source.path);
    final modified = await File(first.path).lastModified();
    final second = await AiImagePreparation.prepare(source.path);
    expect(first.path, isNot(source.path));
    expect(first.bytes, second.bytes);
    expect(await File(second.path).lastModified(), modified);
    expect(sha256.convert(await source.readAsBytes()), hash);
    final resized = img.decodeImage(first.bytes)!;
    expect(resized.width, 4096);
    expect(resized.height, closeTo(120 * 4096 / 4200, 1));
    expect(resized.hasAlpha, isTrue);
    expect(resized.getPixel(0, 0).a, closeTo(120, 1));
    expect(first.mimeType, 'image/png');
  });

  test('同图片并发准备合并，损坏副本重建且不动原图', () async {
    final image = img.Image(width: 3100, height: 80);
    final source = await file('photo.jpg', img.encodeJpg(image, quality: 100));
    final before = await source.readAsBytes();
    final results = await Future.wait([
      AiImagePreparation.prepare(source.path),
      AiImagePreparation.prepare(source.path)
    ]);
    expect(results[0].bytes, results[1].bytes);
    await File(results[0].path).writeAsBytes([1, 2, 3]);
    final repaired = await AiImagePreparation.prepare(source.path);
    expect(repaired.bytes, results[0].bytes);
    expect(await source.readAsBytes(), before);
  });

  test('内容更新后生成新副本，不复用旧内容', () async {
    final source = await file(
        'photo.jpg', img.encodeJpg(img.Image(width: 3100, height: 60)));
    final first = await AiImagePreparation.prepare(source.path);
    final image = img.Image(width: 3100, height: 60);
    img.fill(image, color: img.ColorRgb8(190, 130, 40));
    await source.writeAsBytes(img.encodeJpg(image));
    final second = await AiImagePreparation.prepare(source.path);
    expect(second.path, isNot(first.path));
    expect(second.bytes, isNot(first.bytes));
  });

  test('照片副本减少上传字节，不放大或裁切', () async {
    final image = img.Image(width: 600, height: 400);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes = img.encodeJpg(image, quality: 100);
    final original = [...bytes, ...List.filled(1024 * 1024, 0)];
    final source = await file('photo-large-bytes.jpg', original);
    final prepared = await AiImagePreparation.prepare(source.path);
    expect(prepared.bytes.length, lessThan(original.length));
    final decoded = img.decodeJpg(prepared.bytes)!;
    expect(decoded.width, image.width);
    expect(decoded.height, image.height);
    expect(await source.readAsBytes(), original);
    final prior = img.decodeJpg(bytes)!;
    var error = 0.0;
    for (var y = 0; y < 400; y += 8) {
      for (var x = 0; x < 600; x += 8) {
        final a = decoded.getPixel(x, y), b = prior.getPixel(x, y);
        error += (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      }
    }
    expect(error / (50 * 75 * 3), lessThan(4));
  });

  test('无效、空和缺失图片不发送', () async {
    for (final data in <List<int>>[
      [],
      [1, 2, 3]
    ]) {
      final source = await file('invalid.png', data);
      await expectLater(
          AiImagePreparation.prepare(source.path), throwsFormatException);
    }
    await expectLater(AiImagePreparation.prepare('${temp.path}/missing.png'),
        throwsFormatException);
  });
}
