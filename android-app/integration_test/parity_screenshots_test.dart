import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/core/models/recurring_rule.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/import/bill_import.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/main.dart' as app;
import 'package:qingji/share_intake.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/assistant/meow_assistant_view.dart';
import 'package:qingji/views/assets/account_detail_page.dart';
import 'package:qingji/views/home/manual_add_sheet.dart';
import 'package:qingji/views/assets/physical_asset_detail_page.dart';
import 'package:qingji/views/reports/report_views.dart';
import 'package:qingji/views/search/search_view.dart';
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
import 'package:qingji/widgets/app_buttons.dart';

/// Android-side source for the paired screenshots declared in
/// ios-app/tools/screenshot_manifest.json.
///
/// This is deliberately an integration test instead of a production demo
/// switch: the real Flutter widgets are rendered on a real Android emulator,
/// while the fixture is inserted through the same repository API a user uses.
bool _surfaceConverted = false;

const _p0FixtureAsset = 'assets/parity/p0-demo-ledger-2026-08-v1.json';
const _p0CanonicalFixtureHash =
    'E45AB0CEFF322CCAE8A54474AB523F954724A749D0561F698ED81F23850996A6';
const _p0FixtureHash = String.fromEnvironment('QINGJI_P0_FIXTURE_HASH');
const _parityGroup = String.fromEnvironment(
  'QINGJI_PARITY_GROUP',
  defaultValue: 'all',
);
const _parityScene = String.fromEnvironment('QINGJI_PARITY_SCENE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Android parity screens', (tester) async {
    _surfaceConverted = false;
    expect(tester.view.physicalSize, const Size(1080, 1920),
        reason: 'P0 Android captures require the canonical device size');
    expect(AppClock.now.timeZoneOffset, const Duration(hours: 8),
        reason: 'P0 calendar calculations require device timezone Asia/Shanghai');
    await app.main();
    await _pumpFor(tester, const Duration(seconds: 2));

    final repo = _repositoryFromNavigator();
    await repo.fullyReady;
    final loadedFixture = await _ensureFixture(repo);
    final fixture = loadedFixture.fixture;
    await _pumpFor(tester, const Duration(milliseconds: 500));

    final augustIncome = repo.transactions
        .where(
          (transaction) =>
              transaction.txKind == TransactionKind.income &&
              transaction.date.year == 2026 &&
              transaction.date.month == 8,
        )
        .fold<Decimal>(
          Decimal.zero,
          (sum, transaction) => sum + transaction.amount,
        );
    final augustExpense = repo
        .visibleTransactionsForBookView(repo.currentBookId)
        .where(
          (transaction) =>
              transaction.txKind == TransactionKind.expense &&
              transaction.date.year == 2026 &&
              transaction.date.month == 8,
        )
        .fold<Decimal>(
          Decimal.zero,
          (sum, transaction) => sum + repo.netAmountOf(transaction),
        );
    expect(augustIncome, Decimal.parse('620'));
    expect(augustExpense, Decimal.parse('1017.9'));
    expect(augustIncome - augustExpense, Decimal.parse('-397.9'));

    // Build the business export before the optional asset-detail capture adds
    // its screen-only fixture rows to the repository.
    final businessJson = await _buildP0BusinessJson(
      repo,
      fixture,
      inputHash: loadedFixture.inputHash,
    );

    if (_parityScene.isNotEmpty) {
      await _captureParityScene(tester, binding, repo, _parityScene);
    } else {
      await _captureParityGroup(
        tester,
        binding,
        repo,
        group: _parityGroup,
      );
    }
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['p0BusinessJson'] = businessJson;
  });
}

