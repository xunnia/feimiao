import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/models/recurring_rule.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/import/bill_import.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/main.dart' as app;
import 'package:qingji/share_intake.dart';
import 'package:qingji/views/assistant/meow_assistant_view.dart';
import 'package:qingji/views/quick_add/quick_add_view.dart';
import 'package:qingji/views/reports/report_views.dart';
import 'package:qingji/views/savings/savings_goals_view.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:qingji/views/settings/ai_setting_view.dart';
import 'package:qingji/views/settings/ai_companion_views.dart';
import 'package:qingji/views/settings/backup_view.dart';
import 'package:qingji/views/settings/bill_review_view.dart';
import 'package:qingji/views/settings/budget_setting_view.dart';
import 'package:qingji/views/settings/categories_view.dart';
import 'package:qingji/views/settings/memory_view.dart';
import 'package:qingji/views/settings/recurring_view.dart';
import 'package:qingji/views/settings/settings_view.dart';
import 'package:qingji/views/settings/tags_view.dart';
import 'package:qingji/views/settings/theme_settings_view.dart';
import 'package:qingji/views/settings/transaction_display_settings.dart';
import 'package:qingji/views/statistics/statistics_view.dart';
import 'package:qingji/views/transactions/reimburse_view.dart';
import 'package:qingji/views/transactions/transaction_list_view.dart';
import 'package:qingji/widgets/app_buttons.dart';

/// Android-side source for the paired screenshots declared in
/// ios-app/tools/screenshot_manifest.json.
///
/// This is deliberately an integration test instead of a production demo
/// switch: the real Flutter widgets are rendered on a real Android emulator,
/// while the fixture is inserted through the same repository API a user uses.
bool _surfaceConverted = false;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Android parity screens', (tester) async {
    _surfaceConverted = false;
    await app.main();
    await _pumpFor(tester, const Duration(seconds: 2));

    final repo = _repositoryFromNavigator();
    await repo.fullyReady;
    await _ensureFixture(repo);
    await _pumpFor(tester, const Duration(milliseconds: 500));

    await _takeScreenshot(tester, binding, 'home-overview-android');
    // The drawer button belongs to the root shell. Capture it before pushing
    // page routes that intentionally remain mounted for the rest of the run.
    await _captureBooks(tester, binding);

    await _capturePage(
      tester,
      'quick-add-android',
      const QuickAddView(),
      binding,
    );
    await _capturePage(
      tester,
      'transactions-android',
      const TransactionListView(),
      binding,
    );

    await _captureStatistics(tester, binding, '周', 'stats-week-android');
    await _captureStatistics(tester, binding, '月', 'stats-month-android');
    await _captureStatistics(tester, binding, '年', 'stats-year-android');
    await _captureStatistics(tester, binding, '自定义', 'stats-custom-android');

    await _capturePage(
      tester,
      'budget-android',
      const BudgetSettingView(),
      binding,
    );
    await _captureAssetTab(
      tester,
      'reconcile-android',
      '资金',
      binding,
    );
    await _capturePage(
      tester,
      'reimburse-android',
      const ReimburseView(),
      binding,
    );
    await _capturePage(
      tester,
      'savings-android',
      const SavingsGoalsView(),
      binding,
    );
    await _capturePage(
      tester,
      'recurring-android',
      const RecurringView(),
      binding,
    );
    await _captureAssetTab(
      tester,
      'assets-android',
      '物品',
      binding,
    );
    await _captureAssetTab(
      tester,
      'liabilities-android',
      '资金',
      binding,
    );
    await _captureAssetTab(
      tester,
      'net-worth-android',
      '总览',
      binding,
    );
    // Accounts, reconciliation, liabilities and net worth are intentionally
    // represented by the Android asset hub's corresponding tabs.
    await _captureAssetTab(tester, 'accounts-android', '资金', binding);
    await _capturePage(
      tester,
      'categories-android',
      const CategoriesView(),
      binding,
    );
    await _capturePage(
      tester,
      'tags-android',
      const TagsView(),
      binding,
    );
    await _capturePage(
      tester,
      'settings-android',
      const SettingsView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-android',
      const MeowAssistantView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-settings-android',
      const AiSettingView(),
      binding,
    );
    await _capturePage(
      tester,
      'memory-android',
      const MemoryView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-tasks-android',
      const AiTaskCenterView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-diagnostics-android',
      const AiDiagnosticsView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-search-android',
      const AiUnifiedSearchView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-memory-android',
      const AiMemoryControlView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-extensions-android',
      const AiSkillsAndConnectorsView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-schedules-android',
      const AiReportScheduleView(),
      binding,
    );
    await _capturePage(
      tester,
      'ai-local-android',
      const LocalModelCompanionView(),
      binding,
    );
    await _capturePage(
      tester,
      'backup-android',
      const BackupView(),
      binding,
    );
    await _capturePage(
      tester,
      'theme-android',
      const ThemeSettingsView(),
      binding,
    );
    await _captureDisplaySettings(tester, binding);
    await _capturePage(
      tester,
      'import-review-android',
      BillReviewView(
        rows: _demoImportRows(),
        source: '支付宝',
        skipped: 2,
      ),
      binding,
    );
    await _captureReports(tester, binding);
  });
}

