import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/asset_enhancements.dart';

AssetUsageEventPoint _usage(
  String id,
  int delta, {
  int order = 0,
  String? reversalOf,
}) =>
    AssetUsageEventPoint(
      id: id,
      countDelta: delta,
      occurredMs: order,
      reversalOf: reversalOf,
    );

void main() {
  group('asset reminder status', () {
    final today = DateTime(2026, 7, 13, 23, 30);

    test('distinguishes missing, inactive, due today and expired dates', () {
      expect(
        resolveAssetReminder(dueAt: null, isActive: true, asOf: today).status,
        AssetReminderStatus.none,
      );
      expect(
        resolveWarrantyReminder(
          warrantyUntil: DateTime(2026, 7, 13, 0, 1),
          isEconomicallyOwned: false,
          asOf: today,
        ).status,
        AssetReminderStatus.inactive,
      );
      expect(
        resolveWarrantyReminder(
          warrantyUntil: DateTime(2026, 7, 13, 0, 1),
          isEconomicallyOwned: true,
          asOf: today,
        ).status,
        AssetReminderStatus.dueToday,
      );
      final expired = resolveReceivableDueReminder(
        dueAt: DateTime(2026, 7, 12, 23, 59),
        isCollectible: true,
        asOf: today,
      );
      expect(expired.status, AssetReminderStatus.expired);
      expect(expired.daysUntilDue, -1);
      expect(expired.needsAttention, isTrue);
    });

    test('30-day boundary is upcoming while day 31 is not', () {
      final boundary = resolveAssetReminder(
        dueAt: DateTime(2026, 8, 12),
        isActive: true,
        asOf: today,
      );
      final outside = resolveAssetReminder(
        dueAt: DateTime(2026, 8, 13),
        isActive: true,
        asOf: today,
      );

      expect(boundary.status, AssetReminderStatus.upcoming);
      expect(boundary.daysUntilDue, 30);
      expect(outside.status, AssetReminderStatus.none);
      expect(outside.daysUntilDue, 31);
    });

    test('rejects a negative reminder window', () {
      expect(
        () => resolveAssetReminder(
          dueAt: today,
          isActive: true,
          upcomingWindowDays: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('asset usage event aggregation', () {
    test('sums integer deltas in deterministic event order', () {
      final result = aggregateAssetUsage([
        _usage('add-two', 2, order: 20),
        _usage('add-one', 1, order: 10),
        _usage('remove-one', -1, order: 30),
      ]);

      expect(result.totalCount, 2);
      expect(result.isExact, isTrue);
    });

    test('reversal removes its target and reversal of reversal restores it',
        () {
      final reversed = aggregateAssetUsage([
        _usage('use', 1, order: 10),
        _usage('undo', 0, order: 20, reversalOf: 'use'),
      ]);
      final restored = aggregateAssetUsage([
        _usage('use', 1, order: 10),
        _usage('undo', 0, order: 20, reversalOf: 'use'),
        _usage('redo', 0, order: 30, reversalOf: 'undo'),
      ]);

      expect(reversed.totalCount, 0);
      expect(reversed.isExact, isTrue);
      expect(restored.totalCount, 1);
      expect(restored.isExact, isTrue);
    });

    test('invalid negative history is reported and never returns below zero',
        () {
      final result = aggregateAssetUsage([
        _usage('bad-correction', -2, order: 10),
        _usage('later-use', 1, order: 20),
      ]);

      expect(result.totalCount, 1);
      expect(result.isExact, isFalse);
      expect(result.issues.single, contains('小于 0'));
    });

    test('unknown and malformed reversals are conflicts without changing count',
        () {
      final result = aggregateAssetUsage([
        _usage('use', 2, order: 10),
        _usage('unknown', 0, order: 20, reversalOf: 'missing'),
        _usage('nonzero', -2, order: 30, reversalOf: 'use'),
      ]);

      expect(result.totalCount, 0);
      expect(result.isExact, isFalse);
      expect(result.issues, hasLength(2));
      expect(result.issues.join(' '), contains('不存在'));
      expect(result.issues.join(' '), contains('必须为 0'));
    });

    test('future targets and duplicate active reversals are conflicts', () {
      final result = aggregateAssetUsage([
        _usage('future-undo', 0, order: 5, reversalOf: 'future-use'),
        _usage('future-use', 1, order: 10),
        _usage('use', 1, order: 20),
        _usage('undo-one', 0, order: 30, reversalOf: 'use'),
        _usage('undo-two', 0, order: 40, reversalOf: 'use'),
      ]);

      expect(result.totalCount, 1);
      expect(result.isExact, isFalse);
      expect(result.issues.join(' '), contains('更早'));
      expect(result.issues.join(' '), contains('重复撤销'));
    });
  });
}
