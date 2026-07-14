import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/refund_settlement_sheet.dart';

class _SettlementRepo extends AppRepository {
  _SettlementRepo(this.items);

  final List<AccountEntity> items;

  @override
  List<AccountEntity> get accounts => items;
}

final _cash = AccountEntity(
  id: 1,
  name: '现金',
  openingBalance: Decimal.zero,
);

final _salaryAccount = AccountEntity(
  id: 2,
  name: '工资卡',
  openingBalance: Decimal.zero,
);

TransactionEntity _original({int? accountId = 1}) => TransactionEntity(
      id: 10,
      bookId: 1,
      kind: 'expense',
      amountStr: '100',
      accountId: accountId,
      accountName: accountId == 1 ? '现金' : '',
      note: '六月订单',
      dateMs: DateTime(2026, 6, 20).millisecondsSinceEpoch,
    );

Widget _app({
  required AppRepository repo,
  required Widget child,
}) =>
    ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(home: Scaffold(body: child)),
    );

Finder _confirmButton(String label) => find.byWidgetPredicate(
      (widget) => widget is AppPillButton && widget.label == label,
    );

void main() {
  testWidgets('shows the three required settlement fields and stable keys',
      (tester) async {
    final repo = _SettlementRepo([_cash, _salaryAccount]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(),
          initialAmount: Decimal.fromInt(30),
          maxAmount: Decimal.fromInt(100),
          initialSettledAt: DateTime(2026, 7, 13),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('refund-settlement-sheet')), findsOneWidget);
    expect(find.byKey(const Key('refund-settlement-amount')), findsOneWidget);
    expect(find.byKey(const Key('refund-settlement-date')), findsOneWidget);
    expect(find.byKey(const Key('refund-settlement-account')), findsOneWidget);
    expect(find.text('退款金额'), findsOneWidget);
    expect(find.text('到账日期'), findsOneWidget);
    expect(find.text('到账账户'), findsOneWidget);
    expect(find.text('2026/07/13'), findsOneWidget);
    expect(find.text('现金'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing settlement date disables confirmation', (tester) async {
    final repo = _SettlementRepo([_cash]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(),
          initialAmount: Decimal.fromInt(30),
          maxAmount: Decimal.fromInt(100),
          initialSettledAt: null,
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<AppPillButton>(_confirmButton('确认退款'));
    expect(button.onPressed, isNull);
    expect(find.text('选择到账日期'), findsOneWidget);
  });

  testWidgets('missing settlement account disables confirmation',
      (tester) async {
    final repo = _SettlementRepo(const []);
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(accountId: null),
          initialAmount: Decimal.fromInt(30),
          maxAmount: Decimal.fromInt(100),
          initialSettledAt: DateTime(2026, 7, 13),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<AppPillButton>(_confirmButton('确认退款'));
    expect(button.onPressed, isNull);
    expect(find.text('选择到账账户'), findsOneWidget);
  });

  testWidgets('valid amount date and account enable confirmation',
      (tester) async {
    final repo = _SettlementRepo([_cash]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(),
          initialAmount: Decimal.fromInt(30),
          maxAmount: Decimal.fromInt(100),
          initialSettledAt: DateTime(2026, 7, 13),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<AppPillButton>(_confirmButton('确认退款'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('refund result carries the selected receiving account and date',
      (tester) async {
    final repo = _SettlementRepo([_cash, _salaryAccount]);
    addTearDown(repo.dispose);
    RefundSettlementResult? result;
    final settledAt = DateTime(2026, 7, 13);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.push<RefundSettlementResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: RefundSettlementSheet(
                          original: _original(),
                          initialAmount: Decimal.fromInt(30),
                          maxAmount: Decimal.fromInt(100),
                          initialSettledAt: settledAt,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refund-settlement-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工资卡').last);
    await tester.pumpAndSettle();
    await tester.tap(_confirmButton('确认退款'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amount, Decimal.fromInt(30));
    expect(result!.settledAt, settledAt);
    expect(result!.settlementAccountId, _salaryAccount.id);
  });

  testWidgets('reimbursement may settle into a non-original account',
      (tester) async {
    final repo = _SettlementRepo([_cash, _salaryAccount]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(),
          initialAmount: Decimal.fromInt(100),
          maxAmount: Decimal.fromInt(100),
          amountEditable: false,
          title: '报销到账',
          confirmLabel: '确认报销',
          initialSettledAt: DateTime(2026, 7, 13),
          initialSettlementAccountId: _salaryAccount.id,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('报销金额'), findsOneWidget);
    expect(find.text('工资卡'), findsOneWidget);
    final button = tester.widget<AppPillButton>(_confirmButton('确认报销'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('legacy refund exposes a settlement confirmation action',
      (tester) async {
    final repo = _SettlementRepo([_cash, _salaryAccount]);
    addTearDown(repo.dispose);
    final refund = TransactionEntity(
      id: 11,
      bookId: 1,
      kind: 'expense',
      amountStr: '-30',
      accountId: 1,
      note: '退款',
      dateMs: DateTime(2026, 6, 20).millisecondsSinceEpoch,
      refundOf: 10,
    );

    await tester.pumpWidget(
      _app(
        repo: repo,
        child: RefundSettlementSheet(
          original: _original(),
          initialAmount: Decimal.fromInt(70),
          maxAmount: Decimal.fromInt(70),
          initialSettledAt: DateTime(2026, 7, 13),
          existingRefunds: [refund],
          onConfirmSettlement: (_, __, ___) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.textContaining('到账日待确认'), findsOneWidget);
    expect(find.textContaining('到账账户待确认'), findsOneWidget);
  });
}