Future<void> _captureDisplaySettings(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(
      _parityPageRoute<void>(const _DisplayCaptureShell()),
    ),
  );
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _takeScreenshot(tester, binding, 'display-android');
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 300));
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 300));
}

PageRoute<T> _parityPageRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );

/// Advance the fake clock in bounded steps without waiting for every
/// repeating animation to become idle. The parity driver only needs a stable
/// amount of render time; an unbounded pumpAndSettle can hang forever on the
/// home screen's live widgets.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const quantum = Duration(milliseconds: 100);
  var remaining = duration;
  while (remaining > Duration.zero) {
    final step = remaining < quantum ? remaining : quantum;
    await tester.pump(step);
    remaining -= step;
  }
}

class _DisplayCaptureShell extends StatefulWidget {
  const _DisplayCaptureShell();

  @override
  State<_DisplayCaptureShell> createState() => _DisplayCaptureShellState();
}

class _DisplayCaptureShellState extends State<_DisplayCaptureShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showTransactionDisplaySettings(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

List<ImportedBillRow> _demoImportRows() {
  final now = DateTime(2026, 8, 27, 12);
  DateTime daysAgo(int value) {
    final date = now.subtract(Duration(days: value));
    return DateTime(date.year, date.month, date.day, 12);
  }

  const order = 'PARITY-ORDER-100';
  return [
    ImportedBillRow(
      date: daysAgo(1),
      kind: TransactionKind.expense,
      category: '',
      note: '京东 · 机械键盘',
      amount: Decimal.parse('280'),
      merchant: '京东-订单编号349126',
      product: '机械键盘',
      orderNo: order,
    ),
    ImportedBillRow(
      date: daysAgo(2),
      kind: TransactionKind.expense,
      category: '',
      note: '转账',
      amount: Decimal.parse('48'),
      merchant: 'M&X*^O^*',
    ),
    ImportedBillRow(
      date: daysAgo(3),
      kind: TransactionKind.expense,
      category: '',
      note: '日常消费',
      amount: Decimal.parse('26'),
      merchant: 'M&X*^O^*',
    ),
    ImportedBillRow(
      date: now,
      kind: TransactionKind.expense,
      category: '',
      note: '退款 · 机械键盘',
      amount: Decimal.parse('280'),
      merchant: '京东',
      product: '机械键盘退款',
      orderNo: order,
      isRefund: true,
    ),
  ];
}

AppRepository _repositoryFromNavigator() {
  final context = ShareIntake.navigatorKey.currentContext;
  if (context == null) {
    throw StateError('应用根导航上下文尚未就绪');
  }
  return Provider.of<AppRepository>(context, listen: false);
}

Future<void> _capturePage(
  WidgetTester tester,
  String name,
  Widget page,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  debugPrint('PARITY_PAGE_BEGIN name=$name');
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(_parityPageRoute<void>(page)),
  );
  await _pumpFor(tester, const Duration(milliseconds: 700));
  await _takeScreenshot(tester, binding, name);
  // Keep captured routes mounted until the driver exits. Repeatedly popping
  // opaque routes while the Android surface is an ImageView can make Flutter
  // tear down a live widget tree before the next frame is delivered.
  debugPrint('PARITY_PAGE_READY name=$name');
}