Future<void> _captureParityScene(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  AppRepository repo,
  String scene,
) async {
  debugPrint('PARITY_SCENE_BEGIN scene=$scene');
  if (scene == 'home-overview') {
    await _takeScreenshot(tester, binding, 'home-overview-android');
  } else if (scene == 'drawer-books') {
    await _captureDrawerOnly(tester, binding);
  } else if (scene == 'books-management') {
    await _captureBooksManagementOnly(tester, binding);
  } else if (scene == 'quick-add-expense') {
    await _capturePage(
      tester,
      'quick-add-expense-android',
      const _ManualAddCapturePage(),
      binding,
    );
  } else if (scene == 'quick-add-income') {
    await _captureIncomeOnly(tester, binding);
  } else if (scene == 'transactions-search') {
    await _captureSearch(tester, binding);
  } else if (scene == 'stats-week') {
    await _captureStatistics(tester, binding, '周', 'stats-week-android');
  } else if (scene == 'stats-month') {
    await _captureStatistics(tester, binding, '月', 'stats-month-android');
  } else if (scene == 'stats-year') {
    await _captureStatistics(tester, binding, '年', 'stats-year-android');
  } else if (scene == 'stats-custom') {
    await _captureStatistics(tester, binding, '自定义', 'stats-custom-android');
  } else if (scene == 'budget') {
    await _capturePage(
        tester, 'budget-android', const BudgetSettingView(), binding);
  } else if (scene == 'reimburse') {
    await _capturePage(
        tester, 'reimburse-android', const ReimburseView(), binding);
  } else if (scene == 'reimburse-settlement') {
    await _captureReimburseSettlement(tester, binding);
  } else if (scene == 'savings') {
    await _capturePage(
        tester, 'savings-android', const SavingsGoalsView(), binding);
  } else if (scene == 'recurring') {
    await _capturePage(
        tester, 'recurring-android', const RecurringView(), binding);
  } else if (scene == 'categories') {
    await _capturePage(
        tester, 'categories-android', const CategoriesView(), binding);
  } else if (scene == 'tags') {
    await _capturePage(tester, 'tags-android', const TagsView(), binding);
  } else if (scene == 'category-memory') {
    await _capturePage(
        tester, 'category-memory-android', const MemoryView(), binding);
  } else if (scene == 'settings') {
    await _capturePage(
        tester, 'settings-android', const SettingsView(), binding);
  } else if (scene == 'ai-entry') {
    await _capturePage(
        tester, 'ai-entry-android', const MeowAssistantView(), binding);
  } else if (scene == 'ai-settings') {
    await _capturePage(
        tester, 'ai-settings-android', const AiSettingView(), binding);
  } else if (scene == 'ai-tasks') {
    await _capturePage(
        tester, 'ai-tasks-android', const AiTaskCenterView(), binding);
  } else if (scene == 'ai-diagnostics') {
    await _capturePage(
        tester, 'ai-diagnostics-android', const AiDiagnosticsView(), binding);
  } else if (scene == 'ai-search') {
    await _capturePage(
        tester, 'ai-search-android', const AiUnifiedSearchView(), binding);
  } else if (scene == 'ai-memory') {
    await _capturePage(
        tester, 'ai-memory-android', const AiMemoryControlView(), binding);
  } else if (scene == 'ai-extensions') {
    await _capturePage(
      tester,
      'ai-extensions-android',
      const AiSkillsAndConnectorsView(),
      binding,
    );
  } else if (scene == 'ai-schedules') {
    await _capturePage(
      tester,
      'ai-schedules-android',
      const AiReportScheduleView(),
      binding,
    );
  } else if (scene == 'ai-local') {
    await _capturePage(
      tester,
      'ai-local-android',
      const LocalModelCompanionView(),
      binding,
    );
  } else if (scene == 'backup') {
    await _capturePage(tester, 'backup-android', const BackupView(), binding);
  } else if (scene == 'theme') {
    await _capturePage(
        tester, 'theme-android', const ThemeSettingsView(), binding);
  } else if (scene == 'display') {
    await _captureDisplaySettings(tester, binding);
  } else if (scene == 'assets-hub' ||
      scene == 'assets-funds' ||
      scene == 'accounts-management' ||
      scene == 'liabilities' ||
      scene == 'net-worth') {
    await _captureAssetScene(tester, binding, scene);
  } else if (scene == 'physical-asset-detail') {
    final asset = await _ensureAssetDetailFixture(repo);
    await _capturePage(
      tester,
      'asset-detail-android',
      PhysicalAssetDetailPage(assetId: asset.id, fallbackAsset: asset),
      binding,
    );
  } else if (scene == 'account-detail' || scene == 'reconcile') {
    final account = repo.transactionAccounts.firstWhere(
      (item) => item.type == AccountType.cash,
    );
    await _capturePage(
      tester,
      'account-detail-android',
      AccountDetailPage(account: account),
      binding,
    );
    if (scene == 'reconcile') {
      await _captureAccountReconcile(tester, binding);
    }
  } else if (scene == 'import-review') {
    await _capturePage(
      tester,
      'import-review-android',
      BillReviewView(rows: _demoImportRows(), source: '支付宝', skipped: 2),
      binding,
    );
  } else if (scene == 'reports-library') {
    await _captureReports(tester, binding);
  } else {
    throw ArgumentError.value(scene, 'QINGJI_PARITY_SCENE', 'unknown scene');
  }
  debugPrint('PARITY_SCENE_READY scene=$scene');
}

Future<void> _captureParityGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  AppRepository repo, {
  required String group,
}) async {
  if (group == 'all') {
    await _captureCoreGroup(tester, binding);
    await _capturePlanningGroup(tester, binding);
    await _captureManagementGroup(tester, binding);
    await _captureAiGroup(tester, binding);
    await _captureSystemGroup(tester, binding, repo);
  } else if (group == 'core') {
    await _captureCoreGroup(tester, binding);
  } else if (group == 'planning') {
    await _capturePlanningGroup(tester, binding);
  } else if (group == 'management') {
    await _captureManagementGroup(tester, binding);
  } else if (group == 'ai') {
    await _captureAiGroup(tester, binding);
  } else if (group == 'system') {
    await _captureSystemGroup(tester, binding, repo);
  } else {
    throw ArgumentError.value(
      group,
      'QINGJI_PARITY_GROUP',
      'expected all, core, planning, management, ai, or system',
    );
  }
}

Future<void> _captureCoreGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _takeScreenshot(tester, binding, 'home-overview-android');
  // The drawer button belongs to the root shell. Capture it before pushing
  // page routes that intentionally remain mounted for the rest of this group.
  await _captureBooks(tester, binding);
  await _capturePage(
    tester,
    'quick-add-expense-android',
    const _ManualAddCapturePage(),
    binding,
  );
  await _captureQuickAddIncome(tester, binding);
  await _captureSearch(tester, binding);
}

Future<void> _capturePlanningGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
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
  await _capturePage(
    tester,
    'reimburse-android',
    const ReimburseView(),
    binding,
  );
  await _captureReimburseSettlement(tester, binding);
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
}

Future<void> _captureManagementGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _captureAssetViews(tester, binding);
  await _capturePage(
    tester,
    'categories-android',
    const CategoriesView(),
    binding,
  );
  await _capturePage(tester, 'tags-android', const TagsView(), binding);
  await _capturePage(
    tester,
    'settings-android',
    const SettingsView(),
    binding,
  );
}

Future<void> _captureAiGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _capturePage(
    tester,
    'ai-entry-android',
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
    'category-memory-android',
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
}

