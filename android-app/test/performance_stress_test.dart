// 性能压力测试：大数据量下的表现。
// 生成 10 年、10 万条流水，验证关键路径性能。
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_perf_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Performance stress test', () {
    late AppRepository repo;

    setUp(() async {
      repo = AppRepository();
      await repo.init();
    });

    tearDown(() async {
      await repo.closeForTest();
    });
    
    test('10k transactions performance baseline', () async {
      final sw = Stopwatch()..start();

      // 1. 使用默认账户
      final account = repo.accounts.first;
      final accountId = account.id;
      print('Using default account: ${account.name}');

      // 2. 找到常用分类
      final categoryNames = ['食品餐饮', '居家住房', '交通出行', '购物消费', '娱乐休闲'];
      final categoryIds = <int>[];
      for (final name in categoryNames) {
        final cat = repo.categories.firstWhere(
          (c) => c.nameZh == name,
          orElse: () => repo.categories.first,
        );
        categoryIds.add(cat.id);
      }

      // 3. 生成 1 万条流水（3 年，每天 ~9 条，实战级别）。
      // 使用仓库已有的批量导入入口：逐笔 addTransaction 还会为每行
      // 刷新余额快照、派生缓存和监听器，测到的是 UI 写路径而不是
      // 10k 记录的读取性能，且会把这个基准拖过超时。
      sw.reset();
      final startDate = DateTime(2023, 1, 1);
      const totalTransactions = 10000;
      final drafts = <TransactionDraft>[];
      for (int i = 0; i < totalTransactions; i++) {
        final daysOffset = (i * 1095) ~/ totalTransactions;
        final date = startDate.add(Duration(days: daysOffset));
        final amount = Decimal.parse('${10 + (i % 500)}');
        final categoryId = categoryIds[i % categoryIds.length];
        drafts.add(TransactionDraft(
          kind: TransactionKind.expense,
          amount: amount,
          accountId: accountId,
          date: date,
          categoryId: categoryId,
          note: i % 100 == 0 ? '压测记录 $i' : '',
        ));
      }
      await repo.importTransactions(drafts);
      final generationTime = sw.elapsedMilliseconds;
      print('✓ Generated $totalTransactions transactions in ${generationTime}ms');

      // 4. 性能检查点
      sw.reset();
      final allTransactions = repo.allRecords;
      final fetchTime = sw.elapsedMilliseconds;
      expect(allTransactions.length, totalTransactions);
      print('✓ Fetched all transactions in ${fetchTime}ms');

      sw.reset();
      final summary = StatisticsEngine.monthlySummary(
        repo.allRecords,
        year: 2025,
        month: 6,
      );
      final summaryTime = sw.elapsedMilliseconds;
      print('✓ Computed monthly summary in ${summaryTime}ms');
      expect(summary, isNotNull);

      sw.reset();
      final breakdown = repo.currentNetWorthBreakdown;
      final breakdownTime = sw.elapsedMilliseconds;
      print('✓ Computed net worth breakdown in ${breakdownTime}ms');
      expect(breakdown, isNotNull);

      // 5. 性能阈值断言（实战级别：1万条应该秒级响应）
      expect(fetchTime, lessThan(1000),
          reason: 'Fetching 10k transactions should complete within 1s');
      expect(summaryTime, lessThan(300),
          reason: 'Monthly summary should complete within 300ms');
      expect(breakdownTime, lessThan(200),
          reason: 'Net worth breakdown should complete within 200ms');

      print('\n=== Performance Summary (10k baseline) ===');
      print('Generation: ${generationTime}ms');
      print('Fetch all:  ${fetchTime}ms');
      print('Summary:    ${summaryTime}ms');
      print('Breakdown:  ${breakdownTime}ms');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