Future<void> _captureReports(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(
      _parityPageRoute<void>(const _ReportCaptureShell()),
    ),
  );
  await _pumpFor(tester, const Duration(milliseconds: 900));
  expect(find.text('报告'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'reports-android');
  // Leave the final report sheet mounted. Popping a modal and its capture
  // shell immediately after PixelCopy can trigger a framework disposal error;
  // the test process is ending, so the runner can reclaim both routes.
}

class _ReportCaptureShell extends StatefulWidget {
  const _ReportCaptureShell();

  @override
  State<_ReportCaptureShell> createState() => _ReportCaptureShellState();
}

class _ReportCaptureShellState extends State<_ReportCaptureShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showReportLibrarySheet(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}

Future<void> _captureAssetTab(
  WidgetTester tester,
  String name,
  String tab,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(
      _parityPageRoute<void>(const AccountsView()),
    ),
  );
  await _pumpFor(tester, const Duration(milliseconds: 700));
  final option = find.text(tab);
  expect(option, findsAtLeastNWidgets(1));
  await tester.tap(option.first);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _takeScreenshot(tester, binding, name);
}

Future<void> _captureBooks(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final button = find.byType(AppDrawerButton);
  expect(button, findsAtLeastNWidgets(1));
  await tester.tap(button.first);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('我的账本'), findsOneWidget);
  await _takeScreenshot(tester, binding, 'books-android');
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width - 8, size.height / 2));
  await _pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _captureStatistics(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String range,
  String name,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(
      _parityPageRoute<void>(const StatisticsView()),
    ),
  );
  await _pumpFor(tester, const Duration(milliseconds: 700));
  final option = find.text(range);
  if (option.evaluate().isNotEmpty) {
    await tester.tap(option.first);
    await _pumpFor(tester, const Duration(milliseconds: 500));
  }
  await _takeScreenshot(tester, binding, name);
}

Future<void> _takeScreenshot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // The Android integration plugin replaces the Flutter surface with an
  // ImageView for capture. It must be converted only once per test; the
  // binding restores it automatically during test teardown.
  debugPrint(
    'PARITY_CAPTURE_BEGIN name=$name surfaceConverted=$_surfaceConverted',
  );
  if (!_surfaceConverted) {
    await binding.convertFlutterSurfaceToImage();
    _surfaceConverted = true;
  }
  await tester.pump();
  await binding.takeScreenshot(name);
  debugPrint('PARITY_CAPTURE_DONE name=$name');
}

