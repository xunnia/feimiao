import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_view_clock.dart';

void main() {
  test('current month follows midnight across month and year boundaries', () {
    expect(
      budgetMonthAfterClockChange(
        shown: DateTime(2026, 12),
        syncedNow: DateTime(2026, 12, 31),
        now: DateTime(2027, 1, 1),
      ),
      DateTime(2027, 1),
    );
  });

  test(
      'historical and future month selections survive foreground clock changes',
      () {
    for (final shown in [DateTime(2026, 8), DateTime(2027, 2)]) {
      expect(
        budgetMonthAfterClockChange(
          shown: shown,
          syncedNow: DateTime(2026, 9, 30),
          now: DateTime(2026, 10, 1),
        ),
        shown,
      );
    }
  });

  test('clock correction follows only the selected current month', () {
    expect(
      budgetMonthAfterClockChange(
        shown: DateTime(2026, 10),
        syncedNow: DateTime(2026, 10, 1),
        now: DateTime(2026, 9, 30),
      ),
      DateTime(2026, 9),
    );
  });
}
