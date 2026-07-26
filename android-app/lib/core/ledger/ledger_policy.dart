import 'package:decimal/decimal.dart';

import '../../data/app_repository.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// User-facing ledger policy.
///
/// Lists may still show excluded rows, but any user-visible totals, budgets,
/// exports, insights, and reports should use this policy so "not counted" rows
/// and attached refunds have one consistent meaning across the app.
class LedgerPolicy {
  LedgerPolicy._();

  static bool includeInUserTotals(TransactionEntity t) => !t.excluded;

  /// 一次遍历建立「原单 id → 退款行金额合计（负数）」索引。
  /// 净额逐笔全表扫退款行是 O(n²) 的元凶——凡是要对一批账单循环算
  /// 净额/用户金额的地方，先建一次索引再查，别在循环里调 *Of(t, all)。
  static Map<int, Decimal> refundTotals(Iterable<TransactionEntity> all) {
    final totals = <int, Decimal>{};
    for (final r in all) {
      final of = r.refundOf;
      if (of != null) totals[of] = (totals[of] ?? Decimal.zero) + r.amount;
    }
    return totals;
  }

  /// 净额（索引版，O(1)）：退款行是负数，直接加即净额。
  static Decimal netAmountWith(
    TransactionEntity t,
    Map<int, Decimal> refundTotals,
  ) =>
      t.amount + (refundTotals[t.id] ?? Decimal.zero);

  /// 用户可见金额（索引版，O(1)）。
  static Decimal userAmountWith(
    TransactionEntity t,
    Map<int, Decimal> refundTotals,
  ) {
    if (!includeInUserTotals(t)) return Decimal.zero;
    if (t.refundOf != null) return Decimal.zero;
    return netAmountWith(t, refundTotals);
  }

  static Decimal netAmountOf(
    TransactionEntity t,
    Iterable<TransactionEntity> all,
  ) {
    var net = t.amount;
    for (final r in all) {
      if (r.refundOf == t.id) net += r.amount;
    }
    return net;
  }

  static Decimal userAmountOf(
    TransactionEntity t,
    Iterable<TransactionEntity> all,
  ) {
    if (!includeInUserTotals(t)) return Decimal.zero;
    if (t.refundOf != null) return Decimal.zero;
    return netAmountOf(t, all);
  }

  static bool contributesPositiveExpense(
    TransactionEntity t,
    Iterable<TransactionEntity> all,
  ) =>
      t.txKind == TransactionKind.expense &&
      userAmountOf(t, all) > Decimal.zero;

  /// 笔数口径的唯一判定入口（STATISTICS_CALCULATION_STANDARD §7.1 的
  /// `expenseCount`）：**窗口内净额为正的原始消费家族**才算一笔。
  ///
  /// 全额退款家族净额归 0，贡献 0 元，因此也不占笔数；legacy 独立负支出
  /// （原额 < 0 的冲账行）同理不是一笔正支出。凡是要显示「N 笔支出」的地方
  /// 一律走这里，别自己 `.length`——否则同一批账在不同页面会给出不同笔数。
  static bool countsAsExpenseFamily(
    TransactionEntity t,
    Map<int, Decimal> refundTotals,
  ) =>
      t.txKind == TransactionKind.expense &&
      userAmountWith(t, refundTotals) > Decimal.zero;

  /// [countsAsExpenseFamily] 的批量版：一批账单里算几笔支出。
  static int expenseFamilyCount(
    Iterable<TransactionEntity> transactions,
    Map<int, Decimal> refundTotals,
  ) =>
      transactions
          .where((t) => countsAsExpenseFamily(t, refundTotals))
          .length;

  /// toUserRecord 的索引版：批量转换时先建一次 [refundTotals] 再逐笔调这个。
  static TransactionRecord toUserRecordWith(
    TransactionEntity t,
    Map<int, Decimal> refundTotals, {
    String languageCode = 'zh',
  }) {
    final amount = userAmountWith(t, refundTotals);
    return TransactionRecord(
      id: t.id.toString(),
      kind: t.txKind,
      amount: amount,
      currencyCode: t.currencyCode,
      categoryName:
          languageCode.startsWith('zh') ? t.categoryNameZh : t.categoryNameEn,
      categoryKey: t.categoryKey,
      accountId: t.accountId,
      accountName: t.accountName,
      toAccountId: t.toAccountId,
      toAccountName: t.toAccountName,
      note: t.note,
      date: t.date,
      timePrecision: t.timePrecision,
    );
  }

  static TransactionRecord toUserRecord(
    TransactionEntity t,
    Iterable<TransactionEntity> all, {
    String languageCode = 'zh',
  }) {
    final amount = userAmountOf(t, all);
    return TransactionRecord(
      id: t.id.toString(),
      kind: t.txKind,
      amount: amount,
      currencyCode: t.currencyCode,
      categoryName:
          languageCode.startsWith('zh') ? t.categoryNameZh : t.categoryNameEn,
      categoryKey: t.categoryKey,
      accountId: t.accountId,
      accountName: t.accountName,
      toAccountId: t.toAccountId,
      toAccountName: t.toAccountName,
      note: t.note,
      date: t.date,
      timePrecision: t.timePrecision,
    );
  }
}
