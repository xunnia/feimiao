import '../models/transaction_kind.dart';
import 'account_movement_projection.dart';

enum AccountActivityDirection { inflow, outflow }

class AccountActivityEvent {
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
  final String title;
  final String categoryName;
  final String bookName;

  const AccountActivityEvent({
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
    required this.toAccountId,
    required this.createdMs,
    required this.title,
    required this.categoryName,
    required this.bookName,
  });
}

class AccountActivityItem {
  final String eventId;
  final int accountId;
  final int bookId;
  final String currencyCode;
  final TransactionEventType eventType;
  final AccountActivityDirection direction;
  final int amountMinor;
  final DateTime attributionAt;
  final DateTime? settledAt;
  final SettlementQuality settlementQuality;
  final SettlementQuality settlementAccountQuality;
  final int createdMs;
  final String title;
  final String categoryName;
  final String bookName;

  const AccountActivityItem({
    required this.eventId,
    required this.accountId,
    required this.bookId,
    required this.currencyCode,
    required this.eventType,
    required this.direction,
    required this.amountMinor,
    required this.attributionAt,
    required this.settledAt,
    required this.settlementQuality,
    required this.settlementAccountQuality,
    required this.createdMs,
    required this.title,
    required this.categoryName,
    required this.bookName,
  });

  bool get isPartial =>
      settledAt == null ||
      settlementQuality != SettlementQuality.exact &&
          settlementQuality != SettlementQuality.userConfirmed ||
      settlementAccountQuality != SettlementQuality.exact &&
          settlementAccountQuality != SettlementQuality.userConfirmed;

  int get signedAmountMinor =>
      direction == AccountActivityDirection.inflow ? amountMinor : -amountMinor;
}

class AccountActivityProjection {
  const AccountActivityProjection._();

  static List<AccountActivityItem> forAccount({
    required int accountId,
    required Iterable<AccountActivityEvent> events,
    int? limit,
  }) {
    final items = <AccountActivityItem>[];

    void add(
      AccountActivityEvent event,
      int legAccountId,
      AccountActivityDirection direction,
      int amountMinor,
    ) {
      if (legAccountId != accountId || amountMinor == 0) return;
      items.add(AccountActivityItem(
        eventId: event.id,
        accountId: legAccountId,
        bookId: event.bookId,
        currencyCode: event.currencyCode,
        eventType: event.eventType,
        direction: direction,
        amountMinor: amountMinor.abs(),
        attributionAt: event.attributionAt,
        settledAt: event.settledAt,
        settlementQuality: event.settlementQuality,
        settlementAccountQuality: event.settlementAccountQuality,
        createdMs: event.createdMs,
        title: event.title,
        categoryName: event.categoryName,
        bookName: event.bookName,
      ));
    }

    for (final event in events) {
      final source = event.settlementAccountId;
      if (source == null ||
          event.settlementAccountQuality == SettlementQuality.unknown) {
        continue;
      }
      final amount = event.amountMinor.abs();
      switch (event.eventType) {
        case TransactionEventType.expense ||
              TransactionEventType.assetPurchase ||
              TransactionEventType.principalPayment ||
              TransactionEventType.interest:
          add(event, source, AccountActivityDirection.outflow, amount);
        case TransactionEventType.income ||
              TransactionEventType.refund ||
              TransactionEventType.reimbursement ||
              TransactionEventType.assetSale ||
              TransactionEventType.receivableRecovery:
          add(event, source, AccountActivityDirection.inflow, amount);
        case TransactionEventType.transfer:
          final target = event.toAccountId;
          if (target == null || target == source) continue;
          add(event, source, AccountActivityDirection.outflow, amount);
          add(event, target, AccountActivityDirection.inflow, amount);
        case TransactionEventType.legacyAdjustment:
          switch (event.legacyKind) {
            case TransactionKind.expense:
              final signed = event.amountMinor;
              add(
                event,
                source,
                signed < 0
                    ? AccountActivityDirection.inflow
                    : AccountActivityDirection.outflow,
                signed.abs(),
              );
            case TransactionKind.income:
              final signed = event.amountMinor;
              add(
                event,
                source,
                signed < 0
                    ? AccountActivityDirection.outflow
                    : AccountActivityDirection.inflow,
                signed.abs(),
              );
            case TransactionKind.transfer:
              final target = event.toAccountId;
              if (target == null || target == source) continue;
              add(event, source, AccountActivityDirection.outflow, amount);
              add(event, target, AccountActivityDirection.inflow, amount);
          }
      }
    }

    items.sort((left, right) {
      final leftSort = left.settledAt?.millisecondsSinceEpoch ?? left.createdMs;
      final rightSort =
          right.settledAt?.millisecondsSinceEpoch ?? right.createdMs;
      final byTime = rightSort.compareTo(leftSort);
      if (byTime != 0) return byTime;
      return right.eventId.compareTo(left.eventId);
    });
    if (limit == null || limit < 0 || items.length <= limit) return items;
    return items.take(limit).toList(growable: false);
  }
}
