import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
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
    expect(repo.visibleTransactions.map((t) => t.note), contains('退款'));
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
