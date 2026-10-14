import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/asset_structure_projection.dart';

AssetStructureProjection projection(
        {String total = '0.06',
        String liability = '0.09',
        String cash = '0.01',
        String investment = '0.02',
        String receivable = '0.03',
        String physical = '0',
        bool partial = false}) =>
    AssetStructureProjection(
        totalAssets: Decimal.parse(total),
        totalLiabilities: Decimal.parse(liability),
        cash: Decimal.parse(cash),
        investment: Decimal.parse(investment),
        receivable: Decimal.parse(receivable),
        physical: Decimal.parse(physical),
        partial: partial);

void main() {
  test('structure keeps exact decimal amounts and original denominator', () {
    final value = projection();
    expect(value.isConsistent, isTrue);
    expect(value.visibleKinds, hasLength(3));
    expect(
        value.percentage(AssetStructureKind.cash)!.toStringAsFixed(1), '16.7');
    expect(
        value.percentage(AssetStructureKind.receivable), Decimal.fromInt(50));
    expect(value.liabilityPercentage, Decimal.fromInt(150));
  });
  test('single bucket is real 100 percent, not a second total', () {
    final value =
        projection(total: '42', cash: '42', investment: '0', receivable: '0');
    expect(value.visibleKinds, [AssetStructureKind.cash]);
    expect(value.percentage(AssetStructureKind.cash), Decimal.fromInt(100));
  });
  test('partial amounts remain visible but ratios are not asserted', () {
    final value = projection(partial: true);
    expect(value.amounts[AssetStructureKind.cash], Decimal.parse('0.01'));
    expect(value.hasShares, isFalse);
    expect(value.liabilityPercentage, isNull);
    expect(value.percentage(AssetStructureKind.cash), isNull);
  });
  test('zero denominator is not applicable, even with debt', () {
    final value =
        projection(total: '0', cash: '0', investment: '0', receivable: '0');
    expect(value.isConsistent, isTrue);
    expect(value.visibleKinds, isEmpty);
    expect(value.liabilityPercentage, isNull);
  });
  test('sum mismatch does not renormalize into a false complete chart', () {
    final value = projection(total: '1');
    expect(value.isConsistent, isFalse);
    expect(value.hasShares, isFalse);
  });
  test('negative component stays visible but cannot become a chart segment',
      () {
    final value = projection(total: '0.04', cash: '-0.01');
    expect(value.visibleKinds, contains(AssetStructureKind.cash));
    expect(value.isConsistent, isFalse);
    expect(value.percentage(AssetStructureKind.cash), isNull);
  });
  test('negative liability is invalid rather than a negative ratio', () {
    final value = projection(liability: '-1');
    expect(value.liabilityPercentage, isNull);
  });
  test('liability ratio is not capped at 999 percent', () {
    final value = projection(liability: '6');
    expect(value.liabilityPercentage, Decimal.fromInt(10000));
  });
}
