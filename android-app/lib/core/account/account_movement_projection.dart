import '../models/transaction_kind.dart';
import '../statistics/metric_contract.dart';

enum SettlementQuality { exact, userConfirmed, legacyAssumed, unknown }

extension SettlementQualityX on SettlementQuality {
  String get storageKey => switch (this) {
        SettlementQuality.exact => 'exact',
        SettlementQuality.userConfirmed => 'user_confirmed',
        SettlementQuality.legacyAssumed => 'legacy_assumed',
        SettlementQuality.unknown => 'unknown',
      };

  static SettlementQuality fromStorage(String? value) {
    for (final quality in SettlementQuality.values) {
      if (quality.storageKey == value) return quality;
    }
    return SettlementQuality.unknown;
  }
}

enum TransactionEventType {
  expense,
  income,
  refund,
  reimbursement,
  transfer,
  assetPurchase,
  assetSale,
  receivableRecovery,
  legacyAdjustment,
  principalPayment,
  interest,
}

extension TransactionEventTypeX on TransactionEventType {
  String get storageKey => switch (this) {
        TransactionEventType.expense => 'expense',
        TransactionEventType.income => 'income',
        TransactionEventType.refund => 'refund',
        TransactionEventType.reimbursement => 'reimbursement',
        TransactionEventType.transfer => 'transfer',
        TransactionEventType.assetPurchase => 'asset_purchase',
        TransactionEventType.assetSale => 'asset_sale',
        TransactionEventType.receivableRecovery => 'receivable_recovery',
        TransactionEventType.legacyAdjustment => 'legacy_adjustment',
        TransactionEventType.principalPayment => 'principal_payment',
        TransactionEventType.interest => 'interest',
      };

  static TransactionEventType fromStorage(String? value) {
    for (final type in TransactionEventType.values) {
      if (type.storageKey == value) return type;
    }
    return TransactionEventType.legacyAdjustment;
  }
}

class AccountSettlementEvent {
  final String id;
  final int bookId;
  final String currencyCode;
  final TransactionEventType eventType;
  final TransactionKind legacyKind;
  final int amountMinor;
  final DateTime attributionAt;
  final DateTime? settledAt;
  final SettlementQuality settlementQuality;
  final int? settlementAccountId;
  final SettlementQuality settlementAccountQuality;
  final int? toAccountId;
  final int createdMs;

  const AccountSettlementEvent({
    required this.id,
    required this.bookId,
    required this.currencyCode,
    required this.eventType,
    required this.legacyKind,
    required this.amountMinor,
    required this.attributionAt,
    required this.settledAt,
    required this.settlementQuality,
    required this.settlementAccountId,
    required this.settlementAccountQuality,
    this.toAccountId,
    this.createdMs = 0,
  });
}

enum AccountMovementQueryMode {
  cashFlowWindow,
  currentBalance,
  historicalBalanceAsOf,
}

class AccountMovementQuery {
  final MetricQuery metricQuery;
  final AccountMovementQueryMode mode;
  final int? accountId;
  final DateTime? balanceAsOf;

  const AccountMovementQuery._({
    required this.metricQuery,
    required this.mode,
    required this.accountId,
    required this.balanceAsOf,
  });

  factory AccountMovementQuery.cashFlowWindow({
    required MetricQuery metricQuery,
    int? accountId,
  }) {
    if (metricQuery.dateAxis != MetricDateAxis.settlement) {
      throw ArgumentError('Cash-flow queries must use the settlement axis.');
    }
    return AccountMovementQuery._(
      metricQuery: metricQuery,
      mode: AccountMovementQueryMode.cashFlowWindow,
      accountId: accountId,
      balanceAsOf: null,
    );
  }

  factory AccountMovementQuery.currentBalance({
    required MetricQuery metricQuery,
    int? accountId,
  }) {
    if (metricQuery.dateAxis != MetricDateAxis.settlement) {
      throw ArgumentError('Balance queries must use the settlement axis.');
    }
    return AccountMovementQuery._(
      metricQuery: metricQuery,
      mode: AccountMovementQueryMode.currentBalance,
      accountId: accountId,
      balanceAsOf: metricQuery.asOf,
    );
  }

  factory AccountMovementQuery.historicalBalanceAsOf({
    required MetricQuery metricQuery,
    required DateTime balanceAsOf,
    int? accountId,
  }) {
    if (metricQuery.dateAxis != MetricDateAxis.settlement) {
      throw ArgumentError('Balance queries must use the settlement axis.');
    }
    return AccountMovementQuery._(
      metricQuery: metricQuery,
      mode: AccountMovementQueryMode.historicalBalanceAsOf,
      accountId: accountId,
      balanceAsOf: balanceAsOf,
    );
  }
}

class AccountMovementProjectionValue {
  final int knownMovements;
  final int unresolvedMovements;
  final Map<int, int> deltaMinorByAccount;
  final int unknownSettlementDateCount;
  final int unknownSettlementAccountCount;
  final int assumedSettlementDateCount;
  final int assumedAccountCount;
  final int invalidTransferCount;

  AccountMovementProjectionValue({
    required this.knownMovements,
    required this.unresolvedMovements,
    required Map<int, int> deltaMinorByAccount,
    required this.unknownSettlementDateCount,
    required this.unknownSettlementAccountCount,
    required this.assumedSettlementDateCount,
    required this.assumedAccountCount,
    required this.invalidTransferCount,
  }) : deltaMinorByAccount = Map.unmodifiable(deltaMinorByAccount);

  int deltaMinorFor(int accountId) => deltaMinorByAccount[accountId] ?? 0;
}

