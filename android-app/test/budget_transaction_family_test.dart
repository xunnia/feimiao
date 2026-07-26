import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_transaction_family.dart';
import 'package:qingji/core/statistics/consumption_projection.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

DateTime _at(int month, int day, {int hour = 0}) =>
    DateTime.utc(2026, month, day, hour);

BudgetTransactionFamilyEvent _root({
  String id = 'order-1',
  int amountMinor = 10000,
  bool countsInIncomeExpense = true,
  bool countsInBudget = true,
}) =>
    BudgetTransactionFamilyEvent(
      id: id,
      isExpense: true,
      bookId: 1,
      currencyCode: 'cny',
      attributionDate: _at(6, 20),
      createdAt: _at(6, 20),
      amountMinor: amountMinor,
      countsInIncomeExpense: countsInIncomeExpense,
      countsInBudget: countsInBudget,
      categoryKey: 'dining',
      categoryName: 'Dining',
    );

BudgetTransactionFamilyEvent _refund({
  String id = 'refund-1',
  String refundOfId = 'order-1',
  int amountMinor = -3000,
  DateTime? createdAt,
}) =>
    BudgetTransactionFamilyEvent(
      id: id,
      refundOfId: refundOfId,
      isExpense: true,
      bookId: 1,
      currencyCode: 'CNY',
      attributionDate: _at(6, 20),
      createdAt: createdAt ?? _at(7, 5),
      amountMinor: amountMinor,
    );

MetricQuery _query({required DateTime knowledgeCutoff}) => MetricQuery(
      metricId: 'budget-family-adapter-test',
      window: MetricWindow(
        startInclusive: _at(6, 1),
        endExclusive: _at(7, 1),
      ),
      dateAxis: MetricDateAxis.attribution,
      timezone: 'Asia/Shanghai',
      bookScope: MetricBookScope(bookIds: [1], scopeVersion: 1),
      currencyScope: MetricCurrencyScope.single('CNY'),
      asOf: _at(7, 13),
      knowledgeCutoff: knowledgeCutoff,
    );

void main() {
  group('BudgetTransactionFamilyAdapter', () {
    test('keeps an unrefunded root at its original integer-minor amount', () {
      final families = BudgetTransactionFamilyAdapter.build([_root()]);

      expect(families, hasLength(1));
      final family = families.single;
      expect(family.id, 'order-1');
      expect(family.currencyCode, 'CNY');
      expect(family.originalAmountMinor, 10000);
      expect(family.refunds, isEmpty);
      expect(family.categoryAllocations.single.amountMinor, 10000);
    });

    test('attaches a partial refund without replacing the original amount', () {
      final families = BudgetTransactionFamilyAdapter.build([
        _refund(),
        _root(),
      ]);

      final family = families.single;
      expect(family.originalAmountMinor, 10000);
      expect(family.refunds, hasLength(1));
      final refund = family.refunds.single;
      expect(refund.id, 'refund-1');
      expect(refund.amountMinor, 3000);
      expect(refund.createdAt, _at(7, 5));
      expect(refund.effectiveAt, _at(6, 20));
      expect(refund.categoryAllocations.single.categoryKey, 'dining');
      expect(refund.categoryAllocations.single.amountMinor, 3000);
    });

    test('retains a fully refunded family for order-count semantics', () {
      final families = BudgetTransactionFamilyAdapter.build([
        _root(),
        _refund(amountMinor: -10000),
      ]);

      expect(families, hasLength(1));
      expect(families.single.originalAmountMinor, 10000);
      expect(families.single.refunds.single.amountMinor, 10000);

      final projected = ConsumptionProjection.resolve(
        query: _query(knowledgeCutoff: _at(7, 13)),
        expenseFamilies: families,
      );
      expect(projected.value!.expenseMinor, 0);
      expect(projected.value!.purchaseOrderCount, 1);
      expect(projected.value!.expenseCount, 0);
    });

    test('retains a legacy standalone negative row and nets budget spend', () {
      // 遗留独立冲账行：正支出 100 元 + 无 refundOfId 的负行 -30 元。
      // 预算口径已用应为 70 元，与统计口径（原始行求和）一致。
      final families = BudgetTransactionFamilyAdapter.build([
        _root(),
        _root(id: 'legacy-neg-1', amountMinor: -3000),
      ]);

      expect(families, hasLength(2));
      final legacy =
          families.singleWhere((family) => family.id == 'legacy-neg-1');
      expect(legacy.originalAmountMinor, -3000);
      expect(legacy.refunds, isEmpty);
      expect(legacy.categoryAllocations, isEmpty);

      final projected = ConsumptionProjection.resolve(
        query: _query(knowledgeCutoff: _at(7, 13)),
        expenseFamilies: families,
      );
      expect(projected.value!.budgetExpenseMinor, 7000);
      // 冲账行不是订单，不参与订单/笔数统计。
      expect(projected.value!.purchaseOrderCount, 1);
      expect(projected.value!.expenseCount, 1);
    });

    test('clamps budget spend to zero when only negative rows remain', () {
      final families = BudgetTransactionFamilyAdapter.build([
        _root(id: 'legacy-neg-only', amountMinor: -3000),
      ]);

      final projected = ConsumptionProjection.resolve(
        query: _query(knowledgeCutoff: _at(7, 13)),
        expenseFamilies: families,
      );
      expect(projected.value!.budgetExpenseMinor, 0);
      expect(projected.value!.purchaseOrderCount, 0);
    });

    test('knowledge cutoff sees gross before refund and net after it', () {
      final families = BudgetTransactionFamilyAdapter.build([
        _root(),
        _refund(createdAt: _at(7, 5)),
      ]);

      final before = ConsumptionProjection.resolve(
        query: _query(knowledgeCutoff: _at(7, 4, hour: 23)),
        expenseFamilies: families,
      );
      final after = ConsumptionProjection.resolve(
        query: _query(knowledgeCutoff: _at(7, 5)),
        expenseFamilies: families,
      );

      expect(before.value!.expenseMinor, 10000);
      expect(before.value!.budgetExpenseMinor, 10000);
      expect(after.value!.expenseMinor, 7000);
      expect(after.value!.budgetExpenseMinor, 7000);
    });
  });
}
