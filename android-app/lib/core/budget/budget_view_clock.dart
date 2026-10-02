/// Follow a new current month only when the user was viewing the previous
/// current month. Historical and future budget planning must remain selected.
DateTime budgetMonthAfterClockChange({
  required DateTime shown,
  required DateTime syncedNow,
  required DateTime now,
}) {
  final shownMonth = DateTime(shown.year, shown.month);
  final syncedMonth = DateTime(syncedNow.year, syncedNow.month);
  return shownMonth == syncedMonth ? DateTime(now.year, now.month) : shownMonth;
}
