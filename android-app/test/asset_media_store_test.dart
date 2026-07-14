import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as path;
import 'package:qingji/core/assets/asset_media_store.dart';

void main() {
  late Directory sandbox;
  late Directory appRoot;
  late Directory externalRoot;
  late AssetMediaStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('asset_media_store_test_');
    appRoot = Directory(path.join(sandbox.path, 'app'));
    externalRoot = Directory(path.join(sandbox.path, 'camera'));
    await appRoot.create();
    await externalRoot.create();
    store = AssetMediaStore(
      applicationRoot: appRoot,
      thumbnailMaxDimension: 80,
      random: Random(7),
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<File> writeImage(
    String name, {
    int width = 240,
    int height = 120,
  }) async {
    final image = image_lib.Image(width: width, height: height);
    image_lib.fill(image, color: image_lib.ColorRgb8(32, 96, 160));
    final file = File(path.join(externalRoot.path, name));
    await file.writeAsBytes(image_lib.encodePng(image));
    return file;
  }

  test('copies an external original and generates a bounded PNG thumbnail',
      () async {
    final source = await writeImage('camera shot.PNG');

    final result = await store.importFile(source.path);

    expect(await source.exists(), isTrue);
    expect(path.isWithin(store.originalsDirectory.path, result.originalPath),
        isTrue);
    expect(path.isWithin(store.thumbnailsDirectory.path, result.thumbnailPath),
        isTrue);
    expect(path.basename(result.originalPath),
        matches(RegExp(r'^asset_[a-z0-9]+_[a-f0-9]{24}\.png$')));
    expect(path.extension(result.thumbnailPath), '.png');
    expect(await File(result.originalPath).readAsBytes(),
        await source.readAsBytes());

    final thumbnail = image_lib.decodePng(
      await File(result.thumbnailPath).readAsBytes(),
    );
    expect(thumbnail, isNotNull);
    expect(thumbnail!.width, 80);
    expect(thumbnail.height, 40);
  });

  test('creates collision-resistant managed names without using source name',
      () async {
    final source = await writeImage(r'.. evil name.jpeg');

    final first = await store.importFile(source.path);
    final second = await store.importFile(source.path);

    expect(first.originalPath, isNot(second.originalPath));
    expect(path.basename(first.originalPath), isNot(contains('evil')));
    expect(path.extension(first.originalPath), '.jpeg');
    expect(await File(first.originalPath).exists(), isTrue);
    expect(await File(second.originalPath).exists(), isTrue);
  });

  test('replacement is created before old managed files are removed', () async {
    final oldSource = await writeImage('old.png', width: 120, height: 120);
    final newSource = await writeImage('new.png', width: 300, height: 150);
    final oldMedia = await store.importFile(oldSource.path);

    final replacement = await store.replaceFile(
      sourcePath: newSource.path,
      previous: oldMedia,
    );

    expect(await File(replacement.originalPath).exists(), isTrue);
    expect(await File(replacement.thumbnailPath).exists(), isTrue);
    expect(await File(oldMedia.originalPath).exists(), isFalse);
    expect(await File(oldMedia.thumbnailPath).exists(), isFalse);
  });

  test('failed replacement preserves old media and cleans partial files',
      () async {
    final source = await writeImage('old.png');
    final oldMedia = await store.importFile(source.path);
    final corrupt = File(path.join(externalRoot.path, 'corrupt.jpg'));
    await corrupt.writeAsString('not an image');

    await expectLater(
      store.replaceFile(sourcePath: corrupt.path, previous: oldMedia),
      throwsA(isA<AssetMediaException>()),
    );

    expect(await File(oldMedia.originalPath).exists(), isTrue);
    expect(await File(oldMedia.thumbnailPath).exists(), isTrue);
    final managedFiles = <File>[];
    await for (final entity in store.mediaDirectory.list(recursive: true)) {
      if (entity is File) managedFiles.add(entity);
    }
    expect(managedFiles, hasLength(2));
    expect(managedFiles.any((file) => file.path.endsWith('.part')), isFalse);
  });

  test('corrupt import leaves no originals, thumbnails, or part files',
      () async {
    final corrupt = File(path.join(externalRoot.path, 'broken.png'));
    await corrupt.writeAsBytes(List<int>.generate(128, (index) => index));

    await expectLater(
      store.importFile(corrupt.path),
      throwsA(isA<AssetMediaException>()),
    );

    expect(await corrupt.exists(), isTrue);
    final leftovers = await store.mediaDirectory
        .list(recursive: true)
        .where((entity) => entity is File)
        .toList();
    expect(leftovers, isEmpty);
  });

  test('deletion removes only files inside the two managed directories',
      () async {
    final source = await writeImage('keep-source.png');
    final media = await store.importFile(source.path);
    final unrelatedInsideApp = File(path.join(appRoot.path, 'database.sqlite'));
    await unrelatedInsideApp.writeAsString('keep');

    expect(await store.deleteManagedFile(source.path), isFalse);
    expect(await store.deleteManagedFile(unrelatedInsideApp.path), isFalse);
    await store.deleteFiles(media);

    expect(await source.exists(), isTrue);
    expect(await unrelatedInsideApp.exists(), isTrue);
    expect(await File(media.originalPath).exists(), isFalse);
    expect(await File(media.thumbnailPath).exists(), isFalse);
  });

  test('normalized traversal paths cannot escape managed directories',
      () async {
    final external = File(path.join(appRoot.path, 'outside.txt'));
    await external.writeAsString('keep');
    final traversal = path.join(
      store.originalsDirectory.path,
      '..',
      '..',
      'outside.txt',
    );

    expect(await store.deleteManagedFile(traversal), isFalse);
    expect(await external.exists(), isTrue);
  });
}
