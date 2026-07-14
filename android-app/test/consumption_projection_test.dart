import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/statistics/consumption_projection.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

DateTime _day(int month, int day, {int hour = 0}) =>
    DateTime.utc(2026, month, day, hour);

MetricQuery _query({
  int month = 6,
  DateTime? asOf,
  DateTime? knowledgeCutoff,
  MetricCurrencyScope? currencyScope,
}) =>
    MetricQuery(
      metricId: 'F-TXN-SUMMARY',
      window: MetricWindow(
        startInclusive: DateTime.utc(2026, month, 1),
        endExclusive: DateTime.utc(2026, month + 1, 1),
      ),
      dateAxis: MetricDateAxis.attribution,
      timezone: 'Asia/Shanghai',
      bookScope: MetricBookScope(bookIds: [1], scopeVersion: 1),
      currencyScope: currencyScope ?? MetricCurrencyScope.single('CNY'),
      asOf: asOf ?? _day(7, 13, hour: 12),
      knowledgeCutoff: knowledgeCutoff ?? asOf ?? _day(7, 13, hour: 12),
    );

ConsumptionExpenseFamily _family({
  String id = 'expense-1',
  int? bookId = 1,
  String currencyCode = 'CNY',
  DateTime? attributionDate,
  DateTime? createdAt,
  int originalAmountMinor = 10000,
  bool countsInIncomeExpense = true,
  bool countsInBudget = true,
  List<ConsumptionCategoryAllocation> categoryAllocations = const [],
  List<ConsumptionRefund> refunds = const [],
}) =>
    ConsumptionExpenseFamily(
      id: id,
      bookId: bookId,
      currencyCode: currencyCode,
      attributionDate: attributionDate ?? _day(6, 20),
      createdAt: createdAt ?? _day(6, 20),
      originalAmountMinor: originalAmountMinor,
      countsInIncomeExpense: countsInIncomeExpense,
      countsInBudget: countsInBudget,
      categoryAllocations: categoryAllocations,
      refunds: refunds,
    );

ConsumptionRefund _refund({
  String id = 'refund-1',
  int amountMinor = 3000,
  DateTime? effectiveAt,
  DateTime? createdAt,
  List<ConsumptionRefundAllocation> categoryAllocations = const [],
}) =>
    ConsumptionRefund(
      id: id,
      amountMinor: amountMinor,
      effectiveAt: effectiveAt ?? _day(7, 5),
      createdAt: createdAt ?? _day(7, 5),
      categoryAllocations: categoryAllocations,
    );

