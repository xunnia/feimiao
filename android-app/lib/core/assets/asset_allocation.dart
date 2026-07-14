enum AssetAcquisitionCostSource {
  transactionAllocations,
  manual,
  manualUnknown,
}

extension AssetAcquisitionCostSourceX on AssetAcquisitionCostSource {
  String get storageKey => switch (this) {
        AssetAcquisitionCostSource.transactionAllocations =>
          'transaction_allocations',
        AssetAcquisitionCostSource.manual => 'manual',
        AssetAcquisitionCostSource.manualUnknown => 'manual_unknown',
      };

  static AssetAcquisitionCostSource fromStorage(String? value) =>
      switch (value) {
        'transaction_allocations' =>
          AssetAcquisitionCostSource.transactionAllocations,
        'manual_unknown' => AssetAcquisitionCostSource.manualUnknown,
        _ => AssetAcquisitionCostSource.manual,
      };
}

enum AssetAllocationCostQuality {
  exact,
  partial,
  pendingRefundAllocation,
  manualUnverified,
}

extension AssetAllocationCostQualityX on AssetAllocationCostQuality {
  String get storageKey => switch (this) {
        AssetAllocationCostQuality.exact => 'exact',
        AssetAllocationCostQuality.partial => 'partial',
        AssetAllocationCostQuality.pendingRefundAllocation =>
          'pending_refund_allocation',
        AssetAllocationCostQuality.manualUnverified => 'manual_unverified',
      };

  static AssetAllocationCostQuality fromStorage(String? value) =>
      switch (value) {
        'exact' => AssetAllocationCostQuality.exact,
        'pending_refund_allocation' =>
          AssetAllocationCostQuality.pendingRefundAllocation,
        'manual_unverified' => AssetAllocationCostQuality.manualUnverified,
        _ => AssetAllocationCostQuality.partial,
      };
}

class AssetAllocationLine {
  final int assetId;
  final int grossCents;
  final int refundCents;

  const AssetAllocationLine({
    required this.assetId,
    required this.grossCents,
    required this.refundCents,
  });

  int get netCents => grossCents - refundCents;
}

class AssetAllocationTotals {
  final int grossCents;
  final int refundCents;
  final int netCents;

  const AssetAllocationTotals({
    required this.grossCents,
    required this.refundCents,
    required this.netCents,
  });
}

class AssetAllocationPolicy {
  const AssetAllocationPolicy._();

  static AssetAllocationTotals validate({
    required int orderGrossCents,
    required int validOrderRefundCents,
    required Iterable<AssetAllocationLine> lines,
  }) {
    if (orderGrossCents < 0 ||
        validOrderRefundCents < 0 ||
        validOrderRefundCents > orderGrossCents) {
      throw ArgumentError('订单毛额或有效退款额不合法');
    }
    var gross = 0;
    var refund = 0;
    final assetIds = <int>{};
    for (final line in lines) {
      if (!assetIds.add(line.assetId)) {
        throw StateError('同一物品不能重复分配同一订单');
      }
      if (line.grossCents < 0 ||
          line.refundCents < 0 ||
          line.refundCents > line.grossCents) {
        throw ArgumentError('每件物品必须满足 0 <= 退款额 <= 毛额');
      }
      gross += line.grossCents;
      refund += line.refundCents;
    }
    if (gross > orderGrossCents) {
      throw StateError('物品毛额分配合计超过订单毛额');
    }
    if (refund > validOrderRefundCents) {
      throw StateError('物品退款分配合计超过订单有效退款');
    }
    final net = gross - refund;
    if (net > orderGrossCents - validOrderRefundCents) {
      throw StateError('物品净额分配合计超过订单净额');
    }
    return AssetAllocationTotals(
      grossCents: gross,
      refundCents: refund,
      netCents: net,
    );
  }
}
