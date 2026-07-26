import '../statistics/consumption_projection.dart';

/// Repository-independent transaction event used to reconstruct expense
/// families for budget and consumption projections.
///
/// [amountMinor] uses the persisted sign convention: an expense root is
/// positive and an attached refund is normally negative. The adapter exposes
/// refund magnitudes as positive integer minor units to the projection.
class BudgetTransactionFamilyEvent {
  final String id;
  final String? refundOfId;
  final bool isExpense;
  final int? bookId;
  final String currencyCode;
  final DateTime attributionDate;
  final DateTime createdAt;
  final int amountMinor;
  final bool countsInIncomeExpense;
  final bool countsInBudget;
  final String categoryKey;
  final String categoryName;

  const BudgetTransactionFamilyEvent({
    required this.id,
    this.refundOfId,
    required this.isExpense,
    required this.bookId,
    required this.currencyCode,
    required this.attributionDate,
    required this.createdAt,
    required this.amountMinor,
    this.countsInIncomeExpense = true,
    this.countsInBudget = true,
    this.categoryKey = '',
    this.categoryName = '',
  });
}

class BudgetTransactionFamilyAdapter {
  BudgetTransactionFamilyAdapter._();

  /// Reconstructs one family per positive expense root and attaches every
  /// refund event that references it, regardless of source ordering.
  ///
  /// Fully refunded families are intentionally retained. Dropping them would
  /// lose purchase-order counts and make a frozen knowledge cutoff impossible
  /// to reproduce. Legacy standalone negative expense rows (no refundOfId)
  /// are retained as single-row families with a negative net amount so the
  /// budget projection matches the statistics ledger.
  static List<ConsumptionExpenseFamily> build(
    Iterable<BudgetTransactionFamilyEvent> events,
  ) {
    final source = List<BudgetTransactionFamilyEvent>.of(events);
    final refundsByRoot = <String, List<BudgetTransactionFamilyEvent>>{};
    for (final event in source) {
      final rootId = event.refundOfId?.trim();
      if (rootId == null || rootId.isEmpty || !event.isExpense) continue;
      (refundsByRoot[rootId] ??= []).add(event);
    }

    final families = <ConsumptionExpenseFamily>[];
    for (final root in source) {
      if (!root.isExpense || root.refundOfId != null || root.amountMinor == 0) {
        continue;
      }
      if (root.amountMinor < 0) {
        // 遗留的独立负支出行（老版本退款/报销未挂原单时的冲账产物）：
        // 保留为净额为负的单行家族，不做分类拆分、不附着退款。丢弃它
        // 会让预算口径少冲减这部分金额，与统计口径（原始行直接求和）
        // 在主页同一张卡上对不上。
        families.add(ConsumptionExpenseFamily(
          id: root.id.trim(),
          bookId: root.bookId,
          currencyCode: root.currencyCode.trim().toUpperCase(),
          attributionDate: root.attributionDate,
          createdAt: root.createdAt,
          originalAmountMinor: root.amountMinor,
          countsInIncomeExpense: root.countsInIncomeExpense,
          countsInBudget: root.countsInBudget,
        ));
        continue;
      }
      final rootId = root.id.trim();
      final categoryKey = root.categoryKey.trim();
      final categoryName = root.categoryName.trim();
      final refunds = <ConsumptionRefund>[];
      for (final refund in refundsByRoot[rootId] ?? const []) {
        final amountMinor = refund.amountMinor.abs();
        if (amountMinor == 0) continue;
        refunds.add(ConsumptionRefund(
          id: refund.id.trim(),
          amountMinor: amountMinor,
          createdAt: refund.createdAt,
          effectiveAt: refund.attributionDate,
          categoryAllocations: [
            ConsumptionRefundAllocation(
              categoryKey: categoryKey,
              amountMinor: amountMinor,
            ),
          ],
        ));
      }

      families.add(ConsumptionExpenseFamily(
        id: rootId,
        bookId: root.bookId,
        currencyCode: root.currencyCode.trim().toUpperCase(),
        attributionDate: root.attributionDate,
        createdAt: root.createdAt,
        originalAmountMinor: root.amountMinor,
        countsInIncomeExpense: root.countsInIncomeExpense,
        countsInBudget: root.countsInBudget,
        categoryAllocations: [
          ConsumptionCategoryAllocation(
            categoryKey: categoryKey,
            categoryName: categoryName,
            amountMinor: root.amountMinor,
          ),
        ],
        refunds: refunds,
      ));
    }
    return List.unmodifiable(families);
  }
}
