import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';
import '../transaction_time.dart';

enum SmartSuggestionKind { record, query }

class SmartSuggestion {
  final SmartSuggestionKind kind;
  final String text;
  final int evidenceScore;

  const SmartSuggestion({
    required this.kind,
    required this.text,
    required this.evidenceScore,
  });
}

/// Builds assistant shortcuts only when the local ledger contains enough
/// evidence. Results are deterministic: weak evidence produces fewer chips
/// instead of random filler.
class SmartSuggestionEngine {
  SmartSuggestionEngine._();

  static const int _recordThreshold = 52;
  static const int _maxRecordSuggestions = 2;
  static const int _recordLookbackDays = 180;

  /// Lightweight cache key for every field that can change a suggestion.
  /// Unlike transaction count, this also changes after editing an existing
  /// amount, date, category or note.
  static int contentFingerprint({
    required Iterable<TransactionRecord> records,
    required bool hasActiveBudget,
  }) {
    final ordered = records.toList(growable: false)
      ..sort((left, right) {
        final byId = left.id.compareTo(right.id);
        return byId != 0 ? byId : left.date.compareTo(right.date);
      });
    return Object.hash(
      hasActiveBudget,
      Object.hashAll([
        for (final record in ordered)
          Object.hash(
            record.id,
            record.kind,
            record.amount.toString(),
            record.currencyCode,
            record.categoryKey,
            record.categoryName,
            record.topCategoryKey,
            record.topCategoryName,
            record.note,
            record.date.millisecondsSinceEpoch,
            record.timePrecision,
          ),
      ]),
    );
  }

  static List<SmartSuggestion> build({
    required Iterable<TransactionRecord> records,
    required DateTime now,
    bool hasActiveBudget = false,
    int limit = 4,
  }) {
    if (limit <= 0) return const [];

    final today = _dayOnly(now);
    final usable = records
        .where((record) => !record.date.isAfter(now))
        .where((record) => record.amount > Decimal.zero)
        .toList(growable: false);

    final recordSuggestions = _recordSuggestions(usable, now, today);
    final querySuggestions = _querySuggestions(
      usable,
      now,
      hasActiveBudget: hasActiveBudget,
    );

    return <SmartSuggestion>[
      ...recordSuggestions.take(math.min(_maxRecordSuggestions, limit)),
      ...querySuggestions,
    ].take(limit).toList(growable: false);
  }

  static List<SmartSuggestion> _recordSuggestions(
    List<TransactionRecord> records,
    DateTime now,
    DateTime today,
  ) {
    final groups = <String, List<_SignatureOccurrence>>{};
    final windowStart =
        today.subtract(const Duration(days: _recordLookbackDays - 1));
    for (final record in records) {
      if (record.kind != TransactionKind.expense) continue;
      if (_dayOnly(record.date).isBefore(windowStart)) continue;
      if (!_isLeafCategory(record)) continue;

      final descriptor = _cleanDescriptor(
        record.note,
        categoryName: record.categoryName,
      );
      if (descriptor == null) continue;

      final signature = '${record.currencyCode.toUpperCase()}|'
          '${record.categoryKey}|${descriptor.key}';
      (groups[signature] ??= <_SignatureOccurrence>[]).add(
        _SignatureOccurrence(
          record: record,
          label: descriptor.label,
          cents: _toCents(record.amount),
        ),
      );
    }

    final candidates = <_RecordCandidate>[];
    for (final occurrences in groups.values) {
      occurrences.sort((left, right) {
        final byDate = left.record.date.compareTo(right.record.date);
        return byDate != 0 ? byDate : left.record.id.compareTo(right.record.id);
      });

      final byDay = <DateTime, _SignatureOccurrence>{};
      for (final occurrence in occurrences) {
        byDay[_dayOnly(occurrence.record.date)] = occurrence;
      }
      final distinct = byDay.values.toList(growable: false)
        ..sort((left, right) => left.record.date.compareTo(right.record.date));
      if (distinct.length < 3) continue;

      final latestDay = _dayOnly(distinct.last.record.date);
      if (latestDay == today) continue;
      final daysSinceLatest = today.difference(latestDay).inDays;
      if (daysSinceLatest < 0 || daysSinceLatest > 60) continue;

      final score = _recordScore(
        distinct,
        now: now,
        daysSinceLatest: daysSinceLatest,
      );
      if (score < _recordThreshold) continue;

      final stableCents = _stableAmountCents(
        distinct.map((occurrence) => occurrence.cents).whereType<int>(),
      );
      final label = _ellipsize(distinct.last.label, 12);
      final amountSuffix =
          stableCents == null ? '' : ' ${_formatCents(stableCents)}';
      candidates.add(
        _RecordCandidate(
          suggestion: SmartSuggestion(
            kind: SmartSuggestionKind.record,
            text: '记一笔 $label$amountSuffix',
            evidenceScore: score,
          ),
          latest: distinct.last.record.date,
          stableAmount: stableCents != null,
        ),
      );
    }

    candidates.sort((left, right) {
      final byScore = right.suggestion.evidenceScore
          .compareTo(left.suggestion.evidenceScore);
      if (byScore != 0) return byScore;
      final byAmount =
          (right.stableAmount ? 1 : 0).compareTo(left.stableAmount ? 1 : 0);
      if (byAmount != 0) return byAmount;
      final byLatest = right.latest.compareTo(left.latest);
      if (byLatest != 0) return byLatest;
      return left.suggestion.text.compareTo(right.suggestion.text);
    });
    return candidates
        .map((candidate) => candidate.suggestion)
        .toList(growable: false);
  }

