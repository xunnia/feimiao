import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/account/net_worth_verified_checkpoint.dart';

final _cny = NetWorthCurrencyCoverage.single('CNY');

NetWorthVerifiedCheckpointItem _item(
  String type,
  String uuid,
  int amount, {
  String currency = 'CNY',
  int day = 1,
}) {
  return NetWorthVerifiedCheckpointItem(
    objectType: type,
    objectUuid: uuid,
    confirmedAmountMinor: amount,
    currencyCode: currency,
    valueEffectiveAt: DateTime.utc(2026, 7, day, 10),
    valueSource: 'user_confirmation',
    quality: 'confirmed',
  );
}

NetWorthVerifiedCheckpoint _checkpoint({
  required int day,
  int assets = 10000,
  int liabilities = 0,
  int scopeVersion = 1,
  int calculationVersion = 1,
  NetWorthCurrencyCoverage? currencies,
  NetWorthVerifiedCheckpointCompleteness completeness =
      NetWorthVerifiedCheckpointCompleteness.complete,
  NetWorthVerifiedCheckpointStatus status =
      NetWorthVerifiedCheckpointStatus.active,
  Iterable<NetWorthVerifiedCheckpointReason>? reasons,
  Iterable<NetWorthVerifiedCheckpointItem> items = const [],
}) {
  final asOf = DateTime.utc(2026, 7, day, 10);
  return NetWorthVerifiedCheckpoint(
    header: NetWorthVerifiedCheckpointHeader(
      id: day,
      uuid: 'checkpoint-$day',
      asOf: asOf,
      knowledgeCutoff: asOf,
      scopeVersion: scopeVersion,
      calculationVersion: calculationVersion,
      currencyCoverage: currencies ?? _cny,
      totals: NetWorthVerifiedCheckpointTotals.checked(
        totalAssetsMinor: assets,
        totalLiabilitiesMinor: liabilities,
        netWorthMinor: assets - liabilities,
      ),
      completeness: completeness,
      incompletenessReasons: reasons ??
          (completeness == NetWorthVerifiedCheckpointCompleteness.partial
              ? [
                  NetWorthVerifiedCheckpointReason(
                    code: 'missing_object',
                    message: 'One included object was not confirmed.',
                  ),
                ]
              : const []),
      status: status,
      createdAt: asOf,
    ),
    items: items,
  );
}

