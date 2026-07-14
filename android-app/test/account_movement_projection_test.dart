import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

MetricQuery _metricQuery({
  DateTime? start,
  DateTime? end,
  DateTime? asOf,
}) =>
    MetricQuery(
      metricId: 'account-movement',
      window: MetricWindow(
        startInclusive: start ?? DateTime(2026, 7, 1),
        endExclusive: end ?? DateTime(2026, 8, 1),
      ),
      dateAxis: MetricDateAxis.settlement,
      timezone: 'Asia/Shanghai',
      bookScope: MetricBookScope(bookIds: const [1], scopeVersion: 1),
      currencyScope: MetricCurrencyScope.single('CNY'),
      asOf: asOf ?? DateTime(2026, 7, 31, 23, 59, 59),
      knowledgeCutoff: DateTime(2026, 7, 31, 23, 59, 59),
    );

AccountSettlementEvent _event({
  String id = 'event',
  TransactionEventType eventType = TransactionEventType.expense,
  TransactionKind legacyKind = TransactionKind.expense,
  int amountMinor = 10000,
  DateTime? attributionAt,
  DateTime? settledAt,
  bool hasSettlementDate = true,
  SettlementQuality settlementQuality = SettlementQuality.exact,
  int? settlementAccountId = 1,
  SettlementQuality settlementAccountQuality = SettlementQuality.exact,
  int? toAccountId,
}) =>
    AccountSettlementEvent(
      id: id,
      bookId: 1,
      currencyCode: 'CNY',
      eventType: eventType,
      legacyKind: legacyKind,
      amountMinor: amountMinor,
      attributionAt: attributionAt ?? DateTime(2026, 6, 20),
      settledAt: hasSettlementDate ? settledAt ?? DateTime(2026, 7, 13) : null,
      settlementQuality: settlementQuality,
      settlementAccountId: settlementAccountId,
      settlementAccountQuality: settlementAccountQuality,
      toAccountId: toAccountId,
    );

MetricResult<AccountMovementProjectionValue> _cashFlow(
  Iterable<AccountSettlementEvent> events, {
  int? accountId,
}) =>
    AccountMovementProjection.resolve(
      query: AccountMovementQuery.cashFlowWindow(
        metricQuery: _metricQuery(),
        accountId: accountId,
      ),
      events: events,
    );

