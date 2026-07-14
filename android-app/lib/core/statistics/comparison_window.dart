import 'metric_contract.dart';

enum ComparisonWindowKind {
  calendarMonth,
  calendarWeek,
  budgetCycle,
  calendarYear,
  custom,
}

class ComparisonWindowResult {
  final MetricQuery mainQuery;
  final MetricQuery currentComparableQuery;
  final MetricQuery previousComparableQuery;
  final MetricWindow previousFullWindow;
  final bool currentWindowComplete;
  final int currentComparableDayCount;
  final int previousComparableDayCount;

  /// Non-null when the comparison is deliberately clipped to equal progress.
  final String? qualifier;

  const ComparisonWindowResult({
    required this.mainQuery,
    required this.currentComparableQuery,
    required this.previousComparableQuery,
    required this.previousFullWindow,
    required this.currentWindowComplete,
    required this.currentComparableDayCount,
    required this.previousComparableDayCount,
    required this.qualifier,
  });
}

class ComparisonWindowResolver {
  ComparisonWindowResolver._();

  static const String resolverName = 'ComparisonWindowResolver/v1';

  /// Resolves civil-calendar windows that callers have already projected into
  /// [MetricQuery.timezone]. This resolver compares calendar components only;
  /// it does not convert instants between timezones.
  static MetricResult<ComparisonWindowResult> resolve({
    required MetricQuery query,
    required ComparisonWindowKind kind,
    MetricWindow? previousBudgetCycle,
    int weekStart = DateTime.monday,
  }) {
    final current = query.window;
    if (!_isCalendarBoundary(current.startInclusive) ||
        !_isCalendarBoundary(current.endExclusive)) {
      return _conflict(query, 'Comparison windows must use day boundaries.');
    }

    final shapeIssue = _validateWindowShape(current, kind, weekStart);
    if (shapeIssue != null) return _conflict(query, shapeIssue);

    final previousFull = _previousWindow(
      current: current,
      kind: kind,
      previousBudgetCycle: previousBudgetCycle,
    );
    if (previousFull == null) {
      return MetricResult.conflict(
        reasons: [
          MetricReason(
            code: MetricReasonCode.noComparableWindow,
            message: 'The previous budget cycle must be supplied.',
          ),
        ],
        query: query,
        resolver: resolverName,
      );
    }
    if (!_isCalendarBoundary(previousFull.startInclusive) ||
        !_isCalendarBoundary(previousFull.endExclusive)) {
      return _conflict(
        query,
        'The previous comparison window must use day boundaries.',
      );
    }
    if (kind == ComparisonWindowKind.budgetCycle) {
      if (previousFull.startInclusive.isUtc != current.startInclusive.isUtc ||
          previousFull.endExclusive.isUtc != current.endExclusive.isUtc) {
        return _conflict(
          query,
          'The previous budget cycle must use the same UTC/local '
          'representation as the current cycle.',
        );
      }
      if (!previousFull.startInclusive.isBefore(current.startInclusive) ||
          previousFull.endExclusive != current.startInclusive) {
        return _conflict(
          query,
          'The previous budget cycle must end where the current cycle starts.',
        );
      }
    }

    final previousDays = _calendarDaysBetween(
      previousFull.startInclusive,
      previousFull.endExclusive,
    );
    final elapsedDays = _elapsedCalendarDays(current, query.asOf);
    if (elapsedDays == 0) {
      return MetricResult.notApplicable(
        reasons: [
          MetricReason(
            code: MetricReasonCode.windowNotStarted,
            message: 'The current comparison window has not started.',
          ),
        ],
        query: query,
        resolver: resolverName,
      );
    }

    final complete = !query.asOf.isBefore(current.endExclusive);
    late final MetricWindow currentComparable;
    late final MetricWindow previousComparable;
    late final String? qualifier;

    if (complete) {
      currentComparable = current;
      previousComparable = previousFull;
      qualifier = null;
    } else {
      final previousCapacity = kind == ComparisonWindowKind.calendarYear
          ? _previousYearElapsedDays(
              currentWindow: current,
              previousWindow: previousFull,
              asOf: query.asOf,
            )
          : previousDays;
      final comparableDays = _min(elapsedDays, previousCapacity);
      currentComparable = MetricWindow(
        startInclusive: current.startInclusive,
        endExclusive: _addCalendarDays(
          current.startInclusive,
          comparableDays,
        ),
      );
      previousComparable = MetricWindow(
        startInclusive: previousFull.startInclusive,
        endExclusive: _addCalendarDays(
          previousFull.startInclusive,
          comparableDays,
        ),
      );
      qualifier = '前$comparableDays天';
    }

    final value = ComparisonWindowResult(
      mainQuery: query,
      currentComparableQuery: query.copyWith(window: currentComparable),
      previousComparableQuery: query.copyWith(window: previousComparable),
      previousFullWindow: previousFull,
      currentWindowComplete: complete,
      currentComparableDayCount: _calendarDaysBetween(
        currentComparable.startInclusive,
        currentComparable.endExclusive,
      ),
      previousComparableDayCount: _calendarDaysBetween(
        previousComparable.startInclusive,
        previousComparable.endExclusive,
      ),
      qualifier: qualifier,
    );
    return MetricResult.available(
      value: value,
      query: query,
      resolver: resolverName,
    );
  }