Future<void> _ensureFixture(AppRepository repo) async {
  const marker = '[parity]';
  final alreadySeeded = repo.transactions.any((transaction) {
    if (transaction.note.startsWith(marker)) return true;
    return transaction.note == '午餐 麦当劳' &&
        transaction.amount == Decimal.parse('38');
  });
  if (alreadySeeded) {
    await _ensureReport(repo);
    return;
  }

  var accounts = repo.transactionAccounts.toList(growable: false);
  if (!accounts.any((account) => account.type == AccountType.debit)) {
    await repo.addAccount(
      name: 'Parity银行卡',
      type: AccountType.debit,
      openingBalance: Decimal.parse('12000'),
    );
    await repo.fullyReady;
    accounts = repo.transactionAccounts.toList(growable: false);
  }
  if (!accounts.any((account) => account.type == AccountType.credit)) {
    await repo.addAccount(
      name: 'Parity信用卡',
      type: AccountType.credit,
      openingBalance: Decimal.parse('-1800'),
    );
    await repo.fullyReady;
    accounts = repo.transactionAccounts.toList(growable: false);
  }
  expect(accounts.any((account) => account.type == AccountType.cash), isTrue);
  expect(accounts.any((account) => account.type == AccountType.debit), isTrue);
  final cash =
      accounts.firstWhere((account) => account.type == AccountType.cash);
  final bank =
      accounts.firstWhere((account) => account.type == AccountType.debit);
  final bookID = repo.currentBookId;

  int? category(String key) {
    for (final item in repo.categories) {
      if (item.key == key) return item.id;
    }
    return null;
  }

  final now = DateTime(2026, 8, 27, 12);
  DateTime daysAgo(int amount) {
    final day = now.subtract(Duration(days: amount));
    return DateTime(day.year, day.month, day.day, 12);
  }

  Future<int> add({
    required TransactionKind kind,
    required String amount,
    String? categoryKey,
    required AccountEntity account,
    AccountEntity? toAccount,
    required String note,
    required DateTime date,
    bool reimbursable = false,
    required String sourceID,
  }) {
    return repo.addTransaction(
      kind: kind,
      amount: Decimal.parse(amount),
      categoryId: categoryKey == null ? null : category(categoryKey),
      accountId: account.id,
      toAccountId: toAccount?.id,
      note: note,
      date: date,
      reimbursable: reimbursable,
      bookId: bookID,
      autoRecordSourceId: sourceID,
    );
  }

  // Keep the visible core fixture aligned with DemoDataSeeder.swift. The
  // source IDs make retries idempotent without putting a test marker in notes.
  final thisMonth = <({
    String amount,
    TransactionKind kind,
    String category,
    String note,
    AccountEntity account
  })>[
    (
      amount: '38',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '午餐 麦当劳',
      account: cash
    ),
    (
      amount: '23',
      kind: TransactionKind.expense,
      category: 'transport',
      note: '滴滴打车',
      account: cash
    ),
    (
      amount: '156',
      kind: TransactionKind.expense,
      category: 'groceries',
      note: '盒马超市',
      account: cash
    ),
    (
      amount: '88',
      kind: TransactionKind.expense,
      category: 'entertainment',
      note: '网易云音乐年费',
      account: cash
    ),
    (
      amount: '45',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '晚餐 外卖',
      account: cash
    ),
    (
      amount: '198',
      kind: TransactionKind.expense,
      category: 'shopping',
      note: '优衣库 T 恤',
      account: bank
    ),
    (
      amount: '12',
      kind: TransactionKind.expense,
      category: 'transport',
      note: '公交充值',
      account: cash
    ),
    (
      amount: '68',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '朋友聚餐 AA',
      account: cash
    ),
    (
      amount: '30',
      kind: TransactionKind.expense,
      category: 'utilities',
      note: '话费充值',
      account: cash
    ),
    (
      amount: '280',
      kind: TransactionKind.expense,
      category: 'shopping',
      note: '京东 数据线+充电头',
      account: bank
    ),
    (
      amount: '9.9',
      kind: TransactionKind.expense,
      category: 'subscription',
      note: '微信读书月卡',
      account: cash
    ),
    (
      amount: '15',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '咖啡 瑞幸',
      account: cash
    ),
    (
      amount: '52',
      kind: TransactionKind.expense,
      category: 'groceries',
      note: '菜市场买菜',
      account: cash
    ),
    (
      amount: '18',
      kind: TransactionKind.expense,
      category: 'transport',
      note: '共享单车月卡',
      account: cash
    ),
    (
      amount: '120',
      kind: TransactionKind.income,
      category: 'salary',
      note: '兼职收入',
      account: bank
    ),
    (
      amount: '500',
      kind: TransactionKind.income,
      category: 'redPacket',
      note: '朋友红包',
      account: cash
    ),
  ];
  for (var index = 0; index < thisMonth.length; index++) {
    final row = thisMonth[index];
    await add(
      kind: row.kind,
      amount: row.amount,
      categoryKey: row.category,
      account: row.account,
      note: row.note,
      date: daysAgo(index * 2),
      sourceID: 'parity-v1-current-$index',
    );
  }

  final lastMonth = <({
    String amount,
    TransactionKind kind,
    String category,
    String note,
    AccountEntity account
  })>[
    (
      amount: '42',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '午餐',
      account: cash
    ),
    (
      amount: '320',
      kind: TransactionKind.expense,
      category: 'housing',
      note: '房租（水电）',
      account: bank
    ),
    (
      amount: '76',
      kind: TransactionKind.expense,
      category: 'groceries',
      note: '超市采购',
      account: cash
    ),
    (
      amount: '25',
      kind: TransactionKind.expense,
      category: 'transport',
      note: '出租车',
      account: cash
    ),
    (
      amount: '8800',
      kind: TransactionKind.income,
      category: 'salary',
      note: '7 月工资',
      account: bank
    ),
    (
      amount: '560',
      kind: TransactionKind.expense,
      category: 'shopping',
      note: '网购衣物',
      account: bank
    ),
    (
      amount: '35',
      kind: TransactionKind.expense,
      category: 'medical',
      note: '药店',
      account: cash
    ),
  ];
  for (var index = 0; index < lastMonth.length; index++) {
    final row = lastMonth[index];
    await add(
      kind: row.kind,
      amount: row.amount,
      categoryKey: row.category,
      account: row.account,
      note: row.note,
      date: DateTime(now.year, now.month - 1, index + 3, 12),
      sourceID: 'parity-v1-last-$index',
    );
  }

  final twoMonthsAgo =
      <({String amount, TransactionKind kind, String category, String note})>[
    (
      amount: '8800',
      kind: TransactionKind.income,
      category: 'salary',
      note: '6 月工资'
    ),
    (
      amount: '380',
      kind: TransactionKind.expense,
      category: 'travel',
      note: '周末游'
    ),
    (
      amount: '95',
      kind: TransactionKind.expense,
      category: 'dining',
      note: '朋友生日聚餐'
    ),
    (
      amount: '290',
      kind: TransactionKind.expense,
      category: 'education',
      note: '极客时间年卡'
    ),
    (
      amount: '18',
      kind: TransactionKind.expense,
      category: 'transport',
      note: '高铁票'
    ),
  ];
  for (var index = 0; index < twoMonthsAgo.length; index++) {
    final row = twoMonthsAgo[index];
    await add(
      kind: row.kind,
      amount: row.amount,
      categoryKey: row.category,
      account: bank,
      note: row.note,
      date: DateTime(now.year, now.month - 2, index + 5, 12),
      sourceID: 'parity-v1-before-$index',
    );
  }

  await add(
    kind: TransactionKind.transfer,
    amount: '120',
    account: cash,
    toAccount: bank,
    note: '账户转入',
    date: daysAgo(10),
    sourceID: 'parity-v1-transfer',
  );

  final lunch = repo.transactions.firstWhere(
    (transaction) => transaction.note == '午餐 麦当劳',
  );
  await repo.refundTransaction(
    lunch,
    Decimal.parse('15'),
    settledAt: daysAgo(0),
    settlementAccountId: cash.id,
  );

  if (!repo.budgetPeriods.any((period) => period.bookId == bookID)) {
    await repo.addBudgetPeriod(
      bookId: bookID,
      start: DateTime(now.year, now.month, 1),
      total: Decimal.parse('3000'),
      categoryBudgets: {
        'dining': Decimal.parse('600'),
        'shopping': Decimal.parse('800'),
      },
      monthlyIncome: Decimal.parse('8800'),
    );
  }
  if (repo.savingsGoals.isEmpty) {
    await repo.addSavingsGoal(
      name: '东京旅行',
      target: Decimal.parse('12000'),
      emoji: '✈️',
      initialSaved: Decimal.parse('6800'),
    );
  }
  if (repo.recurringRules.isEmpty) {
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('3200'),
      categoryId: category('housing'),
      accountId: bank.id,
      bookId: bookID,
      note: '房租',
      period: RecurPeriod.monthly,
      startDate: now.add(const Duration(days: 3)),
    );
  }
  await _ensureReport(repo);
}

Future<void> _ensureReport(AppRepository repo) async {
  if (repo.reports.isNotEmpty) return;
  await repo.addReport(
    type: 'monthly',
    title: '2026年8月账单报告',
    summary: '支出 ¥1,017.90 · 收入 ¥620.00',
    markdown: '# 2026年8月账单报告\n\n'
        '- 支出：¥1,017.90\n'
        '- 收入：¥620.00\n'
        '- 结余：¥-397.90\n\n'
        '## 支出分类\n\n'
        '- 餐饮：¥151.00（4笔）\n'
        '- 购物：¥478.00（2笔）\n'
        '- 出行：¥53.00（3笔）\n'
        '- 食品：¥208.00（2笔）',
    periodStart: DateTime(2026, 8, 1),
    periodEnd: DateTime(2026, 8, 31, 23, 59, 59),
    bookId: repo.currentBookId,
  );
}
