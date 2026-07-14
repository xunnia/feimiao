import 'metric_contract.dart';

enum ConsumptionStandaloneEventType {
  ordinaryIncome,
  transfer,
  excludedAccountMovement,
  assetSale,
  loanPrincipal,
  calibration,
  valuationChange,
}

class ConsumptionCategoryAllocation {
  final String categoryKey;
  final String categoryName;
  final int amountMinor;

  const ConsumptionCategoryAllocation({
    required this.categoryKey,
    required this.categoryName,
    required this.amountMinor,
  });
}

class ConsumptionRefundAllocation {
  final String categoryKey;
  final int amountMinor;

  const ConsumptionRefundAllocation({
    required this.categoryKey,
    required this.amountMinor,
  });
}

class ConsumptionRefund {
  final String id;
  final int amountMinor;
  final DateTime createdAt;
  final DateTime effectiveAt;
  final List<ConsumptionRefundAllocation> categoryAllocations;

  ConsumptionRefund({
    required this.id,
    required this.amountMinor,
    required this.createdAt,
    required this.effectiveAt,
    List<ConsumptionRefundAllocation> categoryAllocations = const [],
  }) : categoryAllocations = List.unmodifiable(categoryAllocations);
}

/// One original expense and its attached refunds.
class ConsumptionExpenseFamily {
  final String id;
  final int? bookId;
  final String currencyCode;
  final DateTime attributionDate;
  final DateTime createdAt;
  final int originalAmountMinor;
  final bool countsInIncomeExpense;
  final bool countsInBudget;
  final List<ConsumptionCategoryAllocation> categoryAllocations;
  final List<ConsumptionRefund> refunds;

  ConsumptionExpenseFamily({
    required this.id,
    required this.bookId,
    required this.currencyCode,
    required this.attributionDate,
    required this.createdAt,
    required this.originalAmountMinor,
    this.countsInIncomeExpense = true,
    this.countsInBudget = true,
    List<ConsumptionCategoryAllocation> categoryAllocations = const [],
    List<ConsumptionRefund> refunds = const [],
  })  : categoryAllocations = List.unmodifiable(categoryAllocations),
        refunds = List.unmodifiable(refunds);
}

/// A non-expense event. Only ordinary income can contribute to this projection.
class ConsumptionStandaloneEvent {
  final String id;
  final ConsumptionStandaloneEventType type;
  final int? bookId;
  final String currencyCode;
  final DateTime attributionDate;
  final DateTime createdAt;
  final int amountMinor;
  final bool countsInIncomeExpense;

  const ConsumptionStandaloneEvent({
    required this.id,
    required this.type,
    required this.bookId,
    required this.currencyCode,
    required this.attributionDate,
    required this.createdAt,
    required this.amountMinor,
    required this.countsInIncomeExpense,
  });

  factory ConsumptionStandaloneEvent.ordinaryIncome({
    required String id,
    required int? bookId,
    required String currencyCode,
    required DateTime attributionDate,
    required DateTime createdAt,
    required int amountMinor,
  }) =>
      ConsumptionStandaloneEvent(
        id: id,
        type: ConsumptionStandaloneEventType.ordinaryIncome,
        bookId: bookId,
        currencyCode: currencyCode,
        attributionDate: attributionDate,
        createdAt: createdAt,
        amountMinor: amountMinor,
        countsInIncomeExpense: true,
      );
}

class ConsumptionCategoryTotal {
  final String categoryKey;
  final String categoryName;
  final int amountMinor;

  /// Distinct original families with a positive net allocation in this bucket.
  final int familyCount;

  const ConsumptionCategoryTotal({
    required this.categoryKey,
    required this.categoryName,
    required this.amountMinor,
    required this.familyCount,
  });
}

class ConsumptionProjectionValue {
  final int expenseMinor;
  final int incomeMinor;
  final int budgetExpenseMinor;
  final int expenseCount;
  final int purchaseOrderCount;
  final int incomeCount;
  final int refundedPurchaseCount;
  final List<ConsumptionCategoryTotal> expenseByCategory;
  final List<ConsumptionCategoryTotal> budgetExpenseByCategory;
  final int excludedCurrencyEventCount;
  final Set<String> excludedCurrencyCodes;
  final int excludedFutureEventCount;
  final int unknownScopeEventCount;
  final int unallocatedCategoryRefundMinor;

