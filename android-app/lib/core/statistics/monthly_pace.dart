import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../app_clock.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';
import '../money_format.dart';

/// 「同期平均」至少要几个历史月（用户 2026-09-30 定：2 个月）。
/// 统计页进度卡和桌面小组件都用这个数，两边不能各写各的（07 案例 63、74）。
const int kPaceMinSamples = 2;

/// 「基本持平」的上下界：和平均差不超过 8%。
const double kPaceFlatBand = 0.08;

class MonthlyPaceSample {
  final String label;

  /// 该月整月净支出（只算正额）。
  final Decimal full;

  /// 截到同一天（今天几号，短月裁到月末）的净支出。
  final Decimal pace;
  final bool current;

  /// 这个月在「开始记账」之后。之前的月是缺数据，不进平均；
  /// 之后的月哪怕一分没花（真实 0）也要进平均的分母。
  final bool tracked;

  const MonthlyPaceSample({
    required this.label,
    required this.full,
    required this.pace,
    required this.current,
    this.tracked = true,
  });
}

/// Computes the six historical pace bars and the current-month bar in one
/// pass over [records]. Keeping this pure makes the expensive path measurable
/// without involving Flutter layout or chart painting. 统计页进度卡和桌面小组件
/// 快照共用它（07 案例 74）。
///
/// [records] 用记账仓库的 user records（退款已折回原单）。非正额（全额退款的原单、
/// 老数据的负数冲账）不计入。
List<MonthlyPaceSample> computeMonthlyPaceSamples({
  required List<TransactionRecord> records,
  required int year,
  required int month,
  required bool isCurrentMonth,
  DateTime? now,
}) {
  final currentMonth = DateTime(year, month);
  final today = now ?? AppClock.now;
  final lastDay = DateTime(year, month + 1, 0).day;
  final cutoffDay = isCurrentMonth ? math.min(today.day, lastDay) : lastDay;
  final months = <DateTime>[
    for (var offset = 6; offset >= 1; offset--) DateTime(year, month - offset),
    currentMonth,
  ];
  final monthKeys = <int>{
    for (final value in months) value.year * 100 + value.month,
  };
  final cutoffs = <int, int>{
    for (final value in months)
      value.year * 100 + value.month: value == currentMonth
          ? cutoffDay
          : math.min(
              cutoffDay,
              DateTime(value.year, value.month + 1, 0).day,
            ),
  };
  final fullByMonth = <int, Decimal>{};
  final paceByMonth = <int, Decimal>{};
  int? firstKey;
  for (final record in records) {
    final key = record.date.year * 100 + record.date.month;
    // 开始记账的月份：看任何一条记录（收入、转账也算在用）。
    if (firstKey == null || key < firstKey) firstKey = key;
    if (record.kind != TransactionKind.expense) continue;
    if (record.amount <= Decimal.zero) continue;
    if (!monthKeys.contains(key)) continue;
    fullByMonth[key] = (fullByMonth[key] ?? Decimal.zero) + record.amount;
    if (record.date.day <= cutoffs[key]!) {
      paceByMonth[key] = (paceByMonth[key] ?? Decimal.zero) + record.amount;
    }
  }

  final samples = <MonthlyPaceSample>[];
  for (final value in months.take(6)) {
    final key = value.year * 100 + value.month;
    samples.add(
      MonthlyPaceSample(
        label: '${value.month}月',
        full: fullByMonth[key] ?? Decimal.zero,
        pace: paceByMonth[key] ?? Decimal.zero,
        current: false,
        tracked: firstKey != null && key >= firstKey,
      ),
    );
  }
  final currentKey = year * 100 + month;
  final current = paceByMonth[currentKey] ?? Decimal.zero;
  samples.add(
    MonthlyPaceSample(
      label: '$month月',
      full: current,
      pace: current,
      current: true,
    ),
  );
  return List.unmodifiable(samples);
}

/// 同期平均：只排除「开始记账之前」的月，真实花了 0 的月照样进分母。
/// 可用样本少于 [kPaceMinSamples] 时返回 null（界面显示「--」）。
({Decimal average, int sampleCount})? monthlyPaceAverage(
  List<MonthlyPaceSample> samples,
) {
  final comparable =
      samples.where((s) => !s.current && s.tracked).map((s) => s.pace).toList();
  if (comparable.length < kPaceMinSamples) return null;
  final average = (comparable.fold(Decimal.zero, (a, b) => a + b) /
          Decimal.fromInt(comparable.length))
      .toDecimal(scaleOnInfinitePrecision: 2);
  return (average: average, sampleCount: comparable.length);
}

/// 偏高 / 基本持平 / 偏低。平均是 0 时：本期也是 0 算持平，否则偏高。
String monthlyPaceRelation(Decimal current, Decimal average) {
  final cur = MoneyFormat.toDouble(current);
  final avg = MoneyFormat.toDouble(average);
  if (avg <= 0) return cur <= 0 ? '基本持平' : '偏高';
  final delta = (cur - avg) / avg;
  if (delta.abs() <= kPaceFlatBand) return '基本持平';
  return delta > 0 ? '偏高' : '偏低';
}
