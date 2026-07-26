import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('qingji_startup_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('fast startup exposes the current-month ledger before full hydration',
      () async {
    final seed = AppRepository();
    await seed.init();
    final accountId = seed.transactionAccounts.first.id;
    final categoryId =
        seed.categoriesForKindRanked(TransactionKind.expense).first.id;
    await seed.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('23.50'),
      categoryId: categoryId,
      accountId: accountId,
      note: '启动优先级测试',
      date: DateTime.now(),
    );
    await seed.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('-23.50'),
      categoryId: categoryId,
      accountId: accountId,
      note: '退款',
      date: DateTime.now(),
    );
    await seed.closeForTest();

    final repo = AppRepository();
    final core = repo.init(fastStartup: true);
    await repo.ready;

    expect(repo.isReady, isTrue);
    expect(repo.isFullyReady, isFalse);
    expect(repo.isInitializing, isFalse);
    expect(repo.visibleTransactions.map((t) => t.note), contains('启动优先级测试'));
    expect(repo.visibleTransactions.map((t) => t.note), contains('退款'));
    expect(repo.currentBookId, greaterThan(0));
    expect(
      tmp.listSync().whereType<File>().where(
            (file) => file.path.contains('.auto-'),
          ),
      isEmpty,
    );

    await repo.finishDeferredInitialization();
    await core;
    expect(repo.isFullyReady, isTrue);
    expect(repo.visibleTransactions.map((t) => t.note), contains('启动优先级测试'));
    expect(repo.visibleTransactions.map((t) => t.note), isNot(contains('退款')));
    expect(
      tmp.listSync().whereType<File>().where(
            (file) => file.path.contains('.auto-'),
          ),
      isNotEmpty,
    );
    await repo.closeForTest();
  });
}