  ConsumptionProjectionValue({
    required this.expenseMinor,
    required this.incomeMinor,
    required this.budgetExpenseMinor,
    required this.expenseCount,
    required this.purchaseOrderCount,
    required this.incomeCount,
    required this.refundedPurchaseCount,
    required Iterable<ConsumptionCategoryTotal> expenseByCategory,
    required Iterable<ConsumptionCategoryTotal> budgetExpenseByCategory,
    required this.excludedCurrencyEventCount,
    required Iterable<String> excludedCurrencyCodes,
    required this.excludedFutureEventCount,
    required this.unknownScopeEventCount,
    required this.unallocatedCategoryRefundMinor,
  })  : expenseByCategory = List.unmodifiable(expenseByCategory),
        budgetExpenseByCategory = List.unmodifiable(budgetExpenseByCategory),
        excludedCurrencyCodes = Set.unmodifiable(excludedCurrencyCodes);

  int get balanceMinor => incomeMinor - expenseMinor;

  bool get hasAverageExpense => expenseCount > 0;
  bool get hasAverageIncome => incomeCount > 0;
  bool get categoryBreakdownComplete => unallocatedCategoryRefundMinor == 0;
}

class _MutableCategoryTotal {
  final String key;
  String name;
  int amountMinor;
  int familyCount;

  _MutableCategoryTotal({
    required this.key,
    required this.name,
    required this.amountMinor,
    required this.familyCount,
  });
}

class _FamilyCategory {
  final String key;
  String name;
  int originalMinor;
  int refundMinor;

  _FamilyCategory({
    required this.key,
    required this.name,
    required this.originalMinor,
  }) : refundMinor = 0;

  int get netMinor => originalMinor - refundMinor;
}

class ConsumptionProjection {
  ConsumptionProjection._();

  static const String resolverName = 'ConsumptionProjection/v1';
  static const String otherCategoryKey = '__other__';

