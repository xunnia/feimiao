import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/transaction_time.dart';

void main() {
  group('TransactionTimePrecision', () {
    test('storage values round-trip and unknown values stay conservative', () {
      for (final value in TransactionTimePrecision.values) {
        expect(
          TransactionTimePrecisionX.fromStorage(value.storageKey),
          value,
        );
      }
      expect(
        TransactionTimePrecisionX.fromStorage('future_value'),
        TransactionTimePrecision.legacyUnknown,
      );
    });

    test('AI date-only output records entry clock provenance', () {
      expect(
        aiTransactionTimePrecision('2026-07-13'),
        TransactionTimePrecision.entryClock,
      );
      expect(
        aiTransactionTimePrecision('2026-07-13T00:00:00'),
        TransactionTimePrecision.exact,
      );
    });
  });

  group('calendarDayWithClock', () {
    test('changes the calendar day without introducing midnight', () {
      final result = calendarDayWithClock(
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 14, 12, 34, 56, 789),
      );

      expect(result, DateTime(2026, 7, 13, 12, 34, 56, 789));
    });
  });

  group('parseAiTransactionTime', () {
    final submittedAt = DateTime(2026, 7, 14, 12, 35, 48, 321);

    test('date-only AI output inherits the real submission clock', () {
      expect(
        parseAiTransactionTime('2026-07-13', fallback: submittedAt),
        DateTime(2026, 7, 13, 12, 35, 48, 321),
      );
    });

    test('an explicitly supplied time remains authoritative', () {
      expect(
        parseAiTransactionTime(
          '2026-07-13T08:09:10',
          fallback: submittedAt,
        ),
        DateTime(2026, 7, 13, 8, 9, 10),
      );
    });

    test('an explicit midnight is not mistaken for missing time', () {
      expect(
        parseAiTransactionTime(
          '2026-07-13T00:00:00',
          fallback: submittedAt,
        ),
        DateTime(2026, 7, 13),
      );
    });

    test('invalid output falls back to the complete submission timestamp', () {
      expect(
        parseAiTransactionTime('not-a-date', fallback: submittedAt),
        submittedAt,
      );
    });
  });
}
