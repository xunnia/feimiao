import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/transactions/transaction_list_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_transaction_list_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> freshRepo() async {
    final repo = AppRepository();
    await repo.init();
    return repo;
  }

  Future<void> pumpView(WidgetTester tester, AppRepository repo) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: const MaterialApp(home: TransactionListView()),
      ),
    );
    await tester.pump();
  }

  testWidgets('partial refund is reflected in day and reimbursable totals',
      (tester) async {
    final repo = (await tester.runAsync(freshRepo))!;
    addTearDown(() => tester.runAsync(repo.closeForTest));
    final accountId = repo.accounts.first.id;
    final date = DateTime(2026, 7, 14, 12, 30);

    final transactionId = await tester.runAsync(
      () => repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        accountId: accountId,
        note: '差旅费',
        date: date,
        reimbursable: true,
      ),
    );
    final original = repo.visibleTransactions
        .firstWhere((transaction) => transaction.id == transactionId);
    await tester.runAsync(
      () => repo.refundTransaction(
        original,
        Decimal.fromInt(30),
        settledAt: date.add(const Duration(days: 1)),
        settlementAccountId: accountId,
      ),
    );

    await pumpView(tester, repo);

    final netText = MoneyFormat.string(Decimal.fromInt(70));
    expect(find.text('待报销 1 笔 · 合计 '), findsOneWidget);
    expect(find.text(netText), findsOneWidget);
    expect(find.text('支 ${netText.replaceAll('¥', '')}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('excluded reimbursable row stays payable but not in day spending',
      (tester) async {
    final repo = (await tester.runAsync(freshRepo))!;
    addTearDown(() => tester.runAsync(repo.closeForTest));
    final accountId = repo.accounts.first.id;

    await tester.runAsync(
      () => repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(50),
        accountId: accountId,
        note: '代垫款',
        date: DateTime(2026, 7, 14, 12, 30),
        reimbursable: true,
        excluded: true,
      ),
    );

    await pumpView(tester, repo);

    expect(find.text('待报销 1 笔 · 合计 '), findsOneWidget);
    expect(find.text(MoneyFormat.string(Decimal.fromInt(50))), findsOneWidget);
    expect(find.textContaining('支 '), findsNothing);
    expect(find.byKey(const ValueKey('tx-day-total-0')), findsNothing);
    expect(find.text('不计入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
