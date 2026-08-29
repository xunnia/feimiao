// 临时性能候选测量：用于决定是否值得做缓存/少复制优化。
// 该用例只打印相同数据量下的耗时，不把机器抖动写成硬性阈值。
import 'dart:io';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/smart_suggestions.dart';
import 'package:qingji/core/ledger/ledger_policy.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart'
    show aiQuestionMatchesTransaction;
import 'package:qingji/widgets/monthly_pace_card.dart'
    show computeMonthlyPaceSamples;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_perf_candidate_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('measure repeated derived-data candidates on 10k rows', () async {
    final repo = AppRepository();
    await repo.init();
    addTearDown(repo.closeForTest);

    final account = repo.accounts.first;
    final category = repo.categories.first;
    const count = 10000;
    final drafts = <TransactionDraft>[
      for (var i = 0; i < count; i++)
        TransactionDraft(
          kind: TransactionKind.expense,
          amount: Decimal.parse('${10 + i % 500}'),
          accountId: account.id,
          categoryId: category.id,
          date: DateTime(2023, 1, 1).add(Duration(days: i % 1095)),
          note: 'candidate $i',
        ),
    ];
    await repo.importTransactions(drafts);

    // Warm all lazy indices/caches before comparing repeated calls.
    final recordsRef = repo.allRecordsRef;
    final recordsCopy = repo.allRecords;
    final bookId = repo.currentBookId;
    expect(recordsRef.length, count);
    expect(recordsCopy.length, count);

    int elapsed(int iterations, void Function() action) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        action();
      }
      sw.stop();
      return sw.elapsedMilliseconds;
    }

    final copiesMs = elapsed(100, () {
      final value = repo.allRecords;
      if (value.length != count) throw StateError('copy length changed');
    });
    final refsMs = elapsed(100, () {
      final value = repo.allRecordsRef;
      if (value.length != count) throw StateError('ref length changed');
    });
    final fingerprintMs = elapsed(5, () {
      final value = SmartSuggestionEngine.contentFingerprint(
        records: repo.allRecords,
        hasActiveBudget: false,
      );
      if (value == 0) throw StateError('unexpected empty fingerprint');
    });
    final fingerprintRefMs = elapsed(5, () {
      final value = SmartSuggestionEngine.contentFingerprint(
        records: recordsRef,
        hasActiveBudget: false,
      );
      if (value == 0) throw StateError('unexpected empty fingerprint');
    });
    final bookRecordsMs = elapsed(30, () {
      final value = repo.recordsForBookView(bookId);
      if (value.length != count) throw StateError('book records changed');
    });
    expect(repo.bookRecordsCacheBuildCount, 1);
    final bookVisibleMs = elapsed(30, () {
      final value = repo.visibleTransactionsForBookView(bookId);
      if (value.length != count) throw StateError('book visible changed');
    });
    final monthlySummaryMs = elapsed(50, () {
      final value = StatisticsEngine.monthlySummary(
        recordsCopy,
        year: 2024,
        month: 6,
      );
      if (value.dailyTotals.length != 30) {
        throw StateError('monthly summary changed');
      }
    });
    // One sort is enough to expose the asymptotic cost; repeating it would
    // make the full Flutter test suite spend tens of seconds on a diagnostic
    // measurement rather than on a regression assertion.
    final visibleSortMs = elapsed(1, () {
      final value = repo.visibleTransactions.where((t) => !t.excluded).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (value.length != count) throw StateError('sorted visible changed');
    });
    final visiblePreserveOrderMs = elapsed(10, () {
      final value = repo.visibleTransactions
          .where((t) => !t.excluded)
          .toList(growable: false);
      if (value.length != count) throw StateError('visible changed');
    });
    final keywordScanMs = elapsed(3, () {
      final value = repo.visibleTransactionsRef
          .where((t) => aiQuestionMatchesTransaction('candidate 9999', t))
          .toList(growable: false);
      if (value.isEmpty) throw StateError('keyword scan missed fixture');
    });
    final refundIndexMs = elapsed(30, () {
      final value = LedgerPolicy.refundTotals(repo.transactions);
      if (value.isNotEmpty)
        throw StateError('refund fixture unexpectedly non-empty');
    });
    final paceNow = DateTime(2025, 6, 15);
    final legacyPaceMs = elapsed(5, () {
      final value = _legacyMonthlyPaceComputation(
        recordsCopy,
        year: paceNow.year,
        month: paceNow.month,
        isCurrentMonth: true,
        now: paceNow,
      );
      if (value == Decimal.fromInt(-1)) throw StateError('invalid pace');
    });
    final optimizedPaceMs = elapsed(5, () {
      final value = computeMonthlyPaceSamples(
        records: recordsCopy,
        year: paceNow.year,
        month: paceNow.month,
        isCurrentMonth: true,
        now: paceNow,
      );
      if (value.length != 7) throw StateError('pace sample count changed');
    });

    // The public method still returns a mutable copy, while the expensive
    // TransactionRecord conversion is shared. A transaction write must evict
    // that cache before the next read.
    final cachedView = repo.recordsForBookView(bookId);
    cachedView.clear();
    expect(repo.recordsForBookView(bookId), hasLength(count));
    final buildsBeforeMutation = repo.bookRecordsCacheBuildCount;
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.one,
      accountId: account.id,
      categoryId: category.id,
      date: DateTime(2025, 1, 1),
    );
    expect(repo.recordsForBookView(bookId), hasLength(count + 1));
    expect(repo.bookRecordsCacheBuildCount, buildsBeforeMutation + 1);

    print('=== Performance candidate measurements (10k rows) ===');
    print('allRecords copy x100: ${copiesMs}ms');
    print('allRecordsRef read x100: ${refsMs}ms');
    print('suggestion fingerprint (copy) x5: ${fingerprintMs}ms');
    print('suggestion fingerprint (ref) x5: ${fingerprintRefMs}ms');
    print('recordsForBookView x30: ${bookRecordsMs}ms');
    print('visibleTransactionsForBookView x30: ${bookVisibleMs}ms');
    print('monthlySummary x50: ${monthlySummaryMs}ms');
    print('visible filter + sort x1: ${visibleSortMs}ms');
    print('visible filter preserve-order x10: ${visiblePreserveOrderMs}ms');
    print('AI keyword scan x3: ${keywordScanMs}ms');
    print('refund index rebuild x30: ${refundIndexMs}ms');
    print('MonthlyPace old 13 scans x5: ${legacyPaceMs}ms');
    print('MonthlyPace one scan x5: ${optimizedPaceMs}ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Decimal _legacyMonthlyPaceComputation(
  List<TransactionRecord> records, {
  required int year,
  required int month,
  required bool isCurrentMonth,
  required DateTime now,
}) {
  Decimal expenseInMonth(DateTime value, {required int throughDay}) {
    var total = Decimal.zero;
    for (final record in records) {
      if (record.kind != TransactionKind.expense ||
          record.date.year != value.year ||
          record.date.month != value.month ||
          record.date.day > throughDay) {
        continue;
      }
      total += record.amount;
    }
    return total;
  }

  final lastDay = DateTime(year, month + 1, 0).day;
  final cutoffDay = isCurrentMonth ? math.min(now.day, lastDay) : lastDay;
  var checksum = expenseInMonth(
    DateTime(year, month),
    throughDay: cutoffDay,
  );
  for (var offset = 6; offset >= 1; offset--) {
    final value = DateTime(year, month - offset);
    final monthEndDay = DateTime(value.year, value.month + 1, 0).day;
    checksum += expenseInMonth(value, throughDay: monthEndDay);
    checksum += expenseInMonth(
      value,
      throughDay: math.min(cutoffDay, monthEndDay),
    );
  }
  return checksum;
}
