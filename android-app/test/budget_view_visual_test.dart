// 预算页对照示意图（.tmp/budget_mockup.html：今天 9/18，日常每月 ¥4,000，中秋 9/25–27 每天 ¥300）
// 的离屏截图。普通测试只检查页面能画出来；要出图时：
//   UPDATE_BUDGET_UI_SCREENSHOTS=1 flutter test test/budget_view_visual_test.dart \
//     --dart-define=QINGJI_PARITY_CAPTURE=true \
//     --dart-define=QINGJI_DEMO_NOW=2026-09-18T12:00:00+08:00
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/core/budget/budget_rule_engine.dart';
import 'package:qingji/core/budget/budget_rule_status.dart';
import 'package:qingji/core/budget/budget_rules.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/budget/budget_calendar_card.dart';
import 'package:qingji/views/budget/budget_day_sheet.dart';
import 'package:qingji/views/budget/budget_hero_card.dart';
import 'package:qingji/views/budget/budget_view.dart';

import 'screenshot_font_support.dart';

class _MockupRepo extends AppRepository {
  _MockupRepo(this.rules, this.spend, this.dayTransactions);

  final List<BudgetRule> rules;
  final Map<int, int> spend;
  final List<TransactionEntity> dayTransactions;

  @override
  int get currentBookId => 1;

  @override
  List<BookEntity> get books => const [
        BookEntity(id: 1, name: '总账本', icon: '📒'),
      ];

  @override
  List<BudgetRule> budgetRulesForBook(int bookId) => List.unmodifiable(rules);

  @override
  Map<int, int> budgetSpendByDay(int bookId, {DateTime? asOf}) => spend;

  @override
  BudgetRolloverMode budgetRolloverModeFor(
    int bookId, {
    required int year,
    required int month,
  }) =>
      BudgetRolloverMode.reset;