  static int _recordScore(
    List<_SignatureOccurrence> occurrences, {
    required DateTime now,
    required int daysSinceLatest,
  }) {
    final count = occurrences.length;
    var score = math.min(38, 14 + count * 4);

    score += switch (daysSinceLatest) {
      <= 2 => 18,
      <= 7 => 14,
      <= 21 => 10,
      <= 45 => 6,
      _ => 2,
    };

    final timed = occurrences
        .where((occurrence) =>
            _timeEvidenceWeight(occurrence.record.timePrecision) > 0)
        .toList(growable: false);
    if (timed.length >= 3) {
      final totalWeight = timed.fold<double>(
        0,
        (sum, occurrence) =>
            sum + _timeEvidenceWeight(occurrence.record.timePrecision),
      );
      final nearCurrentHour = timed
          .where((occurrence) =>
              _circularHourDistance(occurrence.record.date.hour, now.hour) <= 2)
          .toList(growable: false);
      final nearWeight = nearCurrentHour.fold<double>(
        0,
        (sum, occurrence) =>
            sum + _timeEvidenceWeight(occurrence.record.timePrecision),
      );
      final ratio = totalWeight == 0 ? 0.0 : nearWeight / totalWeight;
      if (nearCurrentHour.length >= 2 && nearWeight >= 1.0 && ratio >= 0.45) {
        final reliability = totalWeight / timed.length;
        score += ((14 + ratio * 6) * reliability).round();
      }
    }

    final sameWeekday = occurrences
        .where((occurrence) => occurrence.record.date.weekday == now.weekday)
        .length;
    final weekdayRatio = sameWeekday / count;
    if (sameWeekday >= 2 && weekdayRatio >= 0.34) {
      score += 10 + (weekdayRatio * 6).round();
    }

    final days = occurrences
        .map((occurrence) => _dayOnly(occurrence.record.date))
        .toList(growable: false);
    final gaps = <int>[
      for (var index = 1; index < days.length; index++)
        days[index].difference(days[index - 1]).inDays,
    ]..removeWhere((gap) => gap <= 0);
    if (gaps.isNotEmpty) {
      gaps.sort();
      final medianGap = gaps[gaps.length ~/ 2];
      final tolerance = math.max(1, (medianGap * 0.3).round());
      if ((daysSinceLatest - medianGap).abs() <= tolerance) {
        score += medianGap <= 2 ? 12 : 20;
      }
    }

    final recentStart = _dayOnly(now).subtract(const Duration(days: 29));
    final recentCount = occurrences
        .where((occurrence) =>
            !_dayOnly(occurrence.record.date).isBefore(recentStart))
        .length;
    if (recentCount >= 4) score += 6;
    return score;
  }

