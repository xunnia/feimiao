enum TransactionTimePrecision {
  exact,
  entryClock,
  dateOnly,
  legacyUnknown,
}

extension TransactionTimePrecisionX on TransactionTimePrecision {
  String get storageKey => switch (this) {
        TransactionTimePrecision.exact => 'exact',
        TransactionTimePrecision.entryClock => 'entry_clock',
        TransactionTimePrecision.dateOnly => 'date_only',
        TransactionTimePrecision.legacyUnknown => 'legacy_unknown',
      };

  static TransactionTimePrecision fromStorage(String? value) => switch (value) {
        'exact' => TransactionTimePrecision.exact,
        'entry_clock' => TransactionTimePrecision.entryClock,
        'date_only' => TransactionTimePrecision.dateOnly,
        _ => TransactionTimePrecision.legacyUnknown,
      };
}

bool transactionTimeIsMidnight(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

/// Whether a transaction clock is meaningful enough to show in a list card.
///
/// Legacy non-midnight values remain visible because they contain useful
/// information. A legacy midnight is ambiguous, so it is treated as a missing
/// clock instead of claiming the purchase happened at exactly 00:00.
bool shouldShowTransactionClock(
  DateTime value,
  TransactionTimePrecision precision,
) =>
    switch (precision) {
      TransactionTimePrecision.exact ||
      TransactionTimePrecision.entryClock =>
        true,
      TransactionTimePrecision.dateOnly => false,
      TransactionTimePrecision.legacyUnknown =>
        !transactionTimeIsMidnight(value),
    };

TransactionTimePrecision aiTransactionTimePrecision(String raw) {
  final value = raw.trim();
  if (value.isEmpty || DateTime.tryParse(value) == null) {
    return TransactionTimePrecision.entryClock;
  }
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
      ? TransactionTimePrecision.entryClock
      : TransactionTimePrecision.exact;
}

/// Transaction timestamp helpers shared by entry surfaces.
///
/// A calendar picker and an AI response containing only `YYYY-MM-DD` carry a
/// day, not a clock value. Treating that value as a complete timestamp stores
/// an accidental midnight. These helpers combine that day with the real entry
/// clock while leaving sources that explicitly provide a time untouched.
DateTime calendarDayWithClock(DateTime day, DateTime clock) {
  if (day.isUtc) {
    return DateTime.utc(
      day.year,
      day.month,
      day.day,
      clock.hour,
      clock.minute,
      clock.second,
      clock.millisecond,
      clock.microsecond,
    );
  }
  return DateTime(
    day.year,
    day.month,
    day.day,
    clock.hour,
    clock.minute,
    clock.second,
    clock.millisecond,
    clock.microsecond,
  );
}

/// Parses the date field returned by the entry LLM.
///
/// Date-only output inherits [fallback]'s clock because it means "that day at
/// the time this entry was submitted". An explicit ISO time, including a real
/// `00:00`, remains authoritative. Invalid or missing output uses [fallback].
DateTime parseAiTransactionTime(String raw, {required DateTime fallback}) {
  final value = raw.trim();
  if (value.isEmpty) return fallback;

  final parsed = DateTime.tryParse(value);
  if (parsed == null) return fallback;

  final isDateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
  return isDateOnly ? calendarDayWithClock(parsed, fallback) : parsed;
}
