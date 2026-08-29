import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_engine.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/home_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/home_summary_card.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadScreenshotFonts);

  Future<void> capture(
    WidgetTester tester,
    Finder boundary,
    String fileName,
  ) async {
    if (Platform.environment['UPDATE_NINE_UI_SCREENSHOTS'] != '1') return;
    await expectLater(
      boundary,
      matchesGoldenFile('../outputs/ui_comparisons/2026-08-29/$fileName'),
    );
  }

  Future<void> setViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('九条需求：首页大卡片数字和月份选择器', (tester) async {
    await setViewport(tester);
    final summary = MonthlySummary(
      year: 2026,
      month: 8,
      totalExpense: Decimal.fromInt(1255),
      totalIncome: Decimal.zero,
      expenseByCategory: const [],
      dailyTotals: const [],
    );
    final status = BudgetStatus(
      monthlyBudget: Decimal.fromInt(1000),
      spentThisMonth: Decimal.parse('1255'),
      spentToday: Decimal.zero,
      remaining: Decimal.parse('-255'),
      todayAllowance: Decimal.zero,
      isOverBudget: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DecoratedBox(
            key: const ValueKey('nine-ui-home-summary-capture'),
            decoration: AppColors.pageBackground(Brightness.light),
            child: HomeSummaryCard(
              monthDate: DateTime(2026, 8),
              isCurrentMonth: true,
              summary: summary,
              budgetStatus: status,
              budget: Decimal.fromInt(1000),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-budget-percent')))
          .data,
      '126%',
    );
    await capture(
      tester,
      find.byKey(const ValueKey('nine-ui-home-summary-capture')),
      'home_summary_after.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DecoratedBox(
            key: const ValueKey('nine-ui-month-picker-capture'),
            decoration: AppColors.pageBackground(Brightness.light),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: AppTheme.light().colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: buildHomeMonthPickerForTesting(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppCircleButton), findsOneWidget);
    await capture(
      tester,
      find.byKey(const ValueKey('nine-ui-month-picker-capture')),
      'month_picker_after.png',
    );
  });

  testWidgets('九条需求：普通 Chats 空态不显示主页预算提醒', (tester) async {
    await setViewport(tester);
    final repo = AppRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: RepaintBoundary(
            key: const ValueKey('nine-ui-chat-empty-capture'),
            child: AiChatPanel(
              fullScreen: true,
              recordOnly: false,
              onSwitchToManual: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('ai-chat-greeting')), findsNothing);
    await capture(
      tester,
      find.byKey(const ValueKey('nine-ui-chat-empty-capture')),
      'chat_empty_after.png',
    );
  });
}
