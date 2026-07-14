import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

MetricQuery _query({
  MetricWindow? window,
  MetricCurrencyScope? currencyScope,
  int calculationVersion = statisticsCalculationVersion,
}) =>
    MetricQuery(
      metricId: 'F-TXN-001',
      window: window ??
          MetricWindow(
            startInclusive: DateTime.utc(2026, 7, 1),
            endExclusive: DateTime.utc(2026, 8, 1),
          ),
      dateAxis: MetricDateAxis.attribution,
      timezone: 'Asia/Shanghai',
      bookScope: MetricBookScope(bookIds: [2, 1, 2], scopeVersion: 3),
      currencyScope: currencyScope ?? MetricCurrencyScope.single('cny'),
      asOf: DateTime.utc(2026, 7, 13, 12),
      knowledgeCutoff: DateTime.utc(2026, 7, 13, 12),
      calculationVersion: calculationVersion,
    );

void main() {
  group('MetricQuery contract', () {
    test('uses a half-open window and calculation version 1', () {
      final query = _query();

      expect(statisticsCalculationVersion, 1);
      expect(query.calculationVersion, 1);
      expect(query.window.contains(DateTime.utc(2026, 7, 1)), isTrue);
      expect(
        query.window.contains(DateTime.utc(2026, 7, 31, 23, 59, 59)),
        isTrue,
      );
      expect(query.window.contains(DateTime.utc(2026, 8, 1)), isFalse);
      expect(query.bookScope.bookIds, [1, 2]);
      expect(query.currencyScope.currencyCodes, ['CNY']);
    });

    test('rejects empty or inverted explicit scopes', () {
      expect(
        () => MetricWindow(
          startInclusive: DateTime.utc(2026, 8, 1),
          endExclusive: DateTime.utc(2026, 8, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => MetricBookScope(bookIds: const [], scopeVersion: 1),
        throwsArgumentError,
      );
      expect(
        () => MetricCurrencyScope(const []),
        throwsArgumentError,
      );
    });

    test('reports incompatible comparison context instead of comparing', () {
      final current = _query();
      final differentScope = MetricQuery(
        metricId: current.metricId,
        window: current.window,
        dateAxis: current.dateAxis,
        timezone: current.timezone,
        bookScope: MetricBookScope(bookIds: [1], scopeVersion: 4),
        currencyScope: current.currencyScope,
        asOf: current.asOf,
        knowledgeCutoff: current.knowledgeCutoff,
      );

      expect(
        current.comparabilityIssue(differentScope)?.code,
        MetricReasonCode.bookScopeMismatch,
      );
      expect(
        current.comparabilityIssue(current.copyWith(
            window: MetricWindow(
          startInclusive: DateTime.utc(2026, 6, 1),
          endExclusive: DateTime.utc(2026, 7, 1),
        ))),
        isNull,
      );
    });

    test('reason equality and hash do not depend on detail insertion order',
        () {
      final left = MetricReason(
        code: MetricReasonCode.invalidInput,
        message: 'invalid',
        details: {'familyId': 'a', 'amountMinor': 10},
      );
      final right = MetricReason(
        code: MetricReasonCode.invalidInput,
        message: 'invalid',
        details: {'amountMinor': 10, 'familyId': 'a'},
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('reason details are defensively copied and immutable', () {
      final source = <String, Object?>{'familyId': 'a'};
      final reason = MetricReason(
        code: MetricReasonCode.invalidInput,
        message: 'invalid',
        details: source,
      );

      source['familyId'] = 'changed';
      expect(reason.details, {'familyId': 'a'});
      expect(
        () => reason.details['amountMinor'] = 10,
        throwsUnsupportedError,
      );
    });
  });

  group('MetricResult quality state', () {
    test('available zero is distinct from unavailable', () {
      final query = _query();
      final zero = MetricResult<int>.available(
        value: 0,
        query: query,
        resolver: 'test/v1',
      );
      final unavailable = MetricResult<int>.unavailable(
        reasons: [
          MetricReason(
            code: MetricReasonCode.invalidInput,
            message: 'No source is configured.',
          ),
        ],
        query: query,
        resolver: 'test/v1',
      );

      expect(zero.status, MetricStatus.available);
      expect(zero.value, 0);
      expect(unavailable.status, MetricStatus.unavailable);
      expect(unavailable.value, isNull);
      expect(zero.lineage.calculationVersion, 1);
    });

    test('partial results must carry both a value and a reason', () {
      final query = _query();
      expect(
        () => MetricResult<int>.partial(
          value: 10,
          reasons: const [],
          query: query,
          resolver: 'test/v1',
        ),
        throwsArgumentError,
      );
    });
  });
}