void main() {
  test('minor units stay integer-exact and expense creates one outflow', () {
    final result = _cashFlow([
      _event(amountMinor: 10025),
    ]);

    expect(result.status, MetricStatus.available);
    expect(result.value!.knownMovements, 1);
    expect(result.value!.deltaMinorFor(1), -10025);
    expect(result.value!.deltaMinorByAccount, {1: -10025});
  });

  test('refund is attributed to June but enters the July receiving account',
      () {
    final result = _cashFlow([
      _event(
        eventType: TransactionEventType.refund,
        legacyKind: TransactionKind.expense,
        amountMinor: 3000,
        attributionAt: DateTime(2026, 6, 20),
        settledAt: DateTime(2026, 7, 5),
        settlementAccountId: 2,
      ),
    ]);

    expect(result.status, MetricStatus.available);
    expect(result.value!.deltaMinorFor(1), 0);
    expect(result.value!.deltaMinorFor(2), 3000);
  });

  test('reimbursement may enter salary account instead of original card', () {
    final result = _cashFlow([
      _event(
        eventType: TransactionEventType.reimbursement,
        amountMinor: 8800,
        settlementAccountId: 2,
      ),
    ]);

    expect(result.value!.deltaMinorFor(1), 0);
    expect(result.value!.deltaMinorFor(2), 8800);
  });

  test('transfer creates two account legs and zero global delta', () {
    final result = _cashFlow([
      _event(
        eventType: TransactionEventType.transfer,
        legacyKind: TransactionKind.transfer,
        amountMinor: 5000,
        settlementAccountId: 1,
        toAccountId: 2,
      ),
    ]);

    expect(result.status, MetricStatus.available);
    expect(result.value!.knownMovements, 1);
    expect(result.value!.deltaMinorFor(1), -5000);
    expect(result.value!.deltaMinorFor(2), 5000);
    expect(
      result.value!.deltaMinorByAccount.values.fold<int>(0, (a, b) => a + b),
      0,
    );
  });

  test('asset sale and receivable recovery remain real account movements', () {
    final result = _cashFlow([
      _event(
        id: 'sale',
        eventType: TransactionEventType.assetSale,
        legacyKind: TransactionKind.income,
        amountMinor: 180000,
      ),
      _event(
        id: 'recovery',
        eventType: TransactionEventType.receivableRecovery,
        legacyKind: TransactionKind.income,
        amountMinor: 50000,
      ),
    ]);

    expect(result.status, MetricStatus.available);
    expect(result.value!.knownMovements, 2);
    expect(result.value!.deltaMinorFor(1), 230000);
  });

  test('unknown settlement date is usable only for current balance', () {
    final unknownDate = _event(
      hasSettlementDate: false,
      settlementQuality: SettlementQuality.unknown,
      settlementAccountId: 1,
    );
    final current = AccountMovementProjection.resolve(
      query: AccountMovementQuery.currentBalance(
        metricQuery: _metricQuery(),
        accountId: 1,
      ),
      events: [unknownDate],
    );
    final historicalFlow = _cashFlow([unknownDate], accountId: 1);

    expect(current.status, MetricStatus.partial);
    expect(current.value!.deltaMinorFor(1), -10000);
    expect(current.value!.knownMovements, 1);
    expect(current.value!.unresolvedMovements, 1);
    expect(current.value!.unknownSettlementDateCount, 1);
    expect(historicalFlow.status, MetricStatus.partial);
    expect(historicalFlow.value!.deltaMinorFor(1), 0);
    expect(historicalFlow.value!.knownMovements, 0);
    expect(historicalFlow.value!.unresolvedMovements, 1);
    expect(
      historicalFlow.reasons.map((reason) => reason.code),
      contains(MetricReasonCode.unknownSettlementDate),
    );
  });

  test('unknown settlement account never falls back to the original account',
      () {
    final result = _cashFlow(
      [
        _event(
          settlementAccountId: null,
          settlementAccountQuality: SettlementQuality.unknown,
        ),
      ],
      accountId: 1,
    );

    expect(result.status, MetricStatus.partial);
    expect(result.value!.deltaMinorFor(1), 0);
    expect(result.value!.deltaMinorByAccount, isEmpty);
    expect(result.value!.knownMovements, 0);
    expect(result.value!.unresolvedMovements, 1);
    expect(result.value!.unknownSettlementAccountCount, 1);
    expect(
      result.reasons.map((reason) => reason.code),
      contains(MetricReasonCode.unknownSettlementAccount),
    );
  });

  test('legacy adjustment preserves stored balance direction', () {
    final negativeExpenseAdjustment = _event(
      eventType: TransactionEventType.legacyAdjustment,
      legacyKind: TransactionKind.expense,
      amountMinor: -575,
    );
    final result = _cashFlow([negativeExpenseAdjustment]);

    expect(result.status, MetricStatus.available);
    expect(result.value!.deltaMinorFor(1), 575);
    expect(negativeExpenseAdjustment.eventType,
        TransactionEventType.legacyAdjustment);
  });

  test('legacy assumptions are surfaced instead of promoted to exact', () {
    final result = _cashFlow([
      _event(
        settlementQuality: SettlementQuality.legacyAssumed,
        settlementAccountQuality: SettlementQuality.legacyAssumed,
      ),
    ]);

    expect(result.status, MetricStatus.partial);
    expect(result.value!.deltaMinorFor(1), -10000);
    expect(result.value!.assumedSettlementDateCount, 1);
    expect(result.value!.assumedAccountCount, 1);
    expect(
      result.reasons.map((reason) => reason.code),
      containsAll([
        MetricReasonCode.assumedSettlementDate,
        MetricReasonCode.assumedSettlementAccount,
      ]),
    );
  });
}
