import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/recurring_rule.dart';
import 'package:qingji/core/models/category_icon_style.dart';
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
    await seed.setCategoryIconStyle(CategoryIconStyle.line);
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
    await seed.addAiConfiguredProvider(
      displayName: '启动测试 AI',
      baseUrl: 'https://startup.example/v1',
      apiKey: 'startup-key',
      models: const ['startup-model'],
      model: 'startup-model',
    );
    await seed.closeForTest();

    final repo = AppRepository();
    final core = repo.init(fastStartup: true);
    await repo.ready;

    expect(repo.isReady, isTrue);
    expect(repo.isFullyReady, isFalse);
    expect(repo.isInitializing, isFalse);
    expect(repo.visibleTransactions.map((t) => t.note), contains('启动优先级测试'));
    expect(repo.visibleTransactions.map((t) => t.note), isNot(contains('退款')));
    expect(repo.categoryIconStyle, CategoryIconStyle.line);
    expect(repo.currentBookId, greaterThan(0));
    // AI/security storage has its own barrier so it cannot delay the first
    // complete home frame. Wait for that explicit barrier before asserting the
    // persisted selection, which is also what the send path does.
    await repo.aiReady;
    expect(repo.isAiReady, isTrue);
    final startupAi = repo.aiProviderConfigFor(AiTaskType.chatQuery);
    expect(startupAi.hasKey, isTrue);
    expect(startupAi.model, 'startup-model');
    expect(startupAi.baseUrl, 'https://startup.example/v1');
    final startupRecordAi = repo.aiProviderConfigFor(AiTaskType.recordParse);
    expect(startupRecordAi.hasKey, isTrue);
    expect(startupRecordAi.model, 'startup-model');
    expect(startupRecordAi.baseUrl, 'https://startup.example/v1');
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

  test('failed deferred hydration can retry after a database fault is repaired',
      () async {
    final repo = AppRepository();
    await repo.init(fastStartup: true);
    await repo.aiReady;
    final db = await databaseFactory.openDatabase('${tmp.path}/qingji.db');
    await db.execute('ALTER TABLE reports RENAME TO reports_fault_fixture');
    await expectLater(repo.finishDeferredInitialization(), throwsA(anything));
    expect(repo.isFullyReady, isFalse);
    expect(repo.initializationError, isNotNull);
    await db.execute('ALTER TABLE reports_fault_fixture RENAME TO reports');
    await repo.finishDeferredInitialization();
    expect(repo.isFullyReady, isTrue);
    expect(repo.initializationError, isNull);
    await repo.closeForTest();
  });

  test(
      'home ready already includes due recurring entries without later duplication',
      () async {
    final seed = AppRepository();
    await seed.init();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await seed.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('10'),
      accountId: seed.transactionAccounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(now.year, now.month, now.day + 1),
      note: 'startup due fixture',
    );
    final db = await databaseFactory.openDatabase('${tmp.path}/qingji.db');
    await db.update(
        'recurring_rules', {'next_due_ms': today.millisecondsSinceEpoch});
    await seed.closeForTest();
    final repo = AppRepository();
    await repo.init(fastStartup: true);
    expect(
        repo.visibleTransactions
            .where((t) => t.note == 'startup due fixture')
            .length,
        1);
    await repo.finishDeferredInitialization();
    expect(
        repo.visibleTransactions
            .where((t) => t.note == 'startup due fixture')
            .length,
        1);
    await repo.closeForTest();
  });

  test('SQLite header parser reads user_version without opening the database',
      () {
    final header = List<int>.filled(100, 0);
    header.setRange(
      0,
      16,
      const [
        83,
        81,
        76,
        105,
        116,
        101,
        32,
        102,
        111,
        114,
        109,
        97,
        116,
        32,
        51,
        0,
      ],
    );
    // SQLite stores the 32-bit user_version field in big-endian order.
    header.setRange(60, 64, const [0, 0, 0, 49]);

    expect(AppRepository.sqliteUserVersionFromHeader(header), 49);
    expect(
      AppRepository.sqliteUserVersionFromHeader(header.sublist(0, 63)),
      isNull,
    );

    final wrongMagic = List<int>.from(header)..[0] = 0;
    expect(AppRepository.sqliteUserVersionFromHeader(wrongMagic), isNull);
    expect(AppRepository.sqliteUserVersionFromHeader(const []), isNull);
  });
}
