import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as path;

class AssetMediaFiles {
  final String originalPath;
  final String thumbnailPath;

  const AssetMediaFiles({
    required this.originalPath,
    required this.thumbnailPath,
  });
}

class AssetMediaException implements Exception {
  final String message;
  final Object? cause;

  const AssetMediaException(this.message, [this.cause]);

  @override
  String toString() => 'AssetMediaException: $message';
}

/// Owns durable copies of physical-asset images and their thumbnails.
///
/// [applicationRoot] is injected so callers can use the app documents
/// directory in production while tests stay independent of path_provider.
class AssetMediaStore {
  static const _mediaDirectoryName = 'asset_media';
  static const _originalsDirectoryName = 'originals';
  static const _thumbnailsDirectoryName = 'thumbnails';

  final Directory applicationRoot;
  final int thumbnailMaxDimension;
  final Random _random;

  AssetMediaStore({
    required this.applicationRoot,
    this.thumbnailMaxDimension = 480,
    Random? random,
  })  : assert(thumbnailMaxDimension > 0),
        _random = random ?? Random.secure();

  Directory get mediaDirectory =>
      Directory(path.join(applicationRoot.path, _mediaDirectoryName));

  Directory get originalsDirectory =>
      Directory(path.join(mediaDirectory.path, _originalsDirectoryName));

  Directory get thumbnailsDirectory =>
      Directory(path.join(mediaDirectory.path, _thumbnailsDirectoryName));

  /// Copies [sourcePath] into managed storage and creates a PNG thumbnail.
  /// The source file is never moved, renamed, or deleted.
  Future<AssetMediaFiles> importFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw AssetMediaException('Source image does not exist: $sourcePath');
    }

    await originalsDirectory.create(recursive: true);
    await thumbnailsDirectory.create(recursive: true);

    final stem = _newFileStem();
    final originalExtension = _safeOriginalExtension(sourcePath);
    final original = File(
      path.join(originalsDirectory.path, '$stem$originalExtension'),
    );
    final thumbnail = File(
      path.join(thumbnailsDirectory.path, '$stem.png'),
    );
    final originalPart = File('${original.path}.part');
    final thumbnailPart = File('${thumbnail.path}.part');

    try {
      await source.copy(originalPart.path);
      final sourceBytes = await originalPart.readAsBytes();
      final transferable = TransferableTypedData.fromList([sourceBytes]);
      final thumbnailBytes = await Isolate.run(
        () => _createThumbnail(
          transferable,
          maxDimension: thumbnailMaxDimension,
        ),
      );
      await thumbnailPart.writeAsBytes(
        thumbnailBytes.materialize().asUint8List(),
        flush: true,
      );

      await originalPart.rename(original.path);
      await thumbnailPart.rename(thumbnail.path);
      return AssetMediaFiles(
        originalPath: original.path,
        thumbnailPath: thumbnail.path,
      );
    } on AssetMediaException {
      await _deleteFiles([
        originalPart,
        thumbnailPart,
        original,
        thumbnail,
      ]);
      rethrow;
    } catch (error) {
      await _deleteFiles([
        originalPart,
        thumbnailPart,
        original,
        thumbnail,
      ]);
      throw AssetMediaException('Failed to import asset image.', error);
    }
  }

  /// Generates the replacement first, so a failed import leaves [previous]
  /// intact. Old managed files are removed only after the new pair is ready.
  Future<AssetMediaFiles> replaceFile({
    required String sourcePath,
    required AssetMediaFiles previous,
  }) async {
    final replacement = await importFile(sourcePath);
    await deleteFiles(previous);
    return replacement;
  }

  /// Deletes both files when, and only when, they are inside the managed
  /// originals/thumbnails directories. External files are deliberately kept.
  Future<void> deleteFiles(AssetMediaFiles files) async {
    await deleteManagedFile(files.originalPath);
    await deleteManagedFile(files.thumbnailPath);
  }

  /// Returns whether a managed file existed and was deleted.
  Future<bool> deleteManagedFile(String filePath) async {
    if (!_isManagedFilePath(filePath)) return false;
    final file = File(filePath);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  bool _isManagedFilePath(String candidate) {
    final absoluteCandidate = _absoluteNormalized(candidate);
    final originalsRoot = _absoluteNormalized(originalsDirectory.path);
    final thumbnailsRoot = _absoluteNormalized(thumbnailsDirectory.path);
    return path.isWithin(originalsRoot, absoluteCandidate) ||
        path.isWithin(thumbnailsRoot, absoluteCandidate);
  }

  String _absoluteNormalized(String value) =>
      path.normalize(path.absolute(value));

  String _newFileStem() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = List<int>.generate(12, (_) => _random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'asset_${now}_$random';
  }

  String _safeOriginalExtension(String sourcePath) {
    final extension = path.extension(sourcePath).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)
        ? extension
        : '.img';
  }

  Future<void> _deleteFiles(Iterable<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Preserve the original import failure; a later cleanup can remove a
        // file that the operating system temporarily kept open.
      }
    }
  }
}

TransferableTypedData _createThumbnail(
  TransferableTypedData source, {
  required int maxDimension,
}) {
  final bytes = source.materialize().asUint8List();
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) {
    throw const AssetMediaException('The selected file is not a valid image.');
  }

  final oriented = image_lib.bakeOrientation(decoded);
  final longestSide = max(oriented.width, oriented.height);
  final image = longestSide <= maxDimension
      ? oriented
      : oriented.width >= oriented.height
          ? image_lib.copyResize(
              oriented,
              width: maxDimension,
              interpolation: image_lib.Interpolation.average,
            )
          : image_lib.copyResize(
              oriented,
              height: maxDimension,
              interpolation: image_lib.Interpolation.average,
            );
  final encoded = image_lib.encodePng(image, level: 6);
  return TransferableTypedData.fromList([Uint8List.fromList(encoded)]);
}
