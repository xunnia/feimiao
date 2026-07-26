import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class BackupPackageException implements Exception {
  final String message;

  const BackupPackageException(this.message);

  @override
  String toString() => 'BackupPackageException: $message';
}

/// 一个待打包的备份文件：包内路径 + 磁盘上的源文件（内容流式读取）。
class BackupPayloadFile {
  final String archivePath;
  final File file;

  const BackupPayloadFile({required this.archivePath, required this.file});
}

class DecodedBackupPackage {
  final int version;
  final int databaseVersion;
  final DateTime? createdAt;
  final Map<String, Uint8List> files;
  final Map<String, dynamic> manifest;

  const DecodedBackupPackage({
    required this.version,
    required this.databaseVersion,
    required this.createdAt,
    required this.files,
    required this.manifest,
  });
}

/// Binary contract for full-device backups.
///
/// Version 1 (database + receipts) remains readable. Version 2 additionally
/// carries managed asset media and requires the checksum list to match every
/// payload file exactly.
class BackupPackageCodec {
  static const format = 'feimiao-backup';
  static const currentVersion = 2;
  static const manifestPath = 'manifest.json';

  const BackupPackageCodec._();

  static Uint8List encode({
    required Map<String, Uint8List> files,
    required int databaseVersion,
    required DateTime createdAt,
  }) {
    _validatePayloadNames(files.keys);
    if (!files.containsKey('database/qingji.db')) {
      throw const BackupPackageException('Backup database is missing.');
    }

    final checksums = <String, String>{};
    final archive = Archive();
    for (final entry in files.entries) {
      checksums[entry.key] = sha256.convert(entry.value).toString();
      archive.addFile(
        ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    final manifest = <String, Object?>{
      'format': format,
      'version': currentVersion,
      'createdAt': createdAt.toIso8601String(),
      'databaseVersion': databaseVersion,
      'contains': {
        'database': true,
        'receipts': files.keys.any((name) => name.startsWith('receipts/')),
        'assetMedia': files.keys.any((name) => name.startsWith('asset_media/')),
      },
      'excludes': const ['deepseek_api_key', 'custom_ai_api_key'],
      'checksums': checksums,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    archive.addFile(
      ArchiveFile(manifestPath, manifestBytes.length, manifestBytes),
    );
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const BackupPackageException('Backup package encoding failed.');
    }
    return Uint8List.fromList(encoded);
  }

  /// 流式打包到 [outputPath]：逐文件流式算校验和、逐文件流式压入 zip，
  /// 任何时刻内存里只有单个读写缓冲——收据/资产照片多的老用户在低端机上
  /// 导出不再因「全部文件字节 + 整包 zip 字节」同时驻留而 OOM。
  /// 包格式与 [encode] 完全一致，[decode] 可原样读回。
  static Future<void> encodeToFile({
    required List<BackupPayloadFile> files,
    required String outputPath,
    required int databaseVersion,
    required DateTime createdAt,
  }) async {
    final names = [for (final entry in files) entry.archivePath];
    _validatePayloadNames(names);
    if (!names.contains('database/qingji.db')) {
      throw const BackupPackageException('Backup database is missing.');
    }

    final checksums = <String, String>{};
    for (final entry in files) {
      final digest = await sha256.bind(entry.file.openRead()).first;
      checksums[entry.archivePath] = digest.toString();
    }
    final manifest = <String, Object?>{
      'format': format,
      'version': currentVersion,
      'createdAt': createdAt.toIso8601String(),
      'databaseVersion': databaseVersion,
      'contains': {
        'database': true,
        'receipts': names.any((name) => name.startsWith('receipts/')),
        'assetMedia': names.any((name) => name.startsWith('asset_media/')),
      },
      'excludes': const ['deepseek_api_key', 'custom_ai_api_key'],
      'checksums': checksums,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));

    final encoder = ZipFileEncoder();
    encoder.create(outputPath);
    try {
      for (final entry in files) {
        await encoder.addFile(entry.file, entry.archivePath);
      }
      encoder.addArchiveFile(
        ArchiveFile(manifestPath, manifestBytes.length, manifestBytes),
      );
    } finally {
      await encoder.close();
    }
  }

  static DecodedBackupPackage decode(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const BackupPackageException('Backup package is not a valid ZIP.');
    }

    final byName = <String, ArchiveFile>{};
    for (final file in archive.files.where((entry) => entry.isFile)) {
      if (byName.containsKey(file.name)) {
        throw const BackupPackageException(
          'Backup package contains duplicate file names.',
        );
      }
      byName[file.name] = file;
    }
    final manifestFile = byName[manifestPath];
    if (manifestFile == null) {
      throw const BackupPackageException('Backup manifest is missing.');
    }

    late final Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(_bytesOf(manifestFile)));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      manifest = decoded;
    } catch (_) {
      throw const BackupPackageException('Backup manifest is invalid.');
    }
    if (manifest['format'] != format) {
      throw const BackupPackageException('Backup format is not supported.');
    }
    final rawVersion = manifest['version'];
    if (rawVersion is! int) {
      throw const BackupPackageException('Backup version is invalid.');
    }
    final version = rawVersion;
    if (version < 1 || version > currentVersion) {
      throw const BackupPackageException('Backup version is not supported.');
    }
    final rawChecksums = manifest['checksums'];
    if (rawChecksums is! Map) {
      throw const BackupPackageException('Backup checksums are missing.');
    }
    final checksums = <String, String>{
      for (final entry in rawChecksums.entries)
        entry.key.toString(): entry.value.toString(),
    };
    _validatePayloadNames(checksums.keys);

    final payloadNames =
        byName.keys.where((name) => name != manifestPath).toSet();
    if (payloadNames.length != checksums.length ||
        !payloadNames.containsAll(checksums.keys)) {
      throw const BackupPackageException(
        'Backup file list does not match its manifest.',
      );
    }
    if (!checksums.containsKey('database/qingji.db')) {
      throw const BackupPackageException('Backup database is missing.');
    }

    final files = <String, Uint8List>{};
    for (final entry in checksums.entries) {
      final file = byName[entry.key];
      if (file == null) {
        throw const BackupPackageException('A backup file is missing.');
      }
      final content = _bytesOf(file);
      if (sha256.convert(content).toString() != entry.value) {
        throw const BackupPackageException(
            'Backup checksum verification failed.');
      }
      files[entry.key] = content;
    }
    final rawDatabaseVersion = manifest['databaseVersion'];
    if (rawDatabaseVersion != null && rawDatabaseVersion is! int) {
      throw const BackupPackageException(
        'Backup database version is invalid.',
      );
    }
    return DecodedBackupPackage(
      version: version,
      databaseVersion: rawDatabaseVersion as int? ?? 0,
      createdAt: DateTime.tryParse(manifest['createdAt']?.toString() ?? ''),
      files: Map.unmodifiable(files),
      manifest: Map.unmodifiable(manifest),
    );
  }

  static bool isSafePayloadPath(String value) {
    if (value.isEmpty || value.contains('\\')) return false;
    if (path.posix.isAbsolute(value) || path.posix.normalize(value) != value) {
      return false;
    }
    final segments = path.posix.split(value);
    if (segments.any((segment) => segment.isEmpty || segment == '..')) {
      return false;
    }
    if (value == 'database/qingji.db') return true;
    return value.startsWith('receipts/') || value.startsWith('asset_media/');
  }

  static void _validatePayloadNames(Iterable<String> names) {
    final seen = <String>{};
    for (final name in names) {
      if (!seen.add(name) || !isSafePayloadPath(name)) {
        throw const BackupPackageException('Backup contains an unsafe path.');
      }
    }
  }

  static Uint8List _bytesOf(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    return Uint8List.fromList(List<int>.from(content as List));
  }
}
