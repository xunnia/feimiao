import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/backup/backup_package_codec.dart';

Uint8List _zip(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encode(archive)!);

void main() {
  test('v2 round trip includes database, receipts and managed asset media', () {
    final encoded = BackupPackageCodec.encode(
      files: {
        'database/qingji.db': Uint8List.fromList([1, 2, 3]),
        'receipts/receipt.jpg': Uint8List.fromList([4, 5]),
        'asset_media/originals/asset.jpg': Uint8List.fromList([6, 7]),
        'asset_media/thumbnails/asset.png': Uint8List.fromList([8, 9]),
      },
      databaseVersion: 36,
      createdAt: DateTime.utc(2026, 7, 13),
    );

    final decoded = BackupPackageCodec.decode(encoded);
    expect(decoded.version, 2);
    expect(decoded.databaseVersion, 36);
    expect(decoded.files.keys, contains('asset_media/thumbnails/asset.png'));
    expect(decoded.manifest['contains'], containsPair('assetMedia', true));
  });

  test('v1 package remains readable', () {
    final database = Uint8List.fromList([10, 20]);
    final receipt = Uint8List.fromList([30]);
    final checksums = {
      'database/qingji.db': sha256.convert(database).toString(),
      'receipts/old.jpg': sha256.convert(receipt).toString(),
    };
    final manifest = utf8.encode(jsonEncode({
      'format': BackupPackageCodec.format,
      'version': 1,
      'databaseVersion': 34,
      'checksums': checksums,
    }));
    final archive = Archive()
      ..addFile(ArchiveFile('database/qingji.db', database.length, database))
      ..addFile(ArchiveFile('receipts/old.jpg', receipt.length, receipt))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));

    final decoded = BackupPackageCodec.decode(_zip(archive));
    expect(decoded.version, 1);
    expect(decoded.files['receipts/old.jpg'], receipt);
  });

  test('rejects checksum mismatch and undeclared payload files', () {
    final manifest = utf8.encode(jsonEncode({
      'format': BackupPackageCodec.format,
      'version': 2,
      'checksums': {'database/qingji.db': 'wrong'},
    }));
    final archive = Archive()
      ..addFile(ArchiveFile('database/qingji.db', 1, [1]))
      ..addFile(ArchiveFile('receipts/extra.jpg', 1, [2]))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));

    expect(
      () => BackupPackageCodec.decode(_zip(archive)),
      throwsA(isA<BackupPackageException>()),
    );
  });

  test('rejects absolute and traversal paths before extraction', () {
    expect(BackupPackageCodec.isSafePayloadPath('../qingji.db'), isFalse);
    expect(BackupPackageCodec.isSafePayloadPath('/receipts/a.jpg'), isFalse);
    expect(
      BackupPackageCodec.isSafePayloadPath('asset_media/../qingji.db'),
      isFalse,
    );
    expect(
      () => BackupPackageCodec.encode(
        files: {
          'database/qingji.db': Uint8List(1),
          '../outside': Uint8List(1),
        },
        databaseVersion: 36,
        createdAt: DateTime.now(),
      ),
      throwsA(isA<BackupPackageException>()),
    );
  });

  test('normalizes malformed manifest field types to package errors', () {
    final database = Uint8List.fromList([1, 2, 3]);
    final manifest = utf8.encode(jsonEncode({
      'format': BackupPackageCodec.format,
      'version': '2',
      'databaseVersion': 36,
      'checksums': {
        'database/qingji.db': sha256.convert(database).toString(),
      },
    }));
    final archive = Archive()
      ..addFile(ArchiveFile(
        'database/qingji.db',
        database.length,
        database,
      ))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));

    expect(
      () => BackupPackageCodec.decode(_zip(archive)),
      throwsA(isA<BackupPackageException>()),
    );
  });
}
