import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'chat_attachment.dart';

class PreparedAiImage {
  final Uint8List bytes;
  final String mimeType;
  final String path;
  const PreparedAiImage(this.bytes, this.mimeType, this.path);
}

/// Original attachments remain the preview/history source. Network copies are
/// content-addressed, versioned and verified before reuse, including retries.
abstract final class AiImagePreparation {
  static final _pending = <String, Future<PreparedAiImage>>{};
  static Future<void> _tail = Future.value();

  static Future<PreparedAiImage> prepare(String path) {
    return _pending.putIfAbsent(path, () async {
      try {
        final work = _tail.then((_) => Isolate.run(() => _prepareImage(path)));
        _tail = work.then<void>((_) {},
            onError: (Object error, StackTrace stack) {});
        return await work;
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('图片无法准备，请重新选择或转换图片格式');
      } finally {
        _pending.remove(path);
      }
    });
  }

  static Future<void> prepareAll(Iterable<ChatAttachment> attachments) async {
    for (final attachment in attachments.where((item) => item.isImage)) {
      await prepare(attachment.path);
    }
  }
}

PreparedAiImage _prepareImage(String path) {
  final source = File(path);
  if (!source.existsSync()) throw const FormatException('图片已不存在，请重新选择');
  final length = source.lengthSync();
  if (length < 12 || length > 20 * 1024 * 1024) {
    throw const FormatException('图片为空或超过 20 MB');
  }
  final original = source.readAsBytesSync();
  final decoder = img.findDecoderForData(original);
  final info = decoder?.startDecode(original);
  if (info == null) {
    throw const FormatException('无法读取图片格式，请转为 JPEG、PNG 或 WebP 后再添加');
  }
  // Check dimensions before allocating decoded pixels; compressed size alone
  // does not protect against a decompression bomb.
  if (info.width <= 0 ||
      info.height <= 0 ||
      info.width > 20000 ||
      info.height > 20000 ||
      info.width * info.height > 24 * 1024 * 1024) {
    throw const FormatException('图片像素过大，请先缩小图片后再添加');
  }
  final originalMime = decoder is img.PngDecoder
      ? 'image/png'
      : decoder is img.JpegDecoder
          ? 'image/jpeg'
          : decoder is img.WebPDecoder
              ? 'image/webp'
              : decoder is img.GifDecoder
                  ? 'image/gif'
                  : null;
  if (originalMime == null) {
    throw const FormatException('此图片格式暂不支持，请转换为 JPEG、PNG 或 WebP');
  }
  // Never flatten an animation or repeatedly re-encode a small image. PNG
  // screenshots keep lossless encoding and a larger text-friendly edge limit.
  final edge = originalMime == 'image/png' ? 4096 : 3072;
  final needsResize = info.width > edge || info.height > edge;
  if (info.numFrames > 1 ||
      (!needsResize &&
          (length <= 1024 * 1024 || originalMime != 'image/jpeg'))) {
    return PreparedAiImage(original, originalMime, path);
  }
  final key = sha256
      .convert(utf8.encode('feimiao-image-v1:${sha256.convert(original)}'))
      .toString();
  final directory = Directory(p.join(source.parent.path, '.ai_prepared_v1'));
  final manifest = File(p.join(directory.path, '$key.json'));
  if (manifest.existsSync()) {
    try {
      final record =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      final cached =
          File(p.join(directory.path, p.basename(record['file'] as String)));
      final bytes = cached.readAsBytesSync();
      if (bytes.length == record['bytes'] &&
          sha256.convert(bytes).toString() == record['sha256']) {
        return PreparedAiImage(bytes, record['mime'] as String, cached.path);
      }
    } catch (_) {
      /* Rebuild only a corrupt/unreadable cache, never the original. */
    }
  }
  var image = decoder!.decodeFrame(0);
  if (image == null) throw const FormatException('图片解码失败，请重新选择');
  image = img.bakeOrientation(image);
  if (needsResize) {
    image = img.copyResize(image,
        width: image.width >= image.height ? edge : null,
        height: image.height > image.width ? edge : null,
        interpolation: img.Interpolation.average);
  }
  final mime = originalMime == 'image/png' || image.hasAlpha
      ? 'image/png'
      : 'image/jpeg';
  final encoded = mime == 'image/png'
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: 94);
  if (encoded.length > 20 * 1024 * 1024) {
    throw const FormatException('图片准备后仍超过 20 MB，请调整图片后再添加');
  }
  if (!needsResize && encoded.length >= original.length) {
    return PreparedAiImage(original, originalMime, path);
  }
  directory.createSync(recursive: true);
  final filename = '$key.${mime == 'image/png' ? 'png' : 'jpg'}';
  final target = File(p.join(directory.path, filename));
  final temporary = File('${target.path}.pending');
  temporary.writeAsBytesSync(encoded, flush: true);
  temporary.renameSync(target.path);
  final pendingManifest = File('${manifest.path}.pending');
  pendingManifest.writeAsStringSync(
      jsonEncode({
        'file': filename,
        'mime': mime,
        'bytes': encoded.length,
        'sha256': sha256.convert(encoded).toString(),
      }),
      flush: true);
  pendingManifest.renameSync(manifest.path);
  return PreparedAiImage(encoded, mime, target.path);
}
