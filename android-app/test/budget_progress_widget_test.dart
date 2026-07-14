import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_engine.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/home_view.dart';
import 'package:qingji/widgets/budget_progress.dart';
import 'package:qingji/widgets/home_summary_card.dart';
import 'package:qingji/widgets/transaction_day_list.dart';

class _HomeSpacingRepository extends AppRepository {
  _HomeSpacingRepository() {
    final now = DateTime.now();
    transaction = TransactionEntity(
      id: 1,
      bookId: 1,
      kind: 'expense',
      amountStr: '20',
      categoryKey: 'dining',
      categoryNameZh: '食品餐饮',
      note: '午餐',
      dateMs: now.millisecondsSinceEpoch,
      createdMs: now.millisecondsSinceEpoch,
    );
  }

  late final TransactionEntity transaction;

  @override
  List<TransactionEntity> get visibleTransactions => [transaction];

  @override
  List<TransactionRecord> get allRecords => [transaction.toRecord()];

  @override
  BudgetWindowResult budgetForCalendarMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) {
    final now = asOf ?? DateTime.now();
    return BudgetWindowResolver.resolve(
      query: BudgetWindowQuery(
        viewKind: BudgetViewKind.calendarMonth,
        bookId: bookId ?? 1,
        referenceDate: month,
        asOf: now,
        knowledgeCutoff: knowledgeCutoff ?? now,
      ),
      periods: const [],
    );
  }
}

void main() {
  test('budget palette restores green and keeps the track on endpoint hue', () {
    final light = AppTheme.light().colorScheme;
    final dark = AppTheme.dark().colorScheme;

    expect(
      BudgetProgressPalette.colorAt(light, 0),
      AppColors.budgetHealthy(light),
    );
    expect(
      AppColors.budgetHealthy(light),
      const Color(0xFF7FB069),
    );
    expect(
      BudgetProgressPalette.colorAt(light, 1),
      AppColors.warning,
    );
    expect(
      BudgetProgressPalette.colorAt(dark, 0),
      AppColors.budgetHealthy(dark),
    );

    final endpoint = BudgetProgressPalette.colorAt(light, 0.83);
    final track = BudgetProgressPalette.trackColor(light, endpoint);
    final outline = BudgetProgressPalette.trackOutlineColor(light, endpoint);
    expect((track.r, track.g, track.b), (endpoint.r, endpoint.g, endpoint.b));
    expect(
      (outline.r, outline.g, outline.b),
      (endpoint.r, endpoint.g, endpoint.b),
    );
    expect(outline.a, greaterThan(track.a));
  });

  testWidgets('budget bar and ring use tinted tracks with darker outlines',
      (tester) async {
    final scheme = AppTheme.light().colorScheme;
    final endpoint = BudgetProgressPalette.colorAt(scheme, 0.83);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 220,
                child: BudgetProgressBar(value: 0.83),
              ),
              SizedBox(
                width: 80,
                height: 80,
                child: BudgetProgressRing(
                  value: 0.4,
                  activeColor: Color(0xFF7FB069),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final trackBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('budget-progress-track')),
    );
    final trackDecoration = trackBox.decoration as BoxDecoration;
    expect(
      trackDecoration.border!.top.color,
      BudgetProgressPalette.trackOutlineColor(scheme, endpoint),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('budget-progress-fill-clip')),
          )
          .width,
      closeTo(220 * 0.83, 0.01),
    );

    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('budget-progress-ring-fill')),
    );
    final outline = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('budget-progress-ring-outline')),
    );
    const green = Color(0xFF7FB069);
    expect(ring.color, green);
    expect(
      ring.backgroundColor,
      BudgetProgressPalette.trackColor(scheme, green),
    );
    expect(
      outline.color,
      BudgetProgressPalette.trackOutlineColor(scheme, green),
    );
  });

  testWidgets('home budget card keeps healthy ring green', (tester) async {
    final summary = MonthlySummary(
      year: 2026,
      month: 7,
      totalExpense: Decimal.fromInt(200),
      totalIncome: Decimal.fromInt(1000),
      expenseByCategory: const [],
      dailyTotals: const [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(1000),
      spentThisMonth: Decimal.fromInt(200),
      spentToday: Decimal.fromInt(20),
      remaining: Decimal.fromInt(800),
      todayAllowance: Decimal.fromInt(30),
      isOverBudget: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 7),
            isCurrentMonth: true,
            summary: summary,
            budgetStatus: status,
            budget: Decimal.fromInt(1000),
          ),
        ),
      ),
    );

    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('budget-progress-ring-fill')),
    );
    expect(ring.color, AppColors.budgetHealthy(AppTheme.light().colorScheme));
  });

  testWidgets('home filter has the same gap above and below', (tester) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _HomeSpacingRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeView(
              onShowTransactions: () {},
              bottomInset: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final summary = tester.getRect(
      find.byKey(const ValueKey('home-summary-card-surface')),
    );
    final filter = tester.getRect(
      find.byKey(const ValueKey('home-filter-control')),
    );
    final firstDayCard = tester.getRect(find.byType(TxDayCard).first);
    final upperGap = filter.top - summary.bottom;
    final lowerGap = firstDayCard.top - filter.bottom;

    expect(upperGap, closeTo(8, 0.01));
    expect(lowerGap, closeTo(8, 0.01));
    expect(upperGap, closeTo(lowerGap, 0.01));
  });
}