  static MetricResult<ConsumptionProjectionValue> resolve({
    required MetricQuery query,
    Iterable<ConsumptionExpenseFamily> expenseFamilies = const [],
    Iterable<ConsumptionStandaloneEvent> standaloneEvents = const [],
  }) {
    if (query.dateAxis != MetricDateAxis.attribution) {
      return MetricResult.conflict(
        reasons: [
          MetricReason(
            code: MetricReasonCode.dateAxisMismatch,
            message: 'Consumption projection requires the attribution axis.',
          ),
        ],
        query: query,
        resolver: resolverName,
      );
    }
    if (!query.currencyScope.canAggregateWithoutConversion) {
      return MetricResult.conflict(
        reasons: [
          MetricReason(
            code: MetricReasonCode.unsupportedCurrencyAggregation,
            message: 'Consumption totals require one explicit currency.',
          ),
        ],
        query: query,
        resolver: resolverName,
      );
    }

    var expenseMinor = 0;
    var incomeMinor = 0;
    var budgetExpenseMinor = 0;
    var expenseCount = 0;
    var purchaseOrderCount = 0;
    var incomeCount = 0;
    var refundedPurchaseCount = 0;
    var excludedCurrencyEventCount = 0;
    var excludedFutureEventCount = 0;
    var unknownScopeEventCount = 0;
    var unallocatedCategoryRefundMinor = 0;
    final excludedCurrencyCodes = <String>{};
    final categories = <String, _MutableCategoryTotal>{};
    final budgetCategories = <String, _MutableCategoryTotal>{};
    final seenIdentities = <String>{};
    final qualityReasons = <MetricReason>[];
    final conflictReasons = <MetricReason>[];

    for (final family in expenseFamilies) {
      final familyId = family.id.trim();
      if (!_knownByCutoff(family.createdAt, query)) continue;
      if (!_recordIdentity(familyId, seenIdentities)) {
        conflictReasons.add(_duplicateReason(familyId));
        continue;
      }
      if (_notYetEffective(family.attributionDate, query)) {
        if (query.window.contains(family.attributionDate)) {
          excludedFutureEventCount += 1;
        }
        continue;
      }
      if (!query.window.contains(family.attributionDate)) continue;
      if (!_inScope(
        bookId: family.bookId,
        currencyCode: family.currencyCode,
        query: query,
        qualityReasons: qualityReasons,
        excludedCurrencyCodes: excludedCurrencyCodes,
        onUnknownScope: () => unknownScopeEventCount += 1,
        onExcludedCurrency: () => excludedCurrencyEventCount += 1,
      )) {
        continue;
      }
      if (family.originalAmountMinor <= 0) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'Expense family amount must be positive.',
          details: {'familyId': familyId},
        ));
        continue;
      }

      final familyCategories = _buildFamilyCategories(
        family,
        conflictReasons,
      );
      if (familyCategories == null) continue;

      var refundMinor = 0;
      var familyHasUnallocatedRefund = false;
      for (final refund in family.refunds) {
        if (!_refundKnownAndEffective(refund, query)) continue;
        final refundId = refund.id.trim();
        if (!_recordIdentity(refundId, seenIdentities)) {
          conflictReasons.add(_duplicateReason(refundId));
          continue;
        }
        if (refund.amountMinor <= 0) {
          conflictReasons.add(MetricReason(
            code: MetricReasonCode.invalidInput,
            message: 'Attached refund amount must be positive.',
            details: {'familyId': familyId, 'refundId': refundId},
          ));
          continue;
        }
        refundMinor += refund.amountMinor;
        if (refundMinor > family.originalAmountMinor) {
          conflictReasons.add(MetricReason(
            code: MetricReasonCode.refundExceedsOriginal,
            message: 'Attached refunds exceed the original expense.',
            details: {
              'familyId': familyId,
              'originalMinor': family.originalAmountMinor,
              'refundMinor': refundMinor,
            },
          ));
          continue;
        }
        final allocationState = _applyRefundAllocations(
          familyId: familyId,
          refund: refund,
          categories: familyCategories,
          conflictReasons: conflictReasons,
        );
        if (allocationState == _RefundAllocationState.unallocated) {
          familyHasUnallocatedRefund = true;
          unallocatedCategoryRefundMinor += refund.amountMinor;
        }
      }

      if (familyHasUnallocatedRefund) {
        qualityReasons.add(MetricReason(
          code: MetricReasonCode.unallocatedRefund,
          message: 'A split expense has a refund without category allocation.',
          details: {'familyId': familyId},
        ));
      }
      final netMinor = family.originalAmountMinor - refundMinor;
      if (netMinor < 0) continue;

      purchaseOrderCount += 1;
      if (refundMinor > 0) refundedPurchaseCount += 1;
      if (family.countsInIncomeExpense) {
        if (netMinor > 0) {
          expenseMinor += netMinor;
          expenseCount += 1;
          _addFamilyCategories(categories, familyCategories);
        }
      }
      if (family.countsInBudget && netMinor > 0) {
        budgetExpenseMinor += netMinor;
        _addFamilyCategories(budgetCategories, familyCategories);
      }
    }

    for (final event in standaloneEvents) {
      if (!_knownByCutoff(event.createdAt, query)) continue;
      final eventId = event.id.trim();
      if (!_recordIdentity(eventId, seenIdentities)) {
        conflictReasons.add(_duplicateReason(eventId));
        continue;
      }
      final contributes =
          event.type == ConsumptionStandaloneEventType.ordinaryIncome &&
              event.countsInIncomeExpense;
      if (!contributes) continue;
      if (_notYetEffective(event.attributionDate, query)) {
        if (query.window.contains(event.attributionDate)) {
          excludedFutureEventCount += 1;
        }
        continue;
      }
      if (!query.window.contains(event.attributionDate)) continue;
      if (!_inScope(
        bookId: event.bookId,
        currencyCode: event.currencyCode,
        query: query,
        qualityReasons: qualityReasons,
        excludedCurrencyCodes: excludedCurrencyCodes,
        onUnknownScope: () => unknownScopeEventCount += 1,
        onExcludedCurrency: () => excludedCurrencyEventCount += 1,
      )) {
        continue;
      }
      if (event.amountMinor <= 0) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'Ordinary income amount must be positive.',
          details: {'eventId': eventId},
        ));
        continue;
      }
      incomeMinor += event.amountMinor;
      incomeCount += 1;
    }

    if (conflictReasons.isNotEmpty) {
      return MetricResult.conflict(
        reasons: conflictReasons,
        query: query,
        resolver: resolverName,
      );
    }

    final categoryResults = categories.values
        .where((category) => category.amountMinor > 0)
        .map((category) => ConsumptionCategoryTotal(
              categoryKey: category.key,
              categoryName: category.name,
              amountMinor: category.amountMinor,
              familyCount: category.familyCount,
            ))
        .toList()
      ..sort((left, right) {
        final amountOrder = right.amountMinor.compareTo(left.amountMinor);
        if (amountOrder != 0) return amountOrder;
        return left.categoryKey.compareTo(right.categoryKey);
      });
    final budgetCategoryResults = budgetCategories.values
        .where((category) => category.amountMinor > 0)
        .map((category) => ConsumptionCategoryTotal(
              categoryKey: category.key,
              categoryName: category.name,
              amountMinor: category.amountMinor,
              familyCount: category.familyCount,
            ))
        .toList()
      ..sort((left, right) {
        final amountOrder = right.amountMinor.compareTo(left.amountMinor);
        if (amountOrder != 0) return amountOrder;
        return left.categoryKey.compareTo(right.categoryKey);
      });

    final value = ConsumptionProjectionValue(
      expenseMinor: expenseMinor,
      incomeMinor: incomeMinor,
      budgetExpenseMinor: budgetExpenseMinor,
      expenseCount: expenseCount,
      purchaseOrderCount: purchaseOrderCount,
      incomeCount: incomeCount,
      refundedPurchaseCount: refundedPurchaseCount,
      expenseByCategory: categoryResults,
      budgetExpenseByCategory: budgetCategoryResults,
      excludedCurrencyEventCount: excludedCurrencyEventCount,
      excludedCurrencyCodes: excludedCurrencyCodes,
      excludedFutureEventCount: excludedFutureEventCount,
      unknownScopeEventCount: unknownScopeEventCount,
      unallocatedCategoryRefundMinor: unallocatedCategoryRefundMinor,
    );
    if (excludedCurrencyEventCount > 0) {
      qualityReasons.add(MetricReason(
        code: MetricReasonCode.unsupportedCurrencyAggregation,
        message: 'Events in unsupported currencies were excluded.',
        details: {
          'eventCount': excludedCurrencyEventCount,
          'currencyCodes': excludedCurrencyCodes.toList()..sort(),
        },
      ));
    }
    if (qualityReasons.isNotEmpty) {
      return MetricResult.partial(
        value: value,
        reasons: qualityReasons,
        query: query,
        resolver: resolverName,
      );
    }
    return MetricResult.available(
      value: value,
      query: query,
      resolver: resolverName,
    );
  }

  static bool _knownByCutoff(DateTime createdAt, MetricQuery query) =>
      !createdAt.isAfter(query.knowledgeCutoff);

  static bool _notYetEffective(DateTime effectiveAt, MetricQuery query) =>
      effectiveAt.isAfter(query.asOf) ||
      effectiveAt.isAfter(query.knowledgeCutoff);

  static bool _refundKnownAndEffective(
    ConsumptionRefund refund,
    MetricQuery query,
  ) =>
      !refund.createdAt.isAfter(query.knowledgeCutoff) &&
      !refund.effectiveAt.isAfter(query.knowledgeCutoff) &&
      !refund.effectiveAt.isAfter(query.asOf);

  static bool _recordIdentity(String id, Set<String> seenIdentities) =>
      id.isNotEmpty && seenIdentities.add(id);

  static MetricReason _duplicateReason(String id) => MetricReason(
        code: id.isEmpty
            ? MetricReasonCode.invalidInput
            : MetricReasonCode.duplicateIdentity,
        message: id.isEmpty
            ? 'Event identities must not be empty.'
            : 'Event identity is duplicated.',
        details: {'id': id},
      );

  static bool _inScope({
    required int? bookId,
    required String currencyCode,
    required MetricQuery query,
    required List<MetricReason> qualityReasons,
    required Set<String> excludedCurrencyCodes,
    required void Function() onUnknownScope,
    required void Function() onExcludedCurrency,
  }) {
    if (bookId == null) {
      onUnknownScope();
      qualityReasons.add(MetricReason(
        code: MetricReasonCode.unknownBookScope,
        message: 'An event has no proven book scope.',
      ));
      return false;
    }
    if (!query.bookScope.contains(bookId)) return false;

    final currency = currencyCode.trim().toUpperCase();
    if (currency.isEmpty) {
      qualityReasons.add(MetricReason(
        code: MetricReasonCode.unknownCurrency,
        message: 'An event has no currency code.',
      ));
      return false;
    }
    if (!query.currencyScope.contains(currency)) {
      excludedCurrencyCodes.add(currency);
      onExcludedCurrency();
      return false;
    }
    return true;
  }

  static Map<String, _FamilyCategory>? _buildFamilyCategories(
    ConsumptionExpenseFamily family,
    List<MetricReason> conflictReasons,
  ) {
    final categories = <String, _FamilyCategory>{};
    final allocations = family.categoryAllocations.isEmpty
        ? [
            ConsumptionCategoryAllocation(
              categoryKey: otherCategoryKey,
              categoryName: '其他',
              amountMinor: family.originalAmountMinor,
            ),
          ]
        : family.categoryAllocations;
    var allocatedMinor = 0;
    for (final allocation in allocations) {
      if (allocation.amountMinor <= 0) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'Expense category allocations must be positive.',
          details: {'familyId': family.id},
        ));
        return null;
      }
      allocatedMinor += allocation.amountMinor;
      final key = _normalizedCategoryKey(allocation.categoryKey);
      final name = _normalizedCategoryName(allocation.categoryName);
      final current = categories[key];
      if (current == null) {
        categories[key] = _FamilyCategory(
          key: key,
          name: name,
          originalMinor: allocation.amountMinor,
        );
      } else {
        current.originalMinor += allocation.amountMinor;
      }
    }
    if (allocatedMinor != family.originalAmountMinor) {
      conflictReasons.add(MetricReason(
        code: MetricReasonCode.invalidInput,
        message: 'Expense category allocations must equal the original amount.',
        details: {
          'familyId': family.id,
          'originalMinor': family.originalAmountMinor,
          'allocatedMinor': allocatedMinor,
        },
      ));
      return null;
    }
    return categories;
  }

  static _RefundAllocationState _applyRefundAllocations({
    required String familyId,
    required ConsumptionRefund refund,
    required Map<String, _FamilyCategory> categories,
    required List<MetricReason> conflictReasons,
  }) {
    if (refund.categoryAllocations.isEmpty) {
      if (categories.length != 1) return _RefundAllocationState.unallocated;
      final category = categories.values.single;
      category.refundMinor += refund.amountMinor;
      if (category.refundMinor > category.originalMinor) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.refundExceedsOriginal,
          message: 'Category refunds exceed the original allocation.',
          details: {'familyId': familyId, 'refundId': refund.id},
        ));
        return _RefundAllocationState.invalid;
      }
      return _RefundAllocationState.applied;
    }

    var allocatedMinor = 0;
    final pending = <String, int>{};
    for (final allocation in refund.categoryAllocations) {
      if (allocation.amountMinor <= 0) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'Refund category allocations must be positive.',
          details: {'familyId': familyId, 'refundId': refund.id},
        ));
        return _RefundAllocationState.invalid;
      }
      final key = _normalizedCategoryKey(allocation.categoryKey);
      if (!categories.containsKey(key)) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'Refund allocation references an unknown category.',
          details: {
            'familyId': familyId,
            'refundId': refund.id,
            'categoryKey': key,
          },
        ));
        return _RefundAllocationState.invalid;
      }
      allocatedMinor += allocation.amountMinor;
      pending[key] = (pending[key] ?? 0) + allocation.amountMinor;
    }
    if (allocatedMinor != refund.amountMinor) {
      conflictReasons.add(MetricReason(
        code: MetricReasonCode.invalidInput,
        message: 'Refund category allocations must equal the refund amount.',
        details: {'familyId': familyId, 'refundId': refund.id},
      ));
      return _RefundAllocationState.invalid;
    }
    for (final entry in pending.entries) {
      final category = categories[entry.key]!;
      if (category.refundMinor + entry.value > category.originalMinor) {
        conflictReasons.add(MetricReason(
          code: MetricReasonCode.refundExceedsOriginal,
          message: 'Category refunds exceed the original allocation.',
          details: {
            'familyId': familyId,
            'refundId': refund.id,
            'categoryKey': entry.key,
          },
        ));
        return _RefundAllocationState.invalid;
      }
    }
    for (final entry in pending.entries) {
      categories[entry.key]!.refundMinor += entry.value;
    }
    return _RefundAllocationState.applied;
  }

  static void _addFamilyCategories(
    Map<String, _MutableCategoryTotal> totals,
    Map<String, _FamilyCategory> familyCategories,
  ) {
    for (final category in familyCategories.values) {
      if (category.netMinor <= 0) continue;
      final total = totals[category.key];
      if (total == null) {
        totals[category.key] = _MutableCategoryTotal(
          key: category.key,
          name: category.name,
          amountMinor: category.netMinor,
          familyCount: 1,
        );
      } else {
        total.amountMinor += category.netMinor;
        total.familyCount += 1;
      }
    }
  }

  static String _normalizedCategoryKey(String raw) {
    final key = raw.trim();
    return key.isEmpty ? otherCategoryKey : key;
  }

  static String _normalizedCategoryName(String raw) {
    final name = raw.trim();
    if (name.isEmpty ||
        name == '-' ||
        name == '—' ||
        name == '未分类' ||
        name == '其他支出') {
      return '其他';
    }
    return name;
  }
}

enum _RefundAllocationState {
  applied,
  unallocated,
  invalid,
}