  static MetricResult<ComparisonWindowResult> _conflict(
    MetricQuery query,
    String message,
  ) =>
      MetricResult.conflict(
        reasons: [
          MetricReason(
            code: MetricReasonCode.invalidInput,
            message: message,
          ),
        ],
        query: query,
        resolver: resolverName,
      );

  static String? _validateWindowShape(
    MetricWindow window,
    ComparisonWindowKind kind,
    int weekStart,
  ) {
    if (weekStart < DateTime.monday || weekStart > DateTime.sunday) {
      return 'The week start must be a DateTime weekday value from 1 to 7.';
    }
    final start = window.startInclusive;
    final end = window.endExclusive;
    switch (kind) {
      case ComparisonWindowKind.calendarMonth:
        final expectedEnd = _dateLike(start, start.year, start.month + 1, 1);
        if (start.day != 1 || end != expectedEnd) {
          return 'A calendar-month window must cover one complete month.';
        }
        break;
      case ComparisonWindowKind.calendarWeek:
        if (_calendarDaysBetween(start, end) != 7 ||
            start.weekday != weekStart) {
          return 'A calendar-week window must start on the configured weekday '
              'and contain seven calendar days.';
        }
        break;
      case ComparisonWindowKind.calendarYear:
        final expectedEnd = _dateLike(start, start.year + 1, 1, 1);
        if (start.month != 1 || start.day != 1 || end != expectedEnd) {
          return 'A calendar-year window must cover one complete year.';
        }
        break;
      case ComparisonWindowKind.budgetCycle:
      case ComparisonWindowKind.custom:
        break;
    }
    return null;
  }

  static MetricWindow? _previousWindow({
    required MetricWindow current,
    required ComparisonWindowKind kind,
    required MetricWindow? previousBudgetCycle,
  }) {
    final start = current.startInclusive;
    switch (kind) {
      case ComparisonWindowKind.calendarMonth:
        return MetricWindow(
          startInclusive: _dateLike(start, start.year, start.month - 1, 1),
          endExclusive: start,
        );
      case ComparisonWindowKind.calendarWeek:
        return MetricWindow(
          startInclusive: _addCalendarDays(start, -7),
          endExclusive: start,
        );
      case ComparisonWindowKind.calendarYear:
        return MetricWindow(
          startInclusive: _dateLike(start, start.year - 1, 1, 1),
          endExclusive: start,
        );
      case ComparisonWindowKind.custom:
        final dayCount = _calendarDaysBetween(start, current.endExclusive);
        return MetricWindow(
          startInclusive: _addCalendarDays(start, -dayCount),
          endExclusive: start,
        );
      case ComparisonWindowKind.budgetCycle:
        return previousBudgetCycle;
    }
  }

  static int _elapsedCalendarDays(MetricWindow window, DateTime asOf) {
    final start = window.startInclusive;
    final end = window.endExclusive;
    final asOfDay = _startOfCalendarDay(asOf, utc: start.isUtc);
    if (asOfDay.isBefore(start)) return 0;
    if (!asOfDay.isBefore(end)) {
      return _calendarDaysBetween(start, end);
    }
    return _calendarDaysBetween(start, asOfDay) + 1;
  }

  static int _previousYearElapsedDays({
    required MetricWindow currentWindow,
    required MetricWindow previousWindow,
    required DateTime asOf,
  }) {
    final currentLastDay = _addCalendarDays(currentWindow.endExclusive, -1);
    final asOfDay = _startOfCalendarDay(
      asOf.isAfter(currentLastDay) ? currentLastDay : asOf,
      utc: currentWindow.startInclusive.isUtc,
    );
    final previousYear = previousWindow.startInclusive.year;
    final previousMonthLastDay = _daysInMonth(previousYear, asOfDay.month);
    final clippedDay = _min(asOfDay.day, previousMonthLastDay);
    final previousThrough = _dateLike(
      previousWindow.startInclusive,
      previousYear,
      asOfDay.month,
      clippedDay,
    );
    return _calendarDaysBetween(
          previousWindow.startInclusive,
          previousThrough,
        ) +
        1;
  }

  static int _calendarDaysBetween(DateTime start, DateTime end) =>
      DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays;

  static DateTime _addCalendarDays(DateTime date, int days) => date.isUtc
      ? DateTime.utc(date.year, date.month, date.day + days)
      : DateTime(date.year, date.month, date.day + days);

  static DateTime _dateLike(
    DateTime template,
    int year,
    int month,
    int day,
  ) =>
      template.isUtc
          ? DateTime.utc(year, month, day)
          : DateTime(year, month, day);

  static DateTime _startOfCalendarDay(DateTime date, {required bool utc}) => utc
      ? DateTime.utc(date.year, date.month, date.day)
      : DateTime(date.year, date.month, date.day);

  static bool _isCalendarBoundary(DateTime date) =>
      date.hour == 0 &&
      date.minute == 0 &&
      date.second == 0 &&
      date.millisecond == 0 &&
      date.microsecond == 0;

  static int _daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  static int _min(int left, int right) => left < right ? left : right;
}
