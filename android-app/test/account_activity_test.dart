import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/account_activity.dart';
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/views/assets/account_activity_list.dart';

AccountActivityEvent _event({
  required String id,
  TransactionEventType eventType = TransactionEventType.expense,
  TransactionKind legacyKind = TransactionKind.expense,
  int amountMinor = 1000,
  int? accountId = 1,
  int? toAccountId,
  DateTime? settledAt,
  SettlementQuality dateQuality = SettlementQuality.exact,
  SettlementQuality accountQuality = SettlementQuality.exact,
  int createdMs = 0,
}) =>
    AccountActivityEvent(
      id: id,
      bookId: 1,
      currencyCode: 'CNY',
      eventType: eventType,
      legacyKind: legacyKind,
      amountMinor: amountMinor,
      attributionAt: DateTime(2026, 6, 1),
      settledAt: settledAt ?? DateTime(2026, 6, 1),
      settlementQuality: dateQuality,
      settlementAccountId: accountId,
      settlementAccountQuality: accountQuality,
      toAccountId: toAccountId,
      createdMs: createdMs,
      title: id,
      categoryName: '分类',
      bookName: '账本',
    );

void main() {
  test('projects expense, refund and reimbursement to real settlement account',
      () {
    final items = AccountActivityProjection.forAccount(
      accountId: 2,
      events: [
        _event(id: 'expense', accountId: 1),
        _event(
          id: 'refund',
          eventType: TransactionEventType.refund,
          accountId: 2,
        ),
        _event(
          id: 'reimbursement',
          eventType: TransactionEventType.reimbursement,
          accountId: 2,
          amountMinor: 2500,
        ),
      ],
    );

    expect(items.map((item) => item.eventId).toSet(), {
      'refund',
      'reimbursement',
    });
    expect(items.every((item) => item.signedAmountMinor > 0), isTrue);
  });

  test('transfer exposes equal opposite legs', () {
    final event = _event(
      id: 'transfer',
      eventType: TransactionEventType.transfer,
      accountId: 1,
      toAccountId: 2,
      amountMinor: 8800,
    );
    final source = AccountActivityProjection.forAccount(
      accountId: 1,
      events: [event],
    ).single;
    final target = AccountActivityProjection.forAccount(
      accountId: 2,
      events: [event],
    ).single;

    expect(source.signedAmountMinor, -8800);
    expect(target.signedAmountMinor, 8800);
  });

  test('unknown account is not guessed and assumed evidence stays partial', () {
    final unknown = AccountActivityProjection.forAccount(
      accountId: 1,
      events: [
        _event(
          id: 'unknown',
          accountId: null,
          accountQuality: SettlementQuality.unknown,
        ),
      ],
    );
    expect(unknown, isEmpty);

    final assumed = AccountActivityProjection.forAccount(
      accountId: 1,
      events: [
        _event(
          id: 'assumed',
          accountQuality: SettlementQuality.legacyAssumed,
          dateQuality: SettlementQuality.legacyAssumed,
        ),
      ],
    ).single;
    expect(assumed.isPartial, isTrue);
  });

  test('sorts by settlement time and enforces the requested limit', () {
    final items = AccountActivityProjection.forAccount(
      accountId: 1,
      limit: 2,
      events: [
        _event(id: 'old', settledAt: DateTime(2026, 5, 1)),
        _event(id: 'new', settledAt: DateTime(2026, 7, 1)),
        _event(id: 'middle', settledAt: DateTime(2026, 6, 1)),
      ],
    );
    expect(items.map((item) => item.eventId), ['new', 'middle']);
  });

  testWidgets('recent activity renderer exposes quality and signed amount',
      (tester) async {
    final item = AccountActivityProjection.forAccount(
      accountId: 1,
      events: [
        _event(
          id: 'assumed expense',
          amountMinor: 3600,
          dateQuality: SettlementQuality.legacyAssumed,
          accountQuality: SettlementQuality.legacyAssumed,
        ),
      ],
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountActivityList(items: [item]),
        ),
      ),
    );

    expect(find.text('近期活动'), findsOneWidget);
    expect(find.text('assumed expense'), findsOneWidget);
    expect(find.textContaining('时间或账户为历史推定'), findsOneWidget);
    expect(find.textContaining('-¥36.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent activity keeps a long amount inside 320dp at 130% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = AccountActivityProjection.forAccount(
      accountId: 1,
      events: [
        _event(
          id: 'very long activity title that must keep its own space',
          amountMinor: 999999999999999999,
        ),
      ],
    ).single;
    final expectedAmount = MoneyFormat.string(
      budgetDecimalFromCents(item.amountMinor)!,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: AccountActivityList(items: [item]),
        ),
      ),
    );

    expect(find.text('-$expectedAmount'), findsOneWidget);
    expect(
      find.bySemanticsLabel('流出 $expectedAmount'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