  @override
  BudgetRuleSnapshot budgetRuleMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
  }) =>
      BudgetRuleSnapshot(
        bookId: 1,
        month: BudgetRuleEngine.resolveMonth(
          rules: rules,
          spendByDay: spend,
          year: month.year,
          month: month.month,
          today: budgetDay(asOf ?? AppClock.now),
        ),
      );

  @override
  List<TransactionRecord> recordsForBookView(int bookId) => const [];

  @override
  List<TransactionEntity> visibleTransactionsForBookView(int bookId) =>
      dayTransactions;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadScreenshotFonts();
    if (Platform.environment['UPDATE_BUDGET_UI_SCREENSHOTS'] == '1') {
      final emojiPath = Platform.environment['FEIMIAO_EMOJI_FONT'] ??
          r'C:\Windows\Fonts\seguiemj.ttf';
      final bytes = File(emojiPath).readAsBytesSync();
      await (FontLoader('BudgetScreenshotEmoji')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  final capture = Platform.environment['UPDATE_BUDGET_UI_SCREENSHOTS'] == '1';
  final now = AppClock.now;
  final year = now.year;
  final month = now.month;
  final outDir = Platform.environment['BUDGET_SHOT_OUTPUT'] ??
      '../outputs/ui_comparisons/2026-10-02-budget-takeover';
  final suffix = Platform.environment['BUDGET_SHOT_SUFFIX'] ?? 'after';

  void resetTheme() => AppColors.applyTheme(
        bgTop: AppColors.warmBackgroundTop,
        bgBottom: AppColors.warmBackgroundBottom,
        bgSolid: false,
        cardAlphaL: AppColors.cardAlphaLight,
        cardAlphaD: AppColors.cardAlphaDark,
        bgDark: const Color(0xFF211E1C),
        bgDarkTop: const Color(0xFF211E1C),
      );
  setUp(resetTheme);
  tearDown(resetTheme);

  _MockupRepo repo() {
    // 示意图里 9/1–9/17 每天花的钱（元）。
    const daily = [
      96,
      120,
      88,
      130,
      112,
      210,
      64,
      118,
      92,
      125,
      104,
      286,
      98,
      110,
      76,
      122,
      209,
    ];
    final spend = <int, int>{
      for (var i = 0; i < daily.length && i + 1 < now.day; i++)
        budgetDayKey(DateTime(year, month, i + 1)): daily[i] * 100,
    };
    DateTime d(int day) => DateTime(year, month, day);
    TransactionEntity tx(int id, int day, String yuan, String key, String name,
            String note) =>
        TransactionEntity(
          id: id,
          bookId: 1,
          kind: 'expense',
          amountStr: yuan,
          categoryKey: key,
          categoryNameZh: name,
          note: note,
          dateMs: d(day).add(Duration(hours: 12 + id)).millisecondsSinceEpoch,
          createdMs: d(day).millisecondsSinceEpoch,
        );
    return _MockupRepo(
      [
        BudgetRule(
          id: 1,
          bookId: 1,
          kind: BudgetRuleKind.base,
          amountCents: 400000,
          unit: BudgetRuleUnit.month,
          startDate: DateTime(year, month),
          createdMs: 1,
        ),
        BudgetRule(
          id: 2,
          bookId: 1,
          kind: BudgetRuleKind.special,
          name: '中秋',
          amountCents: 30000,
          unit: BudgetRuleUnit.day,
          startDate: d(25),
          endDate: d(27),
          funding: BudgetFunding.extra,
          createdMs: 2,
        ),
      ],
      spend,
      [
        tx(1, 12, '198', 'dining_dinner', '晚餐', '聚餐'),
        tx(2, 12, '66', 'shopping', '购物消费', '超市'),
        tx(3, 12, '22', 'transport', '出行交通', '打车'),
      ],
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    _MockupRepo repo, {
    Size size = const Size(390, 1240),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Widget home = const BudgetView(),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(repo.dispose);
    final theme =
        brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    const fallback = [screenshotCjkFontFamily, 'BudgetScreenshotEmoji'];
    final screenshotTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamilyFallback: fallback),
      primaryTextTheme:
          theme.primaryTextTheme.apply(fontFamilyFallback: fallback),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'Nunito',
          fontFamilyFallback: fallback,
        ),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('budget-capture'),
        child: ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: screenshotTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: DecoratedBox(
                decoration: AppColors.pageBackground(brightness),
                child: child,
              ),
            ),
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!capture) return;
    await expectLater(
      find.byKey(const ValueKey('budget-capture')),
      matchesGoldenFile('$outDir/${name}_$suffix.png'),
    );
  }

  testWidgets('预算主页（示意图第一屏）', (tester) async {
    await pumpPage(tester, repo());
    expect(find.byKey(const ValueKey('budget-hero-card')), findsOneWidget);
    if (suffix == 'after') {
      expect(find.byKey(const ValueKey('budget-rules-card')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    final cardRight = tester
        .getRect(
          find.byKey(const ValueKey('budget-hero-card')),
        )
        .right;
    expect(
      tester
          .getRect(find.byKey(const ValueKey('budget-hero-budget-caption')))
          .right,
      closeTo(cardRight - 18, 1),
    );
    await shot(tester, 'budget_main');
  });

  testWidgets('新增特别安排（示意图第二屏）', (tester) async {
    await pumpPage(tester, repo());
    await tester.tap(find.byKey(const ValueKey('budget-add-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选日期'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('budget-rule-name')), '国庆');
    await tester.enterText(
        find.byKey(const ValueKey('budget-rule-amount')), '200');
    await tester.pumpAndSettle();
    final first = DateTime(year, month, 28);
    final last = DateTime(year, month, 30);
    await tester
        .tap(find.byKey(ValueKey('budget-range-day-${budgetDayKey(first)}')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('budget-range-day-${budgetDayKey(last)}')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-rule-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_rule_sheet');
  });

  testWidgets('某一天详情（示意图第三屏）', (tester) async {
    await pumpPage(tester, repo());
    final day = DateTime(year, month, 12);
    if (!day.isBefore(budgetDay(now))) return; // 只在 12 号以后才有花费可看
    await tester.tap(find.byKey(ValueKey('budget-day-${budgetDayKey(day)}')));
    await tester.pumpAndSettle();
    expect(find.text('当天预算'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_day_sheet');
  });

  testWidgets('深色预算三屏继续使用主题而非白底', (tester) async {
    await pumpPage(tester, repo(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_main_dark');
    await tester.tap(find.byKey(const ValueKey('budget-add-rule')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_rule_sheet_dark');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('budget-day-${budgetDayKey(now)}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_day_sheet_dark');
  });

  testWidgets('樱粉主题详情格跟随弹层颜色', (tester) async {
    AppColors.applyTheme(
      bgTop: const Color(0xFFFAD2DF),
      bgBottom: const Color(0xFFFFF6F8),
      bgSolid: false,
      cardAlphaL: 0.4,
      cardAlphaD: 0.55,
      bgDark: const Color(0xFF242025),
      bgDarkTop: const Color(0xFF242025),
    );
    await pumpPage(tester, repo());
    await tester.tap(find.byKey(ValueKey('budget-day-${budgetDayKey(now)}')));
    await tester.pumpAndSettle();
    final scheme =
        Theme.of(tester.element(find.byType(BudgetDaySheet))).colorScheme;
    expect(budgetSheetTileFill(scheme), AppColors.sheetFill(scheme));
    expect(scheme.surface, const Color(0xFFFFF6F8));
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_day_sheet_pink');
  });

  testWidgets('320dp和200%大字：大金额与日历不溢出', (tester) async {
    final fixture = repo();
    final monthResult = BudgetRuleEngine.resolveMonth(
      rules: [
        BudgetRule(
          id: 1,
          bookId: 1,
          kind: BudgetRuleKind.base,
          amountCents: 12345678900,
          unit: BudgetRuleUnit.month,
          startDate: DateTime(year, month),
          createdMs: 1,
        ),
      ],
      spendByDay: fixture.spend,
      year: year,
      month: month,
      today: budgetDay(now),
    );
    await pumpPage(
      tester,
      fixture,
      size: const Size(320, 844),
      textScale: 2,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            BudgetHeroCard(
              month: monthResult,
              today: budgetDay(now),
              suggestionCents: null,
              nextMonthMode: BudgetRolloverMode.reset,
              onCreate: () {},
            ),
            const SizedBox(height: 12),
            BudgetCalendarCard(
              year: year,
              month: month,
              days: monthResult.days,
              spendByDay: fixture.spend,
              today: budgetDay(now),
              onPrev: () {},
              onNext: () {},
              onTapDay: (_) {},
            ),
          ]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_narrow_large_text');
  });

  testWidgets('详情大金额与200%大字不压缩成三列', (tester) async {
    final fixture = repo();
    addTearDown(fixture.dispose);
    final day = budgetDay(now);
    final detailRepo = _MockupRepo(
      fixture.rules,
      {budgetDayKey(day): 12345678900},
      const [],
    );
    await pumpPage(
      tester,
      detailRepo,
      size: const Size(320, 844),
      textScale: 2,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BudgetDaySheet(bookId: 1, day: day),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('budget-day-stats-rows')), findsOneWidget);
    expect(find.text('当天预算'), findsOneWidget);
    expect(find.text('花了'), findsOneWidget);
    expect(find.text('超了'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_day_narrow_large_text');
  });

  testWidgets('单日长安排：完整名称可查看且日期仍可点击', (tester) async {
    final fixture = repo();
    final day = budgetDay(now);
    const longName = '带家人出去玩和生日聚餐的特别安排';
    final rules = [
      fixture.rules.first,
      BudgetRule(
        id: 3,
        bookId: 1,
        kind: BudgetRuleKind.special,
        name: longName,
        amountCents: 10000,
        unit: BudgetRuleUnit.day,
        startDate: day,
        endDate: day,
        funding: BudgetFunding.extra,
        createdMs: 3,
      ),
    ];
    final result = BudgetRuleEngine.resolveMonth(
      rules: rules,
      spendByDay: fixture.spend,
      year: year,
      month: month,
      today: day,
    );
    DateTime? tappedDay;
    await pumpPage(
      tester,
      fixture,
      size: const Size(320, 844),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BudgetCalendarCard(
            year: year,
            month: month,
            days: result.days,
            spendByDay: fixture.spend,
            today: day,
            onPrev: () {},
            onNext: () {},
            onTapDay: (info) => tappedDay = info.day,
          ),
        ),
      ),
    );
    expect(find.byTooltip('$longName ¥100/天'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('$longName ¥100/天')).overflow,
      TextOverflow.ellipsis,
    );
    await tester.tap(find.byKey(ValueKey('budget-day-${budgetDayKey(day)}')));
    expect(tappedDay, day);
    expect(tester.takeException(), isNull);
    await shot(tester, 'budget_calendar_short_rule');
  });
}