void main() {
  group('verified checkpoint evidence', () {
    test('defensively freezes header reasons, details, and item collection',
        () {
      final details = <String, Object?>{'count': 1};
      final reasons = <NetWorthVerifiedCheckpointReason>[
        NetWorthVerifiedCheckpointReason(
          code: 'missing',
          message: 'Missing evidence.',
          details: details,
        ),
      ];
      final items = <NetWorthVerifiedCheckpointItem>[
        _item('account', 'cash', 10000),
      ];
      final checkpoint = _checkpoint(
        day: 1,
        completeness: NetWorthVerifiedCheckpointCompleteness.partial,
        reasons: reasons,
        items: items,
      );

      details['count'] = 99;
      reasons.clear();
      items.clear();

      expect(checkpoint.header.incompletenessReasons, hasLength(1));
      expect(
        checkpoint.header.incompletenessReasons.single.details['count'],
        1,
      );
      expect(checkpoint.items.single.key.objectUuid, 'cash');
      expect(() => checkpoint.items.clear(), throwsUnsupportedError);
    });

    test('partial evidence needs a reason and complete evidence needs coverage',
        () {
      expect(
        () => _checkpoint(
          day: 1,
          completeness: NetWorthVerifiedCheckpointCompleteness.partial,
          reasons: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => _checkpoint(
          day: 1,
          currencies: NetWorthCurrencyCoverage(
            baseCurrency: 'CNY',
            coveredCurrencies: const ['CNY'],
            uncoveredCurrencies: const ['USD'],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('stored totals must retain the accounting identity', () {
      expect(
        () => NetWorthVerifiedCheckpointTotals.checked(
          totalAssetsMinor: 10000,
          totalLiabilitiesMinor: 3000,
          netWorthMinor: 8000,
        ),
        throwsArgumentError,
      );
    });

    test('duplicate object evidence is rejected', () {
      expect(
        () => _checkpoint(
          day: 1,
          items: [
            _item('account', 'same', 100),
            _item('ACCOUNT', 'same', 200),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('unknown persisted lifecycle and completeness fail closed', () {
      expect(
        NetWorthVerifiedCheckpointStatusX.fromStorage('future'),
        NetWorthVerifiedCheckpointStatus.revoked,
      );
      expect(
        NetWorthVerifiedCheckpointCompletenessX.fromStorage('future'),
        NetWorthVerifiedCheckpointCompleteness.partial,
      );
    });
  });

  group('verified checkpoint comparison', () {
    test('uses frozen totals and items while allowing normal object turnover',
        () {
      final earlierSource = <NetWorthVerifiedCheckpointItem>[
        _item('account', 'cash', 10000, day: 1),
        _item('physical_asset', 'old-phone', 2000, day: 1),
      ];
      final earlier = _checkpoint(
        day: 1,
        assets: 12000,
        items: earlierSource,
      );
      final later = _checkpoint(
        day: 2,
        assets: 15500,
        liabilities: 1000,
        items: [
          _item('account', 'cash', 10500, day: 2),
          _item('physical_asset', 'new-phone', 5000, day: 2),
          _item('liability', 'card', -1000, day: 2),
        ],
      );

      // Simulates current repository state changing after evidence was saved.
      earlierSource
        ..clear()
        ..add(_item('account', 'unrelated-current-state', 999999, day: 2));
      final result = compareNetWorthVerifiedCheckpoints(earlier, later);

      expect(result.isComparable, isTrue);
      expect(result.issues, isEmpty);
      expect(result.change?.totalAssetsDeltaMinor, 3500);
      expect(result.change?.totalLiabilitiesDeltaMinor, 1000);
      expect(result.change?.netWorthDeltaMinor, 2500);
      expect(
        result.change?.objectChanges
            .where((change) =>
                change.type == NetWorthVerifiedObjectChangeType.added)
            .map((change) => change.key.objectUuid),
        containsAll(['new-phone', 'card']),
      );
      expect(
        result.change?.objectChanges
            .singleWhere((change) => change.key.objectUuid == 'old-phone')
            .type,
        NetWorthVerifiedObjectChangeType.removed,
      );
      expect(
        result.change?.objectChanges
            .singleWhere((change) => change.key.objectUuid == 'cash')
            .confirmedAmountDeltaMinor,
        500,
      );
    });

    test('partial checkpoint is incomparable and reports which side is partial',
        () {
      final earlier = _checkpoint(
        day: 1,
        completeness: NetWorthVerifiedCheckpointCompleteness.partial,
      );
      final result = compareNetWorthVerifiedCheckpoints(
        earlier,
        _checkpoint(day: 2),
      );

      expect(result.isComparable, isFalse);
      expect(result.change, isNull);
      expect(
        result.issues,
        [NetWorthVerifiedComparabilityIssue.earlierIncomplete],
      );
      expect(result.reasonMessages.single, contains('earlier checkpoint'));
    });

    test('superseded and revoked evidence cannot produce a delta', () {
      final result = compareNetWorthVerifiedCheckpoints(
        _checkpoint(
          day: 1,
          status: NetWorthVerifiedCheckpointStatus.superseded,
        ),
        _checkpoint(
          day: 2,
          status: NetWorthVerifiedCheckpointStatus.revoked,
        ),
      );

      expect(result.change, isNull);
      expect(result.issues, [
        NetWorthVerifiedComparabilityIssue.earlierNotActive,
        NetWorthVerifiedComparabilityIssue.laterNotActive,
      ]);
    });

    test('scope, calculation, and currency coverage changes give hard reasons',
        () {
      final base = _checkpoint(day: 1);
      final scope = compareNetWorthVerifiedCheckpoints(
        base,
        _checkpoint(day: 2, scopeVersion: 2),
      );
      final calculation = compareNetWorthVerifiedCheckpoints(
        base,
        _checkpoint(day: 2, calculationVersion: 2),
      );
      final currency = compareNetWorthVerifiedCheckpoints(
        base,
        _checkpoint(
          day: 2,
          currencies: NetWorthCurrencyCoverage.single('USD'),
        ),
      );

      expect(scope.change, isNull);
      expect(
        scope.issues,
        [NetWorthVerifiedComparabilityIssue.scopeVersionMismatch],
      );
      expect(
        calculation.issues,
        [NetWorthVerifiedComparabilityIssue.calculationVersionMismatch],
      );
      expect(
        currency.issues,
        [NetWorthVerifiedComparabilityIssue.currencyCoverageMismatch],
      );
    });

    test('the comparison direction must move forward in time', () {
      final result = compareNetWorthVerifiedCheckpoints(
        _checkpoint(day: 2),
        _checkpoint(day: 1),
      );

      expect(result.change, isNull);
      expect(
        result.issues,
        [NetWorthVerifiedComparabilityIssue.nonIncreasingAsOf],
      );
    });
  });
}