Future<void> _captureSystemGroup(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  AppRepository repo,
) async {
  await _capturePage(tester, 'backup-android', const BackupView(), binding);
  await _capturePage(
    tester,
    'theme-android',
    const ThemeSettingsView(),
    binding,
  );
  await _captureDisplaySettings(tester, binding);
  final detailAsset = await _ensureAssetDetailFixture(repo);
  await _capturePage(
    tester,
    'asset-detail-android',
    PhysicalAssetDetailPage(
      assetId: detailAsset.id,
      fallbackAsset: detailAsset,
    ),
    binding,
  );
  final detailAccount = repo.transactionAccounts.firstWhere(
    (account) => account.type == AccountType.cash,
  );
  await _capturePage(
    tester,
    'account-detail-android',
    AccountDetailPage(account: detailAccount),
    binding,
  );
  await _captureAccountReconcile(tester, binding);
  await _capturePage(
    tester,
    'import-review-android',
    BillReviewView(rows: _demoImportRows(), source: '支付宝', skipped: 2),
    binding,
  );
  await _captureReports(tester, binding);
}

Future<void> _captureDisplaySettings(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(_parityPageRoute<void>(const _DisplayCaptureShell())),
  );
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _takeScreenshot(tester, binding, 'display-android');
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 300));
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 300));
}

PageRoute<T> _parityPageRoute<T>(Widget page, {bool opaque = true}) =>
    PageRouteBuilder<T>(
      // Some Android settings surfaces are normally presented inside a
      // material bottom sheet rather than a Scaffold. Keep direct parity
      // pushes under a transparent Material ancestor. Opaque routes still
      // need the real app background: the light theme deliberately exposes a
      // gradient through scaffoldBackgroundColor, and after
      // convertFlutterSurfaceToImage() a transparent route would otherwise
      // composite against the emulator's black surface.
      opaque: opaque,
      pageBuilder: (context, _, __) {
        final child = Material(color: Colors.transparent, child: page);
        if (!opaque) return child;
        return DecoratedBox(
          decoration: AppColors.pageBackground(Theme.of(context).brightness),
          child: child,
        );
      },
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
  final now = AppClock.now;
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
  await _openPage(tester, page);
  await _takeScreenshot(tester, binding, name);
  // Keep captured routes mounted until the driver exits. Repeatedly popping
  // opaque routes while the Android surface is an ImageView can make Flutter
  // tear down a live widget tree before the next frame is delivered.
  debugPrint('PARITY_PAGE_READY name=$name');
}

Future<void> _openPage(WidgetTester tester, Widget page) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(
      // Give every capture route an opaque app background. The manual entry
      // sheet is still the production sheet; making its capture host opaque
      // keeps the surrounding viewport visible after surface conversion.
      _parityPageRoute<void>(page),
    ),
  );
  await _pumpFor(tester, const Duration(milliseconds: 700));
}

Future<void> _captureReports(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(_parityPageRoute<void>(const _ReportCaptureShell())),
  );
  await _pumpFor(tester, const Duration(milliseconds: 900));
  expect(find.text('报告'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'reports-library-android');
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

Future<void> _captureBooks(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final button = find.byType(AppDrawerButton);
  expect(button, findsAtLeastNWidgets(1));
  await tester.tap(button.first);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('我的账本'), findsOneWidget);
  await _takeScreenshot(tester, binding, 'drawer-books-android');
  final newBook = find.text('新建账本');
  expect(newBook, findsAtLeastNWidgets(1));
  await tester.tap(newBook.last);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('新建账本'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'books-management-android');
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  if (navigator!.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 400));
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width - 8, size.height / 2));
  await _pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _captureDrawerOnly(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final button = find.byType(AppDrawerButton);
  expect(button, findsAtLeastNWidgets(1));
  await tester.tap(button.first);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('我的账本'), findsOneWidget);
  await _takeScreenshot(tester, binding, 'drawer-books-android');
}

Future<void> _captureBooksManagementOnly(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final button = find.byType(AppDrawerButton);
  expect(button, findsAtLeastNWidgets(1));
  await tester.tap(button.first);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('我的账本'), findsOneWidget);

  final newBook = find.text('新建账本');
  expect(newBook, findsAtLeastNWidgets(1));
  await tester.tap(newBook.last);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('新建账本'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'books-management-android');
}

Future<void> _captureQuickAddIncome(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final income = find.text('收入');
  expect(income, findsAtLeastNWidgets(1));
  // The base parity page already has the real ManualAddSheet open. Switch
  // that same sheet so both captures share the production route and layout.
  await tester.tap(income.last);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  await _takeScreenshot(tester, binding, 'quick-add-income-android');
}

Future<void> _captureIncomeOnly(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _openPage(tester, const _ManualAddCapturePage());
  await _captureQuickAddIncome(tester, binding);
}

Future<void> _captureSearch(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(navigator!.push<void>(_parityPageRoute<void>(const SearchView())));
  await _pumpFor(tester, const Duration(milliseconds: 700));
  final search = find.byType(SearchView);
  expect(search, findsAtLeastNWidgets(1));
  final field =
      find.descendant(of: search.last, matching: find.byType(TextField));
  expect(field, findsOneWidget);
  await tester.enterText(field, '麦当劳');
  await _pumpFor(tester, const Duration(milliseconds: 500));
  expect(find.text('麦当劳'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'transactions-search-android');
}

Future<void> _captureAssetViews(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
      navigator!.push<void>(_parityPageRoute<void>(const AccountsView())));
  await _pumpFor(tester, const Duration(milliseconds: 700));

  final overview = find.text('总览');
  expect(overview, findsAtLeastNWidgets(1));
  await tester.tap(overview.last);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  await _takeScreenshot(tester, binding, 'assets-hub-android');

  final funds = find.text('资金');
  expect(funds, findsAtLeastNWidgets(1));
  await tester.tap(funds.last);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  await _takeScreenshot(tester, binding, 'assets-funds-android');

  final add = find.byIcon(Icons.add);
  expect(add, findsAtLeastNWidgets(1));
  await tester.tap(add.last);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  final addAccount = find.text('添加账户');
  expect(addAccount, findsAtLeastNWidgets(1));
  await tester.tap(addAccount.last);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _takeScreenshot(tester, binding, 'accounts-management-android');
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 500));

  final credit = find.text('Parity信用卡');
  expect(credit, findsAtLeastNWidgets(1));
  await tester.tap(credit.last);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _takeScreenshot(tester, binding, 'liabilities-android');
  if (navigator.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 500));

  final overviewAgain = find.text('总览');
  expect(overviewAgain, findsAtLeastNWidgets(1));
  await tester.tap(overviewAgain.last);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  await _takeScreenshot(tester, binding, 'net-worth-android');
}

