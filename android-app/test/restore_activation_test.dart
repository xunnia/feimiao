import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/report_execution_fence.dart';
import 'package:qingji/core/backup/restore_activation.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory docs;
  late String dbPath;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('restore_activation_test_');
    docs = await Directory(p.join(root.path, 'docs')).create();
    dbPath = p.join(root.path, 'qingji.db');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> seed(String live, bool database, String value) async {
    if (!database) await Directory(live).create(recursive: true);
    await File(database ? live : p.join(live, 'photo'))
        .writeAsString(value, flush: true);
  }

  Future<String> contents(RestoreActivationPart part) =>
      File(part.name == 'database' ? part.live : p.join(part.live, 'photo'))
          .readAsString();
  Future<RestoreActivation> prepared({bool original = true}) async {
    for (final name in ['database', 'receipts', 'asset_media']) {
      final live = name == 'database' ? dbPath : p.join(docs.path, name);
      if (original) await seed(live, name == 'database', 'old-$name');
      await seed('$live.restore-new-123', name == 'database', 'new-$name');
    }
    return RestoreActivation.begin(
        databasePath: dbPath,
        token: '123',
        documentsDirectory: docs,
        receipts: true,
        assetMedia: true);
  }

  for (var operations = 0; operations <= 6; operations++) {
    test(
        'restart after $operations file switches restores the old complete set',
        () async {
      final activation = await prepared();
      var done = 0;
      for (final part in activation.parts) {
        if (done >= operations) break;
        await part.moveOriginal();
        done++;
        if (done >= operations) break;
        await part.install();
        done++;
      }
      await RestoreActivation.recover(
          databasePath: dbPath, documentsDirectory: () async => docs);
      for (final part in activation.parts) {
        expect(await contents(part), 'old-${part.name}');
        expect(await part.exists(part.old), isFalse);
        expect(await part.exists(part.staged), isFalse);
      }
      await RestoreActivation.recover(
          databasePath: dbPath, documentsDirectory: () async => docs);
      expect(await File(dbPath).readAsString(), 'old-database');
    });
  }
  test('restart during rollback is idempotent', () async {
    final activation = await prepared();
    for (final part in activation.parts) {
      await part.moveOriginal();
      await part.install();
    }
    await activation.parts.last.rollback();
    await RestoreActivation.recover(
        databasePath: dbPath, documentsDirectory: () async => docs);
    for (final part in activation.parts) {
      expect(await contents(part), 'old-${part.name}');
    }
  });
  test('committed journal retains new data after interrupted cleanup',
      () async {
    final activation = await prepared();
    for (final part in activation.parts) {
      await part.moveOriginal();
      await part.install();
    }
    await File('$dbPath.restore-committed-123')
        .writeAsString('committed', flush: true);
    await activation.parts.first.remove(activation.parts.first.old);
    await RestoreActivation.recover(
        databasePath: dbPath, documentsDirectory: () async => docs);
    for (final part in activation.parts) {
      expect(await contents(part), 'new-${part.name}');
    }
  });
  test('rollback removes newly-created directories when none existed before',
      () async {
    final activation = await prepared(original: false);
    for (final part in activation.parts) {
      await part.install();
    }
    await activation.rollback();
    for (final part in activation.parts) {
      expect(await part.exists(part.live), isFalse);
    }
  });
  test('malformed or path-injected journal preserves files and fails closed',
      () async {
    await File(dbPath).writeAsString('original');
    final journal = File(RestoreActivation.journalPath(dbPath));
    for (final invalid in [
      'broken',
      jsonEncode({
        'version': 1,
        'token': '../../escape',
        'parts': {'database': true}
      }),
      jsonEncode({
        'version': 1,
        'token': '123',
        'parts': {'database': true, '../external': false}
      })
    ]) {
      await journal.writeAsString(invalid);
      await expectLater(
          RestoreActivation.recover(
              databasePath: dbPath, documentsDirectory: () async => docs),
          throwsFormatException);
      expect(await File(dbPath).readAsString(), 'original');
      expect(await journal.exists(), isTrue);
    }
  });
  test(
      'missing original and old copy blocks startup instead of creating an empty DB',
      () async {
    final activation = await prepared();
    await activation.database.remove(activation.database.live);
    await expectLater(
        RestoreActivation.recover(
            databasePath: dbPath, documentsDirectory: () async => docs),
        throwsStateError);
    expect(await File(dbPath).exists(), isFalse);
    expect(await File(RestoreActivation.journalPath(dbPath)).exists(), isTrue);
  });
  test(
      'legacy missing-live checkpoint recovers; ambiguous originals are retained',
      () async {
    await File('$dbPath.restore-old-12').writeAsString('legacy');
    await RestoreActivation.recover(
        databasePath: dbPath, documentsDirectory: () async => docs);
    expect(await File(dbPath).readAsString(), 'legacy');
    await File(dbPath).delete();
    await File('$dbPath.restore-old-13').writeAsString('a');
    await File('$dbPath.restore-old-14').writeAsString('b');
    await expectLater(
        RestoreActivation.recover(
            databasePath: dbPath, documentsDirectory: () async => docs),
        throwsStateError);
    expect(await File(dbPath).exists(), isFalse);
  });

  for (final checkpoint in [
    'before_database_install',
    'before_receipts_install',
    'before_asset_media_install',
    'before_database_open'
  ]) {
    test('repository restart from $checkpoint restores live bills and media',
        () async {
      final live = await Directory(p.join(root.path, 'live')).create();
      final crashed = await Directory(p.join(root.path, 'crashed')).create();
      final archives = await Directory(p.join(root.path, 'archives')).create();
      await databaseFactory.setDatabasesPath(live.path);
      final repo = AppRepository(
          reportExecutionFence: ReportExecutionFence(
              databasePathProvider: () async => p.join(root.path, 'fence.db')));
      await repo.init();
      await seed(p.join(docs.path, 'receipts'), false, 'backup-receipt');
      await seed(p.join(docs.path, 'asset_media'), false, 'backup-media');
      final backup = await repo.exportBackupPackage(
          temporaryDirectory: archives, documentsDirectory: docs);
      await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(123),
          accountId: repo.accounts.first.id,
          date: DateTime.now(),
          note: 'keep-live-bill');
      await seed(p.join(docs.path, 'receipts'), false, 'live-receipt');
      await seed(p.join(docs.path, 'asset_media'), false, 'live-media');
      final crashedDocs = Directory(p.join(crashed.path, 'docs'));
      var captured = false;
      // Capture the exact closed on-disk state before catch can roll it back.
      final result = await repo.restoreBackupPackage(backup.path,
          temporaryDirectory: archives,
          documentsDirectory: docs, onRestoreStep: (step) {
        if (step != checkpoint) return;
        for (final entry in live.listSync()) {
          if (entry is File) {
            entry.copySync(p.join(crashed.path, p.basename(entry.path)));
          }
        }
        crashedDocs.createSync();
        for (final entry
            in docs.listSync(recursive: true, followLinks: false)) {
          final target =
              p.join(crashedDocs.path, p.relative(entry.path, from: docs.path));
          if (entry is Directory) {
            Directory(target).createSync(recursive: true);
          }
          if (entry is File) {
            File(target).parent.createSync(recursive: true);
            entry.copySync(target);
          }
        }
        captured = true;
        throw StateError('checkpoint captured');
      });
      expect(captured, isTrue);
      expect(result, isFalse);
      await repo.closeForTest();
      await databaseFactory.setDatabasesPath(crashed.path);
      final recoveryFence = ReportExecutionFence(
          databasePathProvider: () async =>
              p.join(root.path, 'recovery-fence.db'));
      final reopened = AppRepository(
          reportExecutionFence: recoveryFence,
          restoreDocumentsDirectoryProvider: () async => crashedDocs);
      // Background report startup already holds this fence. Real repository
      // recovery must reuse it rather than waiting for its own lock release.
      final workerLease = await recoveryFence.acquire();
      await workerLease
          .guard(reopened.init, readJobUuid: (_) async => null)
          .timeout(const Duration(seconds: 10));
      expect(reopened.transactions.where((row) => row.note == 'keep-live-bill'),
          hasLength(1));
      expect(
          await File(p.join(crashedDocs.path, 'receipts', 'photo'))
              .readAsString(),
          'live-receipt');
      expect(
          await File(p.join(crashedDocs.path, 'asset_media', 'photo'))
              .readAsString(),
          'live-media');
      await reopened.closeForTest();
      final again = AppRepository(
          restoreDocumentsDirectoryProvider: () async => crashedDocs);
      await again.init();
      expect(again.transactions.where((row) => row.note == 'keep-live-bill'),
          hasLength(1));
      await again.closeForTest();
    });
  }
}