  static List<SmartSuggestion> _querySuggestions(
    List<TransactionRecord> records,
    DateTime now, {
    required bool hasActiveBudget,
  }) {
    final today = _dayOnly(now);
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final previousMonthStart = DateTime(now.year, now.month - 1);
    final lastMonthDayCount = DateTime(now.year, now.month, 0).day;
    final comparableDay = math.min(now.day, lastMonthDayCount);
    final previousSameDayEnd = DateTime(
        previousMonthStart.year, previousMonthStart.month, comparableDay + 1);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    bool inRange(TransactionRecord record, DateTime start, DateTime end) =>
        !record.date.isBefore(start) && record.date.isBefore(end);

    final expenses = records
        .where((record) => record.kind == TransactionKind.expense)
        .toList(growable: false);
    final incomes = records
        .where((record) => record.kind == TransactionKind.income)
        .toList(growable: false);
    final monthExpenses = expenses
        .where((record) => inRange(record, monthStart, nextMonth))
        .toList(growable: false);
    final monthIncomes = incomes
        .where((record) => inRange(record, monthStart, nextMonth))
        .toList(growable: false);
    final previousComparableExpenses = expenses
        .where(
            (record) => inRange(record, previousMonthStart, previousSameDayEnd))
        .toList(growable: false);
    final todayExpenses = expenses
        .where((record) => _dayOnly(record.date) == today)
        .toList(growable: false);
    final weekDining = expenses.where((record) {
      if (!inRange(record, weekStart, today.add(const Duration(days: 1)))) {
        return false;
      }
      return record.topCategoryKey == 'dining' ||
          record.topCategoryName.contains('餐饮') ||
          record.topCategoryName.contains('食品');
    }).toList(growable: false);

    final candidates = <SmartSuggestion>[];
    void add(String text, int score) => candidates.add(
          SmartSuggestion(
            kind: SmartSuggestionKind.query,
            text: text,
            evidenceScore: score,
          ),
        );

    if (hasActiveBudget) add('本月预算还剩多少', 100);
    if (monthExpenses.length >= 3 && previousComparableExpenses.length >= 3) {
      add('本月比上月同期多吗', 94);
    }
    if (monthExpenses.length >= 2 && monthIncomes.isNotEmpty) {
      add('本月收支结余多少', 90);
    }
    if (_distinctDayCount(weekDining) >= 2) {
      add('这周吃饭花了多少', 86);
    }

    final topCategoryKeys = monthExpenses
        .map((record) => record.topCategoryKey.trim().isEmpty
            ? record.categoryKey.trim()
            : record.topCategoryKey.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    if (monthExpenses.length >= 5 &&
        monthExpenses.length <= 200 &&
        topCategoryKeys.length >= 2) {
      add('这个月哪类花最多', 82);
    }

    final hasRicherMonthQuestion =
        monthIncomes.isNotEmpty || previousComparableExpenses.length >= 3;
    if (monthExpenses.length >= 3 && !hasRicherMonthQuestion) {
      add('这个月花了多少', 74);
    }
    if (todayExpenses.length >= 2) add('今天花了多少', 68);

    candidates.sort((left, right) {
      final byScore = right.evidenceScore.compareTo(left.evidenceScore);
      return byScore != 0 ? byScore : left.text.compareTo(right.text);
    });
    return candidates;
  }

  static bool _isLeafCategory(TransactionRecord record) {
    final category = record.categoryKey.trim();
    final top = record.topCategoryKey.trim();
    return category.isNotEmpty && top.isNotEmpty && category != top;
  }

  static _Descriptor? _cleanDescriptor(
    String raw, {
    required String categoryName,
  }) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    value = value.replaceAll(
      RegExp(r'^(?:请\s*)?(?:帮我\s*)?(?:记一笔|记账|记录一下|记录|新增一笔)\s*'),
      '',
    );
    value = value.replaceAll(
      RegExp(r'^(?:今天|昨天|前天|刚刚|刚才|今早|今晚|中午|早上|上午|下午|晚上)\s*'),
      '',
    );
    value = value.replaceAll(
      RegExp(r'(?:订单\s*(?:编号|号)?|交易号)\s*[-:：]?\s*[A-Za-z0-9]+'),
      '',
    );
    value = value.replaceAll(RegExp(r'[A-Za-z]*\d{6,}[A-Za-z0-9]*'), '');
    value = value.replaceAll(RegExp(r'[¥￥]\s*\d+(?:\.\d+)?'), '');
    value = value.replaceAll(
      RegExp(
        r'\d+(?:\.\d+)?\s*(?:人民币|元|块钱?|块|rmb|cny)',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(
      RegExp(r'[零〇一二两三四五六七八九十百千万]+\s*(?:元|块钱?|块)'),
      '',
    );
    value =
        value.replaceAll(RegExp(r'(?<![A-Za-z])\d+(?:\.\d+)?(?![A-Za-z])'), '');
    value = value.replaceAll(RegExp(r'(?:花了|花费|消费|付款|支付)$'), '');
    value = value.replaceAll(RegExp(r'[\s·•,，。.!！?？;；:：/\\|_—-]+'), ' ');
    value = value.trim();
    if (value.length < 2) return null;

    final key = _comparisonKey(value);
    final categoryKey = _comparisonKey(categoryName);
    if (key.isEmpty || key == categoryKey) return null;
    if (_genericDescriptors.contains(key)) return null;
    return _Descriptor(key: key, label: value);
  }

  static const Set<String> _genericDescriptors = {
    '消费',
    '支出',
    '付款',
    '扫码付款',
    '扫码支付',
    '微信支付',
    '支付宝',
    '交易',
    '记账',
    '其他',
    '未分类',
    '公交',
    '地铁',
    '公共交通',
    '食品',
    '餐饮',
    '食品餐饮',
    '吃饭',
  };

  static String _comparisonKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s·•,，。.!！?？;；:：/\\|_—-]+'), '');

  static int? _stableAmountCents(Iterable<int> rawCents) {
    final cents = rawCents.where((value) => value > 0).toList()..sort();
    if (cents.length < 3) return null;
    final middle = cents.length ~/ 2;
    final median = cents.length.isOdd
        ? cents[middle]
        : ((cents[middle - 1] + cents[middle]) / 2).round();
    final tolerance = math.max(50, (median * 0.08).round());
    final within =
        cents.where((value) => (value - median).abs() <= tolerance).length;
    final required =
        cents.length <= 3 ? cents.length : (cents.length * 0.75).ceil();
    return within >= required ? median : null;
  }

  static int? _toCents(Decimal amount) {
    var raw = amount.toString();
    if (raw.startsWith('-')) raw = raw.substring(1);
    final parts = raw.split('.');
    final fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > 2 &&
        fraction.substring(2).split('').any((digit) => digit != '0')) {
      return null;
    }
    final whole = int.tryParse(parts.first);
    final minor = int.tryParse(fraction.padRight(2, '0').substring(0, 2));
    if (whole == null || minor == null) return null;
    return whole * 100 + minor;
  }