Future<void> _captureAssetScene(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String scene,
) async {
  await _openPage(tester, const AccountsView());

  Future<void> selectTab(String label) async {
    final tab = find.text(label);
    expect(tab, findsAtLeastNWidgets(1));
    await tester.tap(tab.last);
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }

  if (scene == 'assets-hub' || scene == 'net-worth') {
    await selectTab('总览');
    await _takeScreenshot(tester, binding, '$scene-android');
    return;
  }

  await selectTab('资金');
  if (scene == 'assets-funds') {
    await _takeScreenshot(tester, binding, 'assets-funds-android');
    return;
  }

  if (scene == 'accounts-management') {
    final add = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.add),
    );
    expect(add, findsAtLeastNWidgets(1));
    await tester.tap(add.last);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    final addAccount = find.text('添加账户');
    expect(addAccount, findsAtLeastNWidgets(1));
    await tester.tap(addAccount.last);
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await _takeScreenshot(tester, binding, 'accounts-management-android');
    return;
  }

  if (scene == 'liabilities') {
    final credit = find.text('Parity信用卡');
    expect(credit, findsAtLeastNWidgets(1));
    await tester.tap(credit.last);
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await _takeScreenshot(tester, binding, 'liabilities-android');
    return;
  }

  throw ArgumentError.value(scene, 'scene', 'unknown asset scene');
}

