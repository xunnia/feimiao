import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/search/search_view.dart';
import 'package:qingji/widgets/transaction_day_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('搜索纯函数', () {
    test('时间胶囊：今年只写月日，跨年带年份', () {
      final now = DateTime(2026, 9, 29);
      expect(
        searchDateRangeLabel(
            DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 31)),
            now),
        '03/01~03/31',
      );
      expect(
        searchDateRangeLabel(
            DateTimeRange(start: DateTime(2025, 12, 1), end: DateTime(2026, 1, 5)),
            now),
        '2025/12/01~2026/01/05',
      );
    });

    test('金额区间：最低大于最高时自动对调', () {
      final (lo, hi) =
          normalizeAmountRange(Decimal.fromInt(100), Decimal.fromInt(20));
      expect(lo, Decimal.fromInt(20));
      expect(hi, Decimal.fromInt(100));
      final (a, b) = normalizeAmountRange(Decimal.fromInt(5), null);
      expect(a, Decimal.fromInt(5));
      expect(b, isNull);
    });

    test('pageBgAt 取的是页面渐变色，不是灰白 appBg', () {
      expect(AppColors.pageBgAt(Brightness.light, 0),
          AppColors.warmBackgroundTop);
      expect(AppColors.pageBgAt(Brightness.light, 1),
          AppColors.warmBackgroundBottom);
      expect(AppColors.pageBgAt(Brightness.light, 0.1),
          isNot(const Color(0xFFF7F8FA)));
    });
  });

  group('搜索页', () {
    late Directory tmp;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('qingji_search_bills_test_');
      await databaseFactory.setDatabasesPath(tmp.path);
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<AppRepository> seed(WidgetTester tester) async {
      final repo = (await tester.runAsync(() async {
        final r = AppRepository();
        await r.init();
        final a = r.accounts.first.id;
        final b = await r.addAccount(name: '测试卡');
        await r.addTransaction(
          kind: TransactionKind.transfer,
          amount: Decimal.fromInt(50),
          accountId: a,
          toAccountId: b,
          date: DateTime(2026, 9, 1, 10),
        );
        await r.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(12),
          accountId: a,
          note: '前年的午饭',
          date: DateTime(2024, 3, 5, 12),
        );
        return r;
      }))!;
      addTearDown(() => tester.runAsync(repo.closeForTest));
      return repo;
    }

    Future<void> pumpSearch(WidgetTester tester, AppRepository repo) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: const MaterialApp(home: SearchView()),
        ),
      );
      await tester.pump();
    }

    Future<void> pickKind(WidgetTester tester, String label) async {
      await tester.tap(find.text('类型'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('顶部/底部虚化层用页面渐变色，不再盖出白带', (tester) async {
      final repo = await seed(tester);
      await pumpSearch(tester, repo);

      Color firstColor(String key) {
        final box = tester.widget<DecoratedBox>(find
            .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(DecoratedBox))
            .first);
        final g = (box.decoration as BoxDecoration).gradient!;
        return g.colors.first.withValues(alpha: 1);
      }

      final screenH = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(firstColor('search-top-fade'),
          AppColors.pageBgAt(Brightness.light, kToolbarHeight / screenH));
      expect(firstColor('search-top-fade'), isNot(const Color(0xFFF7F8FA)));
      expect(firstColor('search-bottom-fade'), isNot(const Color(0xFFF7F8FA)));
    });

    testWidgets('筛转账：顶部显示转账笔数和金额，菜单用统一勾选样式', (tester) async {
      final repo = await seed(tester);
      await pumpSearch(tester, repo);

      await tester.tap(find.text('类型'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('转账').last);
      await tester.pump(const Duration(milliseconds: 400));

      final summary = find.byKey(const ValueKey('search-summary'));
      expect(summary, findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('转账')),
          findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('共1笔')),
          findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('支出')),
          findsNothing);
    });

    // 从已删除的旧「明细」页测试迁来：日卡小计用退款后的净额，不计入的不进小计。
    testWidgets('日卡小计：部分退款按净额；不计入的不进小计', (tester) async {
      final repo = (await tester.runAsync(() async {
        final r = AppRepository();
        await r.init();
        final a = r.accounts.first.id;
        final date = DateTime(2026, 7, 14, 12, 30);
        final id = await r.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(100),
          accountId: a,
          note: '差旅费',
          date: date,
          reimbursable: true,
        );
        final original = r.visibleTransactions.firstWhere((t) => t.id == id);
        await r.refundTransaction(
          original,
          Decimal.fromInt(30),
          settledAt: date.add(const Duration(days: 1)),
          settlementAccountId: a,
        );
        await r.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(50),
          accountId: a,
          note: '代垫款',
          date: DateTime(2026, 7, 10, 9),
          reimbursable: true,
          excluded: true,
        );
        return r;
      }))!;
      addTearDown(() => tester.runAsync(repo.closeForTest));
      await pumpSearch(tester, repo);
      await pickKind(tester, '支出');

      final net = MoneyFormat.string(Decimal.fromInt(70)).replaceAll('¥', '');
      expect(find.text('支 $net'), findsOneWidget);
      // 只有「差旅费」那天有小计，「代垫款」那天不计入，没有小计。
      expect(find.textContaining('支 '), findsOneWidget);
      expect(find.text('不计入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('账单行按压用 PressableScale；非今年的日期带年份', (tester) async {
      final repo = await seed(tester);
      await pumpSearch(tester, repo);
      await pickKind(tester, '支出');

      expect(find.textContaining('2024年3月5日 周二'), findsOneWidget);
      expect(find.byKey(const ValueKey('tx-row-press')), findsWidgets);
      expect(
        find.ancestor(of: find.byType(TxRow), matching: find.byType(InkWell)),
        findsNothing,
      );
    });
  });
}