  static String _formatCents(int cents) {
    final whole = cents ~/ 100;
    final minor = cents % 100;
    if (minor == 0) return '$whole';
    if (minor % 10 == 0) return '$whole.${minor ~/ 10}';
    return '$whole.${minor.toString().padLeft(2, '0')}';
  }

  static int _distinctDayCount(Iterable<TransactionRecord> records) =>
      records.map((record) => _dayOnly(record.date)).toSet().length;

  static double _timeEvidenceWeight(TransactionTimePrecision precision) =>
      switch (precision) {
        TransactionTimePrecision.exact => 1,
        TransactionTimePrecision.entryClock => 0.5,
        TransactionTimePrecision.dateOnly ||
        TransactionTimePrecision.legacyUnknown =>
          0,
      };

  static int _circularHourDistance(int left, int right) {
    final direct = (left - right).abs();
    return math.min(direct, 24 - direct);
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _ellipsize(String value, int maxRunes) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= maxRunes) return value;
    return '${String.fromCharCodes(runes.take(maxRunes))}…';
  }
}

class _SignatureOccurrence {
  final TransactionRecord record;
  final String label;
  final int? cents;

  const _SignatureOccurrence({
    required this.record,
    required this.label,
    required this.cents,
  });
}

class _RecordCandidate {
  final SmartSuggestion suggestion;
  final DateTime latest;
  final bool stableAmount;

  const _RecordCandidate({
    required this.suggestion,
    required this.latest,
    required this.stableAmount,
  });
}

class _Descriptor {
  final String key;
  final String label;

  const _Descriptor({required this.key, required this.label});
}
