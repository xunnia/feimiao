import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_engine.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/core/transaction_time.dart';
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
  List<TransactionEntity> get visibleTransactionsRef => [transaction];

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

  testWidgets(
      'home budget card uses 15px month label and rounds overage percent',
      (tester) async {
    final summary = MonthlySummary(
      year: 2026,
      month: 8,
      totalExpense: Decimal.zero,
      totalIncome: Decimal.zero,
      expenseByCategory: [],
      dailyTotals: [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(100),
      spentThisMonth: Decimal.parse('125.5'),
      spentToday: Decimal.zero,
      remaining: Decimal.parse('-25.5'),
      todayAllowance: Decimal.zero,
      isOverBudget: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 8),
            isCurrentMonth: true,
            summary: summary,
            budgetStatus: status,
            budget: Decimal.fromInt(100),
          ),
        ),
      ),
    );

    final monthLabel = tester.widget<Text>(
      find.byKey(const ValueKey('home-summary-month-label')),
    );
    final monthSpan = monthLabel.textSpan! as TextSpan;
    final spans = monthSpan.children!.whereType<TextSpan>().toList();
    expect(spans.map((span) => span.text).join(), '2026年8月');
    expect(spans[0].style?.fontSize, 15);
    expect(spans[2].style?.fontSize, 15);
    expect(spans[1].style?.fontSize, 15);
    expect(spans[3].style?.fontSize, 15);
    expect(spans[0].style?.fontWeight, FontWeight.w500);
    expect(spans[2].style?.fontWeight, FontWeight.w500);
    expect(spans[1].style?.fontWeight, FontWeight.w400);
    expect(spans[3].style?.fontWeight, FontWeight.w400);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('home-budget-percent')),
          )
          .data,
      '126%',
    );

    final overLabel = tester.widget<Text>(find.text('月预算已超'));
    expect(overLabel.style?.fontVariations, hasLength(1));
    expect(overLabel.style?.fontVariations?.single.value, 350);
  });

  test('income is green and budget caution stays gold', () {
    final light = AppTheme.light().colorScheme;
    final dark = AppTheme.dark().colorScheme;
    expect(AppColors.income(light), AppColors.incomeLightMode);
    expect(AppColors.income(dark), AppColors.incomeDarkMode);
    expect(AppColors.budgetCaution(light), kCatGold);
    // 渐变中段仍是金色，收入改绿不影响预算条观感。
    expect(BudgetProgressPalette.gradient(light).colors[1], kCatGold);
  });

  testWidgets('overflow bar splits at the 100% budget line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 200,
            child: BudgetProgressBar(value: 1, overflowStart: 0.7),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('budget-progress-track')), findsNothing);
    final overflow = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('budget-progress-overflow')),
    );
    expect(overflow.color, AppColors.warning);
    // 预算内那段是同一个橙的浅色，不再是绿→金渐变。
    final within = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('budget-progress-fill-clip')),
    );
    final withinColor = within.color;
    expect(
      (withinColor.r, withinColor.g, withinColor.b),
      (AppColors.warning.r, AppColors.warning.g, AppColors.warning.b),
    );
    expect(withinColor.a, lessThan(1));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('budget-progress-fill-clip')))
          .width,
      closeTo(140, 0.01),
    );
    final boundary =
        tester.getRect(find.byKey(const ValueKey('budget-progress-boundary')));
    expect(boundary.center.dx - tester.getTopLeft(find.byType(BudgetProgressBar)).dx,
        closeTo(140, 0.01));
  });

  testWidgets('overspent home card: no minus, warning chip, today ¥0 ring',
      (tester) async {
    final summary = MonthlySummary(
      year: 2026,
      month: 9,
      totalExpense: Decimal.fromInt(4512),
      totalIncome: Decimal.fromInt(500),
      expenseByCategory: const [],
      dailyTotals: const [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(3200),
      spentThisMonth: Decimal.fromInt(4512),
      spentToday: Decimal.parse('2208.95'),
      remaining: Decimal.fromInt(-1312),
      todayAllowance: Decimal.parse('-1217.90'),
      isOverBudget: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 9),
            isCurrentMonth: true,
            summary: summary,
            budgetStatus: status,
            budget: Decimal.fromInt(3200),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('月预算已超'), findsOneWidget);
    expect(find.textContaining('-¥'), findsNothing);
    expect(find.text('¥1,312.00'), findsOneWidget);

    final chip = tester.widget<Container>(
      find.byKey(const ValueKey('home-budget-percent-chip')),
    );
    expect(
      (chip.decoration as BoxDecoration).color,
      AppColors.warning.withValues(alpha: 0.16),
    );
    final pct = tester.widget<Text>(
      find.byKey(const ValueKey('home-budget-percent')),
    );
    expect(pct.data, '141%');
    expect(pct.style?.color, AppColors.warning);

    // 横条：预算线在 3200/4512 ≈ 70.9% 处。
    final barWidth = tester.getSize(find.byType(BudgetProgressBar)).width;
    expect(
      tester
              .getSize(find.byKey(const ValueKey('budget-progress-fill-clip')))
              .width /
          barWidth,
      closeTo(3200 / 4512, 0.001),
    );

    // 右下角标明是预算总额。
    expect(find.textContaining('预算 ¥3,200.00'), findsOneWidget);

    // 圆环：月预算已超，改显示「今日已花」；日额度 991.05 / 今日已花 2208.95 ≈ 44.9%。
    expect(find.text('今日可用'), findsNothing);
    expect(find.text('今日已花'), findsOneWidget);
    expect(find.text('¥2,208.95'), findsOneWidget);
    final ring = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('budget-progress-ring-overflow')),
    );
    final painter = ring.painter! as BudgetOverflowRingPainter;
    expect(painter.withinFraction, closeTo(991.05 / 2208.95, 0.0001));
    expect(painter.overflowColor, AppColors.warning);
  });

  testWidgets(
      'over budget with nothing spent today: empty ring, grey zero income, '
      'ring sits on the percent row', (tester) async {
    // 真机截图场景：预算 4000，本月已花 4419.02，今天还没花。
    final summary = MonthlySummary(
      year: 2026,
      month: 9,
      totalExpense: Decimal.parse('4419.02'),
      totalIncome: Decimal.zero,
      expenseByCategory: const [],
      dailyTotals: const [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(4000),
      spentThisMonth: Decimal.parse('4419.02'),
      spentToday: Decimal.zero,
      remaining: Decimal.parse('-419.02'),
      todayAllowance: Decimal.parse('-209.51'),
      isOverBudget: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 9),
            isCurrentMonth: true,
            summary: summary,
            budgetStatus: status,
            budget: Decimal.fromInt(4000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 今天没花钱：显示「今日已花 ¥0.00」，不画满圈超支，只留浅橙底圈。
    expect(find.text('今日已花'), findsOneWidget);
    expect(find.text('¥0.00'), findsNWidgets(2)); // 收入 ¥0.00 + 今日已花 ¥0.00
    expect(
      find.byKey(const ValueKey('budget-progress-ring-overflow')),
      findsNothing,
    );
    final fill = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('budget-progress-ring-fill')),
    );
    expect(fill.value, 0);
    expect(fill.color, AppColors.warning);

    // 圆环底边与百分比标签那一行对齐。
    final ringRect =
        tester.getRect(find.byKey(const ValueKey('home-today-ring')));
    final chipRect = tester
        .getRect(find.byKey(const ValueKey('home-budget-percent-chip')));
    expect(ringRect.bottom, closeTo(chipRect.bottom, 2));
  });

  test('home income is green only when there is income', () {
    final scheme = AppTheme.light().colorScheme;
    expect(homeIncomeColor(scheme, Decimal.zero), scheme.onSurfaceVariant);
    expect(homeIncomeColor(scheme, Decimal.one), AppColors.income(scheme));
  });

  test('home daily average: today ordinal this month, full month for history',
      () {
    final today = DateTime(2026, 9, 29, 14);
    // 本月：4419.02 / 29 = 152.3800… → 152.38
    expect(
      homeDailyAverageExpense(
        Decimal.parse('4419.02'),
        year: 2026,
        month: 9,
        isCurrentMonth: true,
        today: today,
      ),
      Decimal.parse('152.38'),
    );
    // 历史月（8 月 31 天）：1000 / 31 = 32.2580… → 32.26（四舍五入）
    expect(
      homeDailyAverageExpense(
        Decimal.fromInt(1000),
        year: 2026,
        month: 8,
        isCurrentMonth: false,
        today: today,
      ),
      Decimal.parse('32.26'),
    );
    // 2 月按实际天数（2028 闰年 29 天）
    expect(
      homeDailyAverageExpense(
        Decimal.fromInt(290),
        year: 2028,
        month: 2,
        isCurrentMonth: false,
        today: today,
      ),
      Decimal.fromInt(10),
    );
    expect(
      homeDailyAverageExpense(
        Decimal.zero,
        year: 2026,
        month: 8,
        isCurrentMonth: false,
        today: today,
      ),
      Decimal.zero,
    );
  });

  testWidgets(
      'historical month ring shows daily average instead of repeating percent',
      (tester) async {
    final summary = MonthlySummary(
      year: 2026,
      month: 8,
      totalExpense: Decimal.fromInt(4400),
      totalIncome: Decimal.zero,
      expenseByCategory: const [],
      dailyTotals: const [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(4000),
      spentThisMonth: Decimal.fromInt(4400),
      spentToday: Decimal.zero,
      remaining: Decimal.fromInt(-400),
      todayAllowance: Decimal.zero,
      isOverBudget: true,
      hasDailyGuidance: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 8),
            isCurrentMonth: false,
            summary: summary,
            budgetStatus: status,
            budget: Decimal.fromInt(4000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 110% 只在左边标签出现一次；圆环写日均 4400/31 = 141.94。
    expect(find.text('110%'), findsOneWidget);
    expect(find.text('已用'), findsNothing);
    expect(find.text('日均支出'), findsOneWidget);
    expect(find.text('¥141.94'), findsOneWidget);
    // 历史月没有「剩 N 天」，但仍标明是预算。
    expect(find.textContaining('剩'), findsNothing);
    expect(find.textContaining('预算 ¥4,000.00'), findsOneWidget);
    // 圆环仍按已用比例画超支分界：4000/4400。
    final ring = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('budget-progress-ring-overflow')),
    );
    final painter = ring.painter! as BudgetOverflowRingPainter;
    expect(painter.withinFraction, closeTo(4000 / 4400, 0.0001));
  });

  testWidgets('recurring transaction row shows 周期 before the category',
      (tester) async {
    final repository = AppRepository();
    addTearDown(repository.dispose);
    final date = DateTime(2026, 9, 1);
    final tx = TransactionEntity(
      id: 7,
      bookId: 1,
      kind: 'expense',
      amountStr: '3000',
      categoryKey: 'housing',
      categoryNameZh: '居家住房',
      note: '房租',
      dateMs: date.millisecondsSinceEpoch,
      createdMs: date.millisecondsSinceEpoch,
      timePrecision: TransactionTimePrecision.dateOnly,
      recurringRuleId: 3,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: TxRow(transaction: tx)),
        ),
      ),
    );

    expect(find.text('周期 · 居家住房'), findsOneWidget);
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
          home: const Scaffold(
            body: HomeView(
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