Future<void> _captureAccountReconcile(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  final accountDetail = find.text('校准余额');
  expect(accountDetail, findsAtLeastNWidgets(1));
  await tester.tap(accountDetail.last);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  expect(find.text('校准余额'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'reconcile-android');
  if (navigator!.canPop()) navigator.pop<void>();
  await _pumpFor(tester, const Duration(milliseconds: 400));
}

/// Opens the production bottom-sheet entry point used by the home input bar.
/// Keeping this as a tiny opaque route shell makes the capture deterministic
/// while preserving the actual ManualAddSheet transition and barrier.
class _ManualAddCapturePage extends StatefulWidget {
  const _ManualAddCapturePage();

  @override
  State<_ManualAddCapturePage> createState() => _ManualAddCapturePageState();
}

class _ManualAddCapturePageState extends State<_ManualAddCapturePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(showManualAddSheet(context, onSwitchToAi: () {}));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<void> _captureReimburseSettlement(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final navigator = ShareIntake.navigatorKey.currentState;
  expect(navigator, isNotNull);
  unawaited(
    navigator!.push<void>(_parityPageRoute<void>(const ReimburseView())),
  );
  await _pumpFor(tester, const Duration(milliseconds: 700));
  final settleButton = find.text('已报销');
  expect(settleButton, findsAtLeastNWidgets(1));
  // The base reimburse page remains mounted for the rest of the capture run;
  // tap the action on the topmost page rather than its hidden earlier copy.
  await tester.tap(settleButton.last);
  await _pumpFor(tester, const Duration(milliseconds: 700));
  expect(find.text('报销到账'), findsAtLeastNWidgets(1));
  await _takeScreenshot(tester, binding, 'reimburse-settlement-android');
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
    navigator!.push<void>(_parityPageRoute<void>(const StatisticsView())),
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

class _P0FixtureBundle {
  const _P0FixtureBundle({required this.fixture, required this.inputHash});

  final Map<String, dynamic> fixture;
  final String inputHash;
}

Future<_P0FixtureBundle> _loadP0Fixture() async {
  final data = await rootBundle.load(_p0FixtureAsset);
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final actualHash = sha256.convert(bytes).toString().toUpperCase();
  if (actualHash != _p0CanonicalFixtureHash) {
    throw StateError(
      'P0 fixture asset differs from the frozen canonical hash: '
      'actual=$actualHash expected=$_p0CanonicalFixtureHash',
    );
  }
  final expectedHash = _p0FixtureHash.trim().toUpperCase();
  if (!RegExp(r'^[0-9A-F]{64}$').hasMatch(expectedHash)) {
    throw StateError(
      'QINGJI_P0_FIXTURE_HASH must be an uppercase SHA-256 value',
    );
  }
  if (actualHash != expectedHash) {
    throw StateError(
      'P0 fixture asset SHA-256 differs: actual=$actualHash expected=$expectedHash',
    );
  }
  final raw = utf8.decode(bytes);
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw StateError('P0 fixture root is not an object');
  }
  return _P0FixtureBundle(
    fixture: Map<String, dynamic>.from(decoded),
    inputHash: actualHash,
  );
}

Map<String, dynamic> _p0Row(Object? value, String label) {
  if (value is! Map) throw StateError('P0 fixture $label is not an object');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _p0Rows(Object? value, String label) {
  if (value is! List) throw StateError('P0 fixture $label is not an array');
  return value.map((item) => _p0Row(item, label)).toList(growable: false);
}

String _p0String(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw StateError('P0 fixture field $key is missing');
  }
  return value;
}

DateTime _p0Date(Map<String, dynamic> row, String key) =>
    DateTime.parse(_p0String(row, key)).toLocal();

Decimal _p0Amount(Map<String, dynamic> row) =>
    Decimal.parse(_p0String(row, 'amount'));

Future<_P0FixtureBundle> _ensureFixture(AppRepository repo) async {
  final loadedFixture = await _loadP0Fixture();
  final fixture = loadedFixture.fixture;
  final bookRows = _p0Rows(fixture['books'], 'books');
  final accountRows = _p0Rows(fixture['accounts'], 'accounts');
  final transactionRows = _p0Rows(fixture['transactions'], 'transactions');
  final budgetRows = _p0Rows(fixture['budgets'], 'budgets');
  final savingsRows = _p0Rows(fixture['savingsGoals'], 'savingsGoals');
  final recurringRows = _p0Rows(fixture['recurringRules'], 'recurringRules');
  final bookDefinition = bookRows.firstWhere(
    (row) => row['key'] == 'book-total',
    orElse: () => throw StateError('P0 fixture book-total is missing'),
  );
  final bookName = _p0String(bookDefinition, 'name');
  final bookID = repo.books
      .firstWhere(
        (book) => book.name == bookName,
        orElse: () => throw StateError(
          'P0 fixture book is not available: $bookName',
        ),
      )
      .id;
  if (repo.currentBookId != bookID) {
    await repo.switchBook(bookID);
    await repo.fullyReady;
  }

  final sourceRows = await repo.debugDb.query(
    'auto_record_occurrences',
    columns: const ['source_id'],
  );
  final seededSources =
      sourceRows.map((row) => row['source_id']).whereType<String>().toSet();
  final expectedOriginalSources = transactionRows
      .where((row) => row['refundOf'] == null)
      .map((row) => 'p0-${_p0String(row, 'key')}')
      .toSet();
  final alreadySeeded = expectedOriginalSources.every(seededSources.contains);
  if (alreadySeeded) {
    await _ensureReport(repo, fixture);
    await repo.fullyReady;
    await _buildP0BusinessJson(
      repo,
      fixture,
      inputHash: loadedFixture.inputHash,
    );
    return loadedFixture;
  }

  var accounts = repo.transactionAccounts.toList(growable: false);
  Future<void> ensureAccount(String key) async {
    final definition = accountRows.firstWhere((row) => row['key'] == key);
    final kind = AccountTypeX.fromStorage(definition['kind'] as String?);
    if (accounts.any((account) => account.name == definition['name'])) return;
    await repo.addAccount(
      name: _p0String(definition, 'name'),
      type: kind,
      openingBalance: Decimal.parse(_p0String(definition, 'initialBalance')),
    );
    await repo.fullyReady;
    accounts = repo.transactionAccounts.toList(growable: false);
  }

  await ensureAccount('account-bank');
  await ensureAccount('account-credit');
  // addAccount uses the production default sort order (0). Apply the explicit
  // fixture input to storage, then reload it; the exporter must continue to
  // report the real database value, not copy the expected sortOrder to output.
  for (final definition in accountRows) {
    final account = accounts.firstWhere((a) => a.name == definition['name']);
    await repo.debugDb.update(
      'accounts',
      {'sort_order': definition['sortOrder'] as int},
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }
  await repo.reloadForTest();
  accounts = repo.transactionAccounts.toList(growable: false);
  for (final definition in accountRows) {
    expect(accounts.firstWhere((a) => a.name == definition['name']).sortOrder,
        definition['sortOrder']);
  }
  expect(accounts.any((account) => account.type == AccountType.cash), isTrue);
  expect(accounts.any((account) => account.name == 'Parity银行卡'), isTrue);

  AccountEntity accountFor(String key) {
    final definition = accountRows.firstWhere((row) => row['key'] == key);
    return accounts.firstWhere(
      (account) => account.name == definition['name'],
      orElse: () => throw StateError(
        'P0 fixture account is not available: ${definition['name']}',
      ),
    );
  }

  int? category(String key) {
    for (final item in repo.categories) {
      if (item.key == key) return item.id;
    }
    return null;
  }

  final originals = <String, TransactionEntity>{};
  for (final row in transactionRows.where((row) => row['refundOf'] == null)) {
    final kind = TransactionKind.fromJson(_p0String(row, 'kind'));
    final account = accountFor(_p0String(row, 'account'));
    final toAccount = row['toAccount'] == null
        ? null
        : accountFor(row['toAccount'] as String);
    final key = _p0String(row, 'key');
    final id = await repo.addTransaction(
      kind: kind,
      amount: _p0Amount(row),
      currencyCode: row['currency'] as String? ?? 'CNY',
      categoryId:
          row['category'] == null ? null : category(row['category'] as String),
      accountId: account.id,
      toAccountId: toAccount?.id,
      note: row['note'] as String? ?? '',
      date: _p0Date(row, 'date'),
      reimbursable: row['reimbursable'] as bool? ?? false,
      excluded: row['excluded'] as bool? ?? false,
      bookId: bookID,
      autoRecordSourceId: 'p0-$key',
    );
    await repo.fullyReady;
    originals[key] = repo.transactions.firstWhere((item) => item.id == id);
  }

  for (final row in transactionRows.where((row) => row['refundOf'] != null)) {
    final original = originals[row['refundOf'] as String];
    if (original == null) throw StateError('P0 refund original is missing');
    final settlementKey =
        row['settlementAccount'] as String? ?? row['account'] as String;
    await repo.refundTransaction(
      original,
      _p0Amount(row).abs(),
      settledAt: row['settledAt'] == null
          ? _p0Date(row, 'date')
          : _p0Date(row, 'settledAt'),
      settlementAccountId: accountFor(settlementKey).id,
    );
  }

  if (!repo.budgetPeriods.any((period) => period.bookId == bookID)) {
    final categoryBudgets = <String, Decimal>{};
    for (final row in budgetRows) {
      final categoryKey = row['category'] as String?;
      if (categoryKey != null) {
        categoryBudgets[categoryKey] = Decimal.parse(_p0String(row, 'amount'));
      }
    }
    final total = budgetRows.firstWhere((row) => row['category'] == null);
    await repo.addBudgetPeriod(
      bookId: bookID,
      start: _p0Date(total, 'periodStart'),
      recurringMonthly: total['cycle'] == 'monthly',
      total: Decimal.parse(_p0String(total, 'amount')),
      categoryBudgets: categoryBudgets,
    );
  }

  if (repo.savingsGoals.isEmpty) {
    for (final row in savingsRows) {
      await repo.addSavingsGoal(
        name: _p0String(row, 'name'),
        target: Decimal.parse(_p0String(row, 'target')),
        emoji: row['emoji'] as String? ?? '🐷',
        initialSaved: Decimal.parse(_p0String(row, 'saved')),
      );
    }
  }

  if (repo.recurringRules.isEmpty && recurringRows.isNotEmpty) {
    final row = recurringRows.first;
    await repo.addRecurringRule(
      kind: TransactionKind.fromJson(_p0String(row, 'kind')),
      amount: Decimal.parse(_p0String(row, 'amount')),
      categoryId: category(row['category'] as String),
      accountId: accountFor(_p0String(row, 'account')).id,
      bookId: bookID,
      note: row['note'] as String? ?? '',
      period: RecurPeriod.fromJson(_p0String(row, 'period')),
      startDate: _p0Date(row, 'startDate'),
    );
  }
  await _ensureReport(repo, fixture);
  await repo.fullyReady;
  await _buildP0BusinessJson(
    repo,
    fixture,
    inputHash: loadedFixture.inputHash,
  );
  return loadedFixture;
}

Future<PhysicalAssetEntity> _ensureAssetDetailFixture(
  AppRepository repo,
) async {
  final existing = repo.globalActivePhysicalAssets.firstOrNull;
  if (existing != null) return existing;

  final assetId = await repo.addPhysicalAsset(
    name: 'iPhone Air',
    assetType: AssetType.digital,
    currentValue: Decimal.parse('5800'),
    purchasePrice: Decimal.parse('6999'),
    sourceType: PhysicalAssetSourceType.historicalExisting,
    purchaseDate: DateTime(2026, 5, 27, 12),
    brand: 'Apple',
    model: 'iPhone Air',
    location: '随身',
    warrantyUntil: DateTime(2027, 8, 27, 12),
    note: '演示物品资产',
    includeInNetWorth: true,
    occurredAt: DateTime(2026, 5, 27, 12),
  );
  await repo.fullyReady;
  final asset = repo.physicalAssetDetailById(assetId);
  if (asset == null) throw StateError('资产演示数据写入后无法读取');
  return asset;
}

Future<void> _ensureReport(
  AppRepository repo,
  Map<String, dynamic> fixture,
) async {
  if (repo.reports.isNotEmpty) return;
  final reports = _p0Rows(fixture['reports'], 'reports');
  if (reports.isEmpty) return;
  final report = reports.first;
  final expected = Map<String, dynamic>.from(fixture['expected'] as Map);
  final title = _p0String(report, 'title');
  final expense = expected['augustNetExpense'];
  final income = expected['augustIncome'];
  final balance = expected['augustBalance'];
  await repo.addReport(
    type: report['type'] as String? ?? 'monthly',
    title: title,
    summary: report['summary'] as String? ?? '',
    markdown: '# $title\n\n'
        '- 支出：¥$expense\n'
        '- 收入：¥$income\n'
        '- 结余：¥$balance\n\n'
        '## 支出分类\n\n'
        '- 餐饮：¥151.00（4笔）\n'
        '- 购物：¥478.00（2笔）\n'
        '- 出行：¥53.00（3笔）\n'
        '- 食品：¥208.00（2笔）',
    periodStart: _p0Date(report, 'periodStart'),
    periodEnd: _p0Date(report, 'periodEnd'),
    bookId: repo.currentBookId,
  );
}

Future<Map<String, dynamic>> _buildP0BusinessJson(
    AppRepository repo, Map<String, dynamic> fixture,
    {required String inputHash}) async {
  final bookRows = _p0Rows(fixture['books'], 'books');
  final accountRows = _p0Rows(fixture['accounts'], 'accounts');
  final transactionRows = _p0Rows(fixture['transactions'], 'transactions');
  final budgetRows = _p0Rows(fixture['budgets'], 'budgets');
  final savingsRows = _p0Rows(fixture['savingsGoals'], 'savingsGoals');
  final recurringRows = _p0Rows(fixture['recurringRules'], 'recurringRules');
  final reportRows = _p0Rows(fixture['reports'], 'reports');
  final expected = _p0Row(fixture['expected'], 'expected');

  final fixtureBookKeyByName = <String, String>{
    for (final row in bookRows) _p0String(row, 'name'): _p0String(row, 'key'),
  };
  final fixtureAccountKeyByName = <String, String>{
    for (final row in accountRows)
      _p0String(row, 'name'): _p0String(row, 'key'),
  };
  final bookKeyById = <int, String>{};
  final bookSortById = <int, int>{};
  for (final row in await repo.debugDb.query(
    'books',
    columns: const ['id', 'sort_order'],
  )) {
    final id = row['id'];
    if (id is int) {
      final name = repo.books.firstWhere((book) => book.id == id).name;
      final key = fixtureBookKeyByName[name];
      if (key != null) bookKeyById[id] = key;
      bookSortById[id] = (row['sort_order'] as int?) ?? 0;
    }
  }
  final accountKeyById = <int, String>{};
  for (final account in repo.accounts) {
    final key = fixtureAccountKeyByName[account.name];
    if (key != null) accountKeyById[account.id] = key;
  }
  final categoryKeyById = <int, String>{
    for (final category in repo.categories) category.id: category.key,
  };
  final sourceKeyByTransactionId = <int, String>{};
  for (final row in await repo.debugDb.query(
    'auto_record_occurrences',
    columns: const ['source_id', 'transaction_id'],
  )) {
    final source = row['source_id'];
    final id = row['transaction_id'];
    if (source is String && source.startsWith('p0-') && id is int) {
      sourceKeyByTransactionId[id] = source.substring(3);
    }
  }

  final actualByKey = <String, TransactionEntity>{};
  for (final transaction in repo.transactions) {
    final key = sourceKeyByTransactionId[transaction.id];
    if (key != null) actualByKey[key] = transaction;
  }
  for (final row in transactionRows.where((row) => row['refundOf'] != null)) {
    final originalKey = row['refundOf'] as String;
    final original = actualByKey[originalKey];
    if (original == null) {
      throw StateError('P0 export refund original is missing: $originalKey');
    }
    final refund = repo.transactions.firstWhere(
      (transaction) => transaction.refundOf == original.id,
      orElse: () => throw StateError(
        'P0 export refund row is missing: ${row['key']}',
      ),
    );
    actualByKey[_p0String(row, 'key')] = refund;
  }

  final expectedBudgetBookKey = _p0String(budgetRows.first, 'book');
  final budgetPeriod = repo.budgetPeriods.firstWhere(
    (period) =>
        period.bookId != null &&
        bookKeyById[period.bookId!] == expectedBudgetBookKey,
    orElse: () => throw StateError('P0 export budget period is missing'),
  );
  final savingsByName = {
    for (final goal in repo.savingsGoals) goal.name: goal,
  };
  final recurring = repo.recurringRules;
  final reports = repo.reports;

  final transactionPayload = <Map<String, dynamic>>[];
  for (final row in transactionRows) {
    final key = _p0String(row, 'key');
    final transaction = actualByKey[key];
    if (transaction == null) {
      throw StateError('P0 export transaction is missing: $key');
    }
    final accountKey = transaction.accountId == null
        ? null
        : accountKeyById[transaction.accountId!];
    final toAccountKey = transaction.toAccountId == null
        ? null
        : accountKeyById[transaction.toAccountId!];
    final bookKey =
        transaction.bookId == null ? null : bookKeyById[transaction.bookId!];
    transactionPayload.add({
      'key': key,
      'kind': transaction.kind,
      'amount': transaction.amount.toString(),
      'category':
          transaction.categoryKey.isEmpty ? null : transaction.categoryKey,
      'account': accountKey,
      'toAccount': toAccountKey,
      'book': bookKey,
      'note': transaction.note,
      'date': _p0Iso(transaction.date),
      'settledAt':
          transaction.settledAt == null ? null : _p0Iso(transaction.settledAt!),
      'settlementAccount': transaction.settlementAccountId == null
          ? null
          : accountKeyById[transaction.settlementAccountId!],
      'eventType': transaction.eventType.storageKey,
      'reimbursable': transaction.reimbursable,
      'isReimbursed': false,
      'excluded': transaction.excluded,
      'refundOf': transaction.refundOf == null
          ? null
          : sourceKeyByTransactionId[transaction.refundOf!],
    });
  }

  final logicalNow = _p0Date(_p0Row(fixture, 'fixture'), 'clock');
  final monthRows = [
    for (final row in transactionRows)
      if (_p0Date(row, 'date').year == logicalNow.year &&
          _p0Date(row, 'date').month == logicalNow.month)
        actualByKey[_p0String(row, 'key')]!,
  ];
  final income = monthRows
      .where((transaction) => transaction.txKind == TransactionKind.income)
      .fold<Decimal>(
          Decimal.zero, (sum, transaction) => sum + transaction.amount);
  final grossExpense = monthRows
      .where((transaction) =>
          transaction.txKind == TransactionKind.expense &&
          transaction.amount > Decimal.zero)
      .fold<Decimal>(
          Decimal.zero, (sum, transaction) => sum + transaction.amount);
  final refund = monthRows
      .where((transaction) =>
          transaction.txKind == TransactionKind.expense &&
          transaction.amount < Decimal.zero)
      .fold<Decimal>(
          Decimal.zero, (sum, transaction) => sum + transaction.amount.abs());
  final netExpense = grossExpense - refund;

  final accountPayload = <Map<String, dynamic>>[];
  for (final row in accountRows) {
    final account = repo.accounts.firstWhere(
      (item) => item.name == _p0String(row, 'name'),
      orElse: () =>
          throw StateError('P0 export account is missing: ${row['key']}'),
    );
    accountPayload.add({
      'key': _p0String(row, 'key'),
      'name': account.name,
      'kind': account.type.storageKey,
      'initialBalance': account.openingBalance.toString(),
      'balance': repo.accountBalanceOf(account).toString(),
      'sortOrder': account.sortOrder,
    });
  }

  final budgetsPayload = <Map<String, dynamic>>[];
  for (final row in budgetRows) {
    final category = row['category'] as String?;
    final amount = category == null
        ? budgetPeriod.total
        : budgetPeriod.categoryBudgets[category];
    if (amount == null) {
      throw StateError('P0 export category budget is missing: $category');
    }
    final actualBook =
        budgetPeriod.bookId == null ? null : bookKeyById[budgetPeriod.bookId!];
    if (actualBook != row['book']) {
      throw StateError('P0 export budget book differs: ${row['key']}');
    }
    final actualCategory = category == null
        ? null
        : budgetPeriod.categoryBudgets.containsKey(category)
            ? category
            : throw StateError(
                'P0 export budget category differs: ${row['key']}',
              );
    budgetsPayload.add({
      'key': _p0String(row, 'key'),
      'book': actualBook,
      'category': actualCategory,
      'periodStart': _p0Iso(budgetPeriod.start),
      'cycle': budgetPeriod.recurringMonthly ? 'monthly' : 'one_time',
      'amount': amount.toString(),
    });
  }

  final savingsPayload = <Map<String, dynamic>>[];
  for (final row in savingsRows) {
    final goal = savingsByName[_p0String(row, 'name')];
    if (goal == null) {
      throw StateError('P0 export savings goal is missing: ${row['key']}');
    }
    savingsPayload.add({
      'key': _p0String(row, 'key'),
      'name': goal.name,
      'emoji': goal.emoji,
      'target': goal.target.toString(),
      'saved': goal.saved.toString(),
    });
  }

  final recurringPayload = <Map<String, dynamic>>[];
  for (final row in recurringRows) {
    final rule = recurring.firstWhere(
      (item) => item.note == (row['note'] as String? ?? ''),
      orElse: () => throw StateError(
          'P0 export recurring rule is missing: ${row['key']}'),
    );
    final actualCategory =
        rule.categoryId == null ? null : categoryKeyById[rule.categoryId!];
    final actualAccount =
        rule.accountId == null ? null : accountKeyById[rule.accountId!];
    final actualToAccount =
        rule.toAccountId == null ? null : accountKeyById[rule.toAccountId!];
    final actualBook = bookKeyById[rule.bookId];
    if (actualCategory != row['category'] ||
        actualAccount != row['account'] ||
        actualToAccount != row['toAccount'] ||
        actualBook != row['book']) {
      throw StateError('P0 export recurring references differ: ${row['key']}');
    }
    recurringPayload.add({
      'key': _p0String(row, 'key'),
      'kind': rule.kind,
      'amount': rule.amount.toString(),
      'category': actualCategory,
      'account': actualAccount,
      'toAccount': actualToAccount,
      'book': actualBook,
      'note': rule.note,
      'period': rule.period,
      'startDate': _p0Iso(rule.startDate),
      'endDate': rule.endDate == null ? null : _p0Iso(rule.endDate!),
      'totalCount': rule.totalCount,
    });
  }

  final reportsPayload = <Map<String, dynamic>>[];
  for (final row in reportRows) {
    final report = reports.firstWhere(
      (item) => item.title == _p0String(row, 'title'),
      orElse: () =>
          throw StateError('P0 export report is missing: ${row['key']}'),
    );
    reportsPayload.add({
      'key': _p0String(row, 'key'),
      'type': report.type,
      'book': report.bookId == null ? null : bookKeyById[report.bookId!],
      'title': report.title,
      'summary': report.summary,
      'periodStart': _p0Iso(report.periodStart),
      'periodEnd': _p0Iso(report.periodEnd),
    });
  }

  return {
    'schemaVersion': 1,
    'platform': 'android',
    'fixture': {
      'fixtureId': _p0String(fixture, 'fixtureId'),
      'inputHash': inputHash,
      'logicalNow': _p0String(fixture, 'clock'),
      'locale': _p0String(fixture, 'locale'),
      'timezone': _p0String(fixture, 'timezone'),
      'currency': _p0String(fixture, 'currency'),
    },
    'books': [
      for (final row in bookRows)
        {
          'key': _p0String(row, 'key'),
          'name': _p0String(row, 'name'),
          'includeInTotal': repo.books
              .firstWhere((book) => book.name == row['name'])
              .includeInTotal,
          'isDefault':
              repo.books.firstWhere((book) => book.name == row['name']).id ==
                  repo.defaultBookId,
          'sortOrder': bookSortById[repo.books
                  .firstWhere((book) => book.name == row['name'])
                  .id] ??
              0,
        },
    ],
    'accounts': accountPayload,
    'transactions': transactionPayload,
    'budgets': budgetsPayload,
    'savingsGoals': savingsPayload,
    'recurringRules': recurringPayload,
    'reports': reportsPayload,
    'physicalAssets': const <Map<String, dynamic>>[],
    'summary': {
      'augustIncome': income.toString(),
      'augustGrossExpense': grossExpense.toString(),
      'augustRefund': refund.toString(),
      'augustNetExpense': netExpense.toString(),
      'augustBalance': (income - netExpense).toString(),
      'augustTransactionRowsIncludingOffsetAndTransfer': monthRows.length,
      'augustVisibleOrdinaryRows': monthRows
          .where((transaction) =>
              transaction.txKind != TransactionKind.transfer &&
              transaction.refundOf == null)
          .length,
      'budget': budgetPeriod.total.toString(),
      'fixtureExpectedBalance': expected['augustBalance'],
    },
    'logicalMonth': {'year': logicalNow.year, 'month': logicalNow.month},
  };
}

String _p0Iso(DateTime value) {
  final result = value.toUtc().toIso8601String();
  return result.endsWith('.000Z')
      ? '${result.substring(0, result.length - 5)}Z'
      : result;
}
