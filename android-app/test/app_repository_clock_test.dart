import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('default cash seed uses one logical timestamp and survives reopening',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = Directory.systemTemp.createTempSync('qingji_clock_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    await databaseFactory.setDatabasesPath(directory.path);

    // Also run this test with QINGJI_PARITY_CAPTURE=true and a historical
    // QINGJI_DEMO_NOW. A wall-clock seed would then fall outside this interval
    // and make the cash account invisible to the fixed-date balance query.
    final before = AppClock.now.millisecondsSinceEpoch;
    final repo = AppRepository();
    late AccountEntity cash;
    try {
      await repo.init();
      await repo.fullyReady;
      final after = AppClock.now.millisecondsSinceEpoch;
      cash = repo.accounts.singleWhere((account) => account.name == '现金');
      expect(cash.createdMs, inInclusiveRange(before, after));
      expect(cash.updatedMs, cash.createdMs);
      expect(cash.openingBalanceEffectiveMs, cash.createdMs);
    } finally {
      await repo.closeForTest();
    }

    final reopened = AppRepository();
    try {
      await reopened.init();
      await reopened.fullyReady;
      final restored = reopened.accounts.singleWhere((a) => a.id == cash.id);
      expect(restored.createdMs, cash.createdMs);
      expect(restored.updatedMs, cash.updatedMs);
      expect(restored.openingBalanceEffectiveMs, cash.openingBalanceEffectiveMs);
    } finally {
      await reopened.closeForTest();
    }
  });
}