void main() {
  group('ConsumptionProjection family truth', () {
    test('later refund corrects original consumption period, not income', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(refunds: [_refund()]),
        ],
      );

      expect(result.status, MetricStatus.available);
      expect(result.value!.expenseMinor, 7000);
      expect(result.value!.budgetExpenseMinor, 7000);
      expect(result.value!.incomeMinor, 0);
      expect(result.value!.expenseCount, 1);
      expect(result.value!.purchaseOrderCount, 1);
      expect(result.value!.refundedPurchaseCount, 1);
    });

    test('frozen cutoff cannot see a refund recorded later', () {
      final frozenAt = _day(6, 30, hour: 23);
      final result = ConsumptionProjection.resolve(
        query: _query(asOf: frozenAt, knowledgeCutoff: frozenAt),
        expenseFamilies: [
          _family(refunds: [_refund()]),
        ],
      );

      expect(result.value!.expenseMinor, 10000);
      expect(result.value!.refundedPurchaseCount, 0);
    });

    test('full refund keeps purchase order but removes expense count', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(refunds: [_refund(amountMinor: 10000)]),
        ],
      );

      expect(result.value!.expenseMinor, 0);
      expect(result.value!.expenseCount, 0);
      expect(result.value!.purchaseOrderCount, 1);
      expect(result.value!.refundedPurchaseCount, 1);
      expect(result.value!.hasAverageExpense, isFalse);
      expect(result.value!.expenseByCategory, isEmpty);
    });

    test('refunds exceeding the original amount are a conflict', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(refunds: [_refund(amountMinor: 10001)]),
        ],
      );

      expect(result.status, MetricStatus.conflict);
      expect(
        result.reasons.map((reason) => reason.code),
        contains(MetricReasonCode.refundExceedsOriginal),
      );
    });

    test('excluded expense remains an order but not an ordinary total', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(
            countsInIncomeExpense: false,
            countsInBudget: false,
            refunds: [_refund()],
          ),
        ],
        standaloneEvents: [
          ConsumptionStandaloneEvent(
            id: 'transfer-1',
            type: ConsumptionStandaloneEventType.transfer,
            bookId: 1,
            currencyCode: 'CNY',
            attributionDate: _day(6, 20),
            createdAt: _day(6, 20),
            amountMinor: 50000,
            countsInIncomeExpense: true,
          ),
        ],
      );

      expect(result.value!.expenseMinor, 0);
      expect(result.value!.incomeMinor, 0);
      expect(result.value!.expenseCount, 0);
      expect(result.value!.purchaseOrderCount, 1);
      expect(result.value!.refundedPurchaseCount, 1);
      expect(result.value!.incomeCount, 0);
    });
  });

  group('ConsumptionProjection scope and cutoff', () {
    test('single-currency result excludes and reports other currencies', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(id: 'cny', originalAmountMinor: 1000),
          _family(
            id: 'usd',
            currencyCode: 'USD',
            originalAmountMinor: 2000,
          ),
        ],
      );

      expect(result.status, MetricStatus.partial);
      expect(result.value!.expenseMinor, 1000);
      expect(result.value!.excludedCurrencyEventCount, 1);
      expect(result.value!.excludedCurrencyCodes, {'USD'});
      expect(
        result.reasons.map((reason) => reason.code),
        contains(MetricReasonCode.unsupportedCurrencyAggregation),
      );
    });

    test('multi-currency aggregation without rates is rejected', () {
      final result = ConsumptionProjection.resolve(
        query: _query(
          currencyScope: MetricCurrencyScope(['CNY', 'USD']),
        ),
      );

      expect(result.status, MetricStatus.conflict);
      expect(
        result.reasons.single.code,
        MetricReasonCode.unsupportedCurrencyAggregation,
      );
    });

    test('future attribution is excluded from through-now totals', () {
      final result = ConsumptionProjection.resolve(
        query: _query(
          month: 7,
          asOf: _day(7, 13, hour: 12),
          knowledgeCutoff: _day(7, 13, hour: 12),
        ),
        expenseFamilies: [
          _family(
            attributionDate: _day(7, 20),
            createdAt: _day(7, 10),
          ),
        ],
      );

      expect(result.value!.expenseMinor, 0);
      expect(result.value!.excludedFutureEventCount, 1);
    });

    test('frozen knowledge cutoff excludes later-effective attribution', () {
      final result = ConsumptionProjection.resolve(
        query: _query(
          month: 7,
          asOf: _day(7, 31, hour: 12),
          knowledgeCutoff: _day(7, 13, hour: 12),
        ),
        expenseFamilies: [
          _family(
            attributionDate: _day(7, 20),
            createdAt: _day(7, 10),
          ),
        ],
      );

      expect(result.value!.expenseMinor, 0);
      expect(result.value!.excludedFutureEventCount, 1);
    });

    test('unknown book scope is partial rather than silently zero', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [_family(bookId: null)],
      );

      expect(result.status, MetricStatus.partial);
      expect(result.value!.expenseMinor, 0);
      expect(result.value!.unknownScopeEventCount, 1);
      expect(
        result.reasons.single.code,
        MetricReasonCode.unknownBookScope,
      );
    });
  });

  group('ConsumptionProjection amount and count units', () {
    test('budget and ordinary category policies stay independent', () {
      final ordinaryOnly = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(
            countsInIncomeExpense: true,
            countsInBudget: false,
            categoryAllocations: const [
              ConsumptionCategoryAllocation(
                categoryKey: 'dining',
                categoryName: 'Dining',
                amountMinor: 10000,
              ),
            ],
          ),
        ],
      );
      final budgetOnly = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(
            countsInIncomeExpense: false,
            countsInBudget: true,
            categoryAllocations: const [
              ConsumptionCategoryAllocation(
                categoryKey: 'dining',
                categoryName: 'Dining',
                amountMinor: 10000,
              ),
            ],
          ),
        ],
      );

      expect(ordinaryOnly.value!.expenseMinor, 10000);
      expect(ordinaryOnly.value!.budgetExpenseMinor, 0);
      expect(ordinaryOnly.value!.expenseByCategory.single.amountMinor, 10000);
      expect(ordinaryOnly.value!.budgetExpenseByCategory, isEmpty);
      expect(budgetOnly.value!.expenseMinor, 0);
      expect(budgetOnly.value!.budgetExpenseMinor, 10000);
      expect(budgetOnly.value!.expenseByCategory, isEmpty);
      expect(
        budgetOnly.value!.budgetExpenseByCategory.single.amountMinor,
        10000,
      );
    });

    test('income counts distinct ordinary events and uses integer minor units',
        () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        standaloneEvents: [
          ConsumptionStandaloneEvent.ordinaryIncome(
            id: 'income-1',
            bookId: 1,
            currencyCode: 'CNY',
            attributionDate: _day(6, 5),
            createdAt: _day(6, 5),
            amountMinor: 12345,
          ),
        ],
      );

      expect(result.value!.incomeMinor, 12345);
      expect(result.value!.incomeCount, 1);
      expect(result.value!.balanceMinor, 12345);
    });

    test('one split family can count once in multiple categories', () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(
            categoryAllocations: const [
              ConsumptionCategoryAllocation(
                categoryKey: 'dining',
                categoryName: '食品餐饮',
                amountMinor: 6000,
              ),
              ConsumptionCategoryAllocation(
                categoryKey: 'shopping',
                categoryName: '购物消费',
                amountMinor: 4000,
              ),
            ],
            refunds: [
              _refund(
                amountMinor: 1000,
                categoryAllocations: const [
                  ConsumptionRefundAllocation(
                    categoryKey: 'dining',
                    amountMinor: 1000,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      expect(result.value!.expenseMinor, 9000);
      expect(result.value!.expenseCount, 1);
      expect(result.value!.expenseByCategory, hasLength(2));
      expect(
        result.value!.expenseByCategory
            .map((category) => category.familyCount)
            .toList(),
        [1, 1],
      );
      expect(
        result.value!.expenseByCategory
            .map((category) => category.amountMinor)
            .toList(),
        [5000, 4000],
      );
    });

    test('unallocated refund on a split family returns a partial breakdown',
        () {
      final result = ConsumptionProjection.resolve(
        query: _query(),
        expenseFamilies: [
          _family(
            categoryAllocations: const [
              ConsumptionCategoryAllocation(
                categoryKey: 'dining',
                categoryName: '食品餐饮',
                amountMinor: 6000,
              ),
              ConsumptionCategoryAllocation(
                categoryKey: 'shopping',
                categoryName: '购物消费',
                amountMinor: 4000,
              ),
            ],
            refunds: [_refund(amountMinor: 1000)],
          ),
        ],
      );

      expect(result.status, MetricStatus.partial);
      expect(result.value!.expenseMinor, 9000);
      expect(result.value!.categoryBreakdownComplete, isFalse);
      expect(result.value!.unallocatedCategoryRefundMinor, 1000);
    });
  });
}