class AccountMovementProjection {
  static const resolverName = 'AccountMovementProjection';

  static MetricResult<AccountMovementProjectionValue> resolve({
    required AccountMovementQuery query,
    required Iterable<AccountSettlementEvent> events,
  }) {
    final metric = query.metricQuery;
    final deltas = <int, int>{};
    final reasons = <MetricReason>[];
    var known = 0;
    var unresolved = 0;
    var unknownDate = 0;
    var unknownAccount = 0;
    var assumedDate = 0;
    var assumedAccount = 0;
    var invalidTransfers = 0;

    void addDelta(int accountId, int amountMinor) {
      if (query.accountId != null && query.accountId != accountId) return;
      deltas[accountId] = (deltas[accountId] ?? 0) + amountMinor;
    }

    for (final event in events) {
      if (!metric.bookScope.contains(event.bookId) ||
          !metric.currencyScope.contains(event.currencyCode)) {
        continue;
      }
      if (event.createdMs > 0 &&
          event.createdMs > metric.knowledgeCutoff.millisecondsSinceEpoch) {
        continue;
      }
      if (query.accountId != null &&
          event.settlementAccountId != null &&
          event.settlementAccountId != query.accountId &&
          event.toAccountId != query.accountId) {
        continue;
      }

      final settledAt = event.settledAt;
      if (settledAt != null) {
        final inWindow = switch (query.mode) {
          AccountMovementQueryMode.cashFlowWindow =>
            metric.window.contains(settledAt),
          AccountMovementQueryMode.currentBalance ||
          AccountMovementQueryMode.historicalBalanceAsOf =>
            !settledAt.isAfter(query.balanceAsOf!),
        };
        if (!inWindow) continue;
      }

      final hasUnknownDate = event.settledAt == null ||
          event.settlementQuality == SettlementQuality.unknown;
      final hasUnknownAccount = event.settlementAccountId == null ||
          event.settlementAccountQuality == SettlementQuality.unknown;
      final transferInvalid =
          event.eventType == TransactionEventType.transfer &&
              (event.settlementAccountId == null ||
                  event.toAccountId == null ||
                  event.settlementAccountId == event.toAccountId);

      if (hasUnknownDate) unknownDate++;
      if (hasUnknownAccount) unknownAccount++;
      if (event.settlementQuality == SettlementQuality.legacyAssumed) {
        assumedDate++;
      }
      if (event.settlementAccountQuality == SettlementQuality.legacyAssumed) {
        assumedAccount++;
      }
      if (transferInvalid) invalidTransfers++;

      final isCurrentBalance =
          query.mode == AccountMovementQueryMode.currentBalance;
      if (hasUnknownDate && !isCurrentBalance) {
        unresolved++;
        continue;
      }
      if (hasUnknownAccount || transferInvalid) {
        unresolved++;
        continue;
      }
      final accountId = event.settlementAccountId!;
      final amount = event.amountMinor.abs();
      switch (event.eventType) {
        case TransactionEventType.expense ||
              TransactionEventType.assetPurchase ||
              TransactionEventType.principalPayment ||
              TransactionEventType.interest:
          addDelta(accountId, -amount);
        case TransactionEventType.income ||
              TransactionEventType.refund ||
              TransactionEventType.reimbursement ||
              TransactionEventType.assetSale ||
              TransactionEventType.receivableRecovery:
          addDelta(accountId, amount);
        case TransactionEventType.transfer:
          addDelta(accountId, -amount);
          addDelta(event.toAccountId!, amount);
        case TransactionEventType.legacyAdjustment:
          switch (event.legacyKind) {
            case TransactionKind.expense:
              addDelta(accountId, -event.amountMinor);
            case TransactionKind.income:
              addDelta(accountId, event.amountMinor);
            case TransactionKind.transfer:
              addDelta(accountId, -event.amountMinor.abs());
              if (event.toAccountId != null && event.toAccountId != accountId) {
                addDelta(event.toAccountId!, event.amountMinor.abs());
              }
          }
      }
      known++;
      if (hasUnknownDate) unresolved++;
    }

    if (unknownDate > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.unknownSettlementDate,
        message: '$unknownDate events have no confirmed settlement date.',
        details: {'count': unknownDate},
      ));
    }
    if (unknownAccount > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.unknownSettlementAccount,
        message: '$unknownAccount events have no confirmed settlement account.',
        details: {'count': unknownAccount},
      ));
    }
    if (assumedDate > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.assumedSettlementDate,
        message: '$assumedDate settlement dates are legacy assumptions.',
        details: {'count': assumedDate},
      ));
    }
    if (assumedAccount > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.assumedSettlementAccount,
        message: '$assumedAccount settlement accounts are legacy assumptions.',
        details: {'count': assumedAccount},
      ));
    }
    if (invalidTransfers > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.invalidTransferAccounts,
        message: '$invalidTransfers transfers have invalid account legs.',
        details: {'count': invalidTransfers},
      ));
    }

    final value = AccountMovementProjectionValue(
      knownMovements: known,
      unresolvedMovements: unresolved,
      deltaMinorByAccount: deltas,
      unknownSettlementDateCount: unknownDate,
      unknownSettlementAccountCount: unknownAccount,
      assumedSettlementDateCount: assumedDate,
      assumedAccountCount: assumedAccount,
      invalidTransferCount: invalidTransfers,
    );
    return reasons.isEmpty
        ? MetricResult.available(
            value: value,
            query: metric,
            resolver: resolverName,
          )
        : MetricResult.partial(
            value: value,
            reasons: reasons,
            query: metric,
            resolver: resolverName,
          );
  }
}
