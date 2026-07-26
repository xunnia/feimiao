import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/widgets/transaction_day_list.dart';

void main() {
  testWidgets('day header wraps totals on a 320dp screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = AppRepository();
    addTearDown(repo.dispose);
    final day = DateTime(2026, 7, 14, 12);
    TransactionEntity transaction(int id, String kind) => TransactionEntity(
          id: id,
          kind: kind,
          amountStr: '123456789012345.90',
          categoryKey: kind == 'expense' ? 'dining' : 'salary',
          categoryNameZh: kind == 'expense' ? '食品餐饮' : '工资薪酬',
          dateMs: day.millisecondsSinceEpoch,
        );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TxDaySectionHeader(
                section: TxSection(
                  day: DateTime(2026, 7, 14),
                  items: [
                    transaction(1, 'expense'),
                    transaction(2, 'income'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final dateRect = tester.getRect(
      find.byKey(const ValueKey('tx-day-header-date')),
    );
    final expenseRect = tester.getRect(find.textContaining('支 '));
    final incomeRect = tester.getRect(find.textContaining('收 '));
    expect(expenseRect.top, greaterThanOrEqualTo(dateRect.bottom));
    expect(incomeRect.right, lessThanOrEqualTo(304));
    expect(find.byKey(const ValueKey('tx-day-total-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tx-day-total-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
