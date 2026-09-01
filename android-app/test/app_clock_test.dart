import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/app_clock.dart';

void main() {
  test('parses the shared parity clock with an explicit timezone', () {
    final value = AppClock.parseDemoNow('2026-08-27T12:00:00+08:00');

    expect(value, isNotNull);
    expect(value!.toUtc(), DateTime.utc(2026, 8, 27, 4));
  });

  test('ignores an invalid or empty parity clock', () {
    expect(AppClock.parseDemoNow(''), isNull);
    expect(AppClock.parseDemoNow('not-a-date'), isNull);
  });
}
