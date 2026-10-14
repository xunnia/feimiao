import 'package:decimal/decimal.dart';

enum AssetStructureKind {
  cash('流动资金'),
  investment('投资余额'),
  receivable('权益资产'),
  physical('计入物品');

  const AssetStructureKind(this.label);
  final String label;
}

class AssetStructureProjection {
  AssetStructureProjection({
    required this.totalAssets,
    required this.totalLiabilities,
    required Decimal cash,
    required Decimal investment,
    required Decimal receivable,
    required Decimal physical,
    this.partial = false,
  }) : amounts = Map.unmodifiable({
          AssetStructureKind.cash: cash,
          AssetStructureKind.investment: investment,
          AssetStructureKind.receivable: receivable,
          AssetStructureKind.physical: physical,
        });

  final Decimal totalAssets;
  final Decimal totalLiabilities;
  final Map<AssetStructureKind, Decimal> amounts;
  final bool partial;

  bool get isConsistent =>
      amounts.values.every((value) => value >= Decimal.zero) &&
      totalLiabilities >= Decimal.zero &&
      amounts.values.fold(Decimal.zero, (sum, value) => sum + value) ==
          totalAssets;

  bool get hasShares => !partial && isConsistent && totalAssets > Decimal.zero;

  Iterable<AssetStructureKind> get visibleKinds =>
      amounts.keys.where((kind) => amounts[kind] != Decimal.zero);

  Decimal? percentage(AssetStructureKind kind) => hasShares
      ? (amounts[kind]! * Decimal.fromInt(100) / totalAssets)
          .toDecimal(scaleOnInfinitePrecision: 8)
      : null;

  Decimal? get liabilityPercentage => hasShares
      ? (totalLiabilities * Decimal.fromInt(100) / totalAssets)
          .toDecimal(scaleOnInfinitePrecision: 8)
      : null;
}
