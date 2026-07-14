import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/asset_allocation.dart';

void main() {
  test('validates gross, refund, and net independently', () {
    final totals = AssetAllocationPolicy.validate(
      orderGrossCents: 10000,
      validOrderRefundCents: 3000,
      lines: const [
        AssetAllocationLine(assetId: 1, grossCents: 6000, refundCents: 3000),
        AssetAllocationLine(assetId: 2, grossCents: 4000, refundCents: 0),
      ],
    );

    expect(totals.grossCents, 10000);
    expect(totals.refundCents, 3000);
    expect(totals.netCents, 7000);
  });

  test('rejects over-allocation even when a net-only check would pass', () {
    expect(
      () => AssetAllocationPolicy.validate(
        orderGrossCents: 10000,
        validOrderRefundCents: 5000,
        lines: const [
          AssetAllocationLine(
            assetId: 1,
            grossCents: 12000,
            refundCents: 7000,
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('rejects duplicate asset allocation for one order', () {
    expect(
      () => AssetAllocationPolicy.validate(
        orderGrossCents: 10000,
        validOrderRefundCents: 0,
        lines: const [
          AssetAllocationLine(assetId: 1, grossCents: 4000, refundCents: 0),
          AssetAllocationLine(assetId: 1, grossCents: 6000, refundCents: 0),
        ],
      ),
      throwsStateError,
    );
  });

  test('storage enums retain pending and manual quality', () {
    expect(
      AssetAllocationCostQualityX.fromStorage('pending_refund_allocation'),
      AssetAllocationCostQuality.pendingRefundAllocation,
    );
    expect(
      AssetAcquisitionCostSourceX.fromStorage('transaction_allocations'),
      AssetAcquisitionCostSource.transactionAllocations,
    );
  });
}
