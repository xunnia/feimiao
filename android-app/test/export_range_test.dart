import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/export/export_range.dart';

void main() {
  group('ExportRange', () {
    test('presets default to current month first, not full export', () {
      final ranges = ExportRange.presets(DateTime(2026, 7, 7, 12));

      expect(ranges.first.label, '本月');
      expect(ranges.first.start, DateTime(2026, 7, 1));
      expect(ranges.first.end, DateTime(2026, 7, 7, 23, 59, 59, 999));
      expect(ranges.first.isAll, isFalse);
      expect(ranges.last.label, '全部');
      expect(ranges.last.isAll, isTrue);
    });

    test('last month preset includes the whole previous month only', () {
      final lastMonth = ExportRange.presets(DateTime(2026, 7, 7, 12))
          .singleWhere((r) => r.label == '上月');

      expect(lastMonth.start, DateTime(2026, 6, 1));
      expect(lastMonth.end, DateTime(2026, 6, 30, 23, 59, 59, 999));
      expect(lastMonth.contains(DateTime(2026, 5, 31, 23, 59)), isFalse);
      expect(lastMonth.contains(DateTime(2026, 6, 1)), isTrue);
      expect(
          lastMonth.contains(DateTime(2026, 6, 30, 23, 59, 59, 999)), isTrue);
      expect(lastMonth.contains(DateTime(2026, 7, 1)), isFalse);
      expect(lastMonth.fileSuffix, '20260601-20260630');
    });

    test('recent 3 months starts at the first day two months ago', () {
      final recent3 = ExportRange.presets(DateTime(2026, 7, 7, 12))
          .singleWhere((r) => r.label == '近 3 个月');

      expect(recent3.start, DateTime(2026, 5, 1));
      expect(recent3.end, DateTime(2026, 7, 7, 23, 59, 59, 999));
      expect(recent3.contains(DateTime(2026, 4, 30, 23, 59)), isFalse);
      expect(recent3.contains(DateTime(2026, 5, 1)), isTrue);
      expect(recent3.contains(DateTime(2026, 7, 7, 23, 59)), isTrue);
    });

    test('custom range normalizes to full days and generates a file suffix',
        () {
      final custom = ExportRange.custom(
        start: DateTime(2026, 7, 3, 18),
        end: DateTime(2026, 7, 5, 8),
      );

      expect(custom.label, '7月3日 - 7月5日');
      expect(custom.start, DateTime(2026, 7, 3));
      expect(custom.end, DateTime(2026, 7, 5, 23, 59, 59, 999));
      expect(custom.contains(DateTime(2026, 7, 2, 23, 59)), isFalse);
      expect(custom.contains(DateTime(2026, 7, 3)), isTrue);
      expect(custom.contains(DateTime(2026, 7, 5, 23, 59, 59, 999)), isTrue);
      expect(custom.fileSuffix, '20260703-20260705');
    });

    test('one-sided ranges are not treated as full export', () {
      final fromDate = ExportRange(
        '2026年7月以后',
        start: DateTime(2026, 7, 1),
      );
      final untilDate = ExportRange(
        '截至2026年7月',
        end: DateTime(2026, 7, 31, 23, 59, 59, 999),
      );

      expect(fromDate.isAll, isFalse);
      expect(fromDate.contains(DateTime(2026, 6, 30, 23, 59)), isFalse);
      expect(fromDate.contains(DateTime(2026, 7, 1)), isTrue);
      expect(fromDate.fileSuffix, 'from-20260701');
      expect(fromDate.description, 'from 20260701');

      expect(untilDate.isAll, isFalse);
      expect(untilDate.contains(DateTime(2026, 7, 31, 23, 59)), isTrue);
      expect(untilDate.contains(DateTime(2026, 8, 1)), isFalse);
      expect(untilDate.fileSuffix, 'until-20260731');
      expect(untilDate.description, 'until 20260731');
    });
  });
}
