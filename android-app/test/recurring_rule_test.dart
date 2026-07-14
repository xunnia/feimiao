import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/recurring_rule.dart';

void main() {
  group('RecurPeriod.advance', () {
    test('daily +1 day', () {
      expect(
        RecurPeriod.daily.advance(DateTime(2026, 6, 1)),
        DateTime(2026, 6, 2),
      );
    });

    test('weekly +7 days', () {
      expect(
        RecurPeriod.weekly.advance(DateTime(2026, 6, 1)),
        DateTime(2026, 6, 8),
      );
    });

    test('monthly normal day', () {
      expect(
        RecurPeriod.monthly.advance(DateTime(2026, 1, 15)),
        DateTime(2026, 2, 15),
      );
    });

    test('monthly clamps to month-end (Jan 31 -> Feb 28/29)', () {
      expect(
        RecurPeriod.monthly.advance(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
      expect(
        RecurPeriod.monthly.advance(DateTime(2024, 1, 31)),
        DateTime(2024, 2, 29),
      );
    });

    test('monthly preview keeps original day after month-end clamp', () {
      expect(
        RecurPeriod.monthly.previewDates(DateTime(2026, 1, 31), count: 4),
        [
          DateTime(2026, 1, 31),
          DateTime(2026, 2, 28),
          DateTime(2026, 3, 31),
          DateTime(2026, 4, 30),
        ],
      );
      expect(
        RecurPeriod.monthly.previewDates(DateTime(2026, 1, 30), count: 4),
        [
          DateTime(2026, 1, 30),
          DateTime(2026, 2, 28),
          DateTime(2026, 3, 30),
          DateTime(2026, 4, 30),
        ],
      );
    });

    test('monthly rolls Dec -> next Jan', () {
      expect(
        RecurPeriod.monthly.advance(DateTime(2026, 12, 10)),
        DateTime(2027, 1, 10),
      );
    });

    test('yearly +1 year, Feb 29 -> Feb 28', () {
      expect(
        RecurPeriod.yearly.advance(DateTime(2024, 2, 29)),
        DateTime(2025, 2, 28),
      );
      expect(
        RecurPeriod.yearly.advance(DateTime(2026, 3, 5)),
        DateTime(2027, 3, 5),
      );
    });

    test('previewDates returns upcoming occurrences from first due date', () {
      expect(
        RecurPeriod.weekly.previewDates(DateTime(2026, 7, 7), count: 3),
        [
          DateTime(2026, 7, 7),
          DateTime(2026, 7, 14),
          DateTime(2026, 7, 21),
        ],
      );
    });

    test('previewDates with non-positive count returns empty list', () {
      expect(
        RecurPeriod.monthly.previewDates(DateTime(2026, 7, 7), count: 0),
        isEmpty,
      );
    });
  });

  group('RecurPeriod.fromJson', () {
    test('round trips and falls back to monthly', () {
      expect(RecurPeriod.fromJson('weekly'), RecurPeriod.weekly);
      expect(RecurPeriod.fromJson('garbage'), RecurPeriod.monthly);
    });
  });
}
