import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/delta_badge_text.dart';
import 'package:qingji/core/statistics/monthly_pace.dart';
import 'package:qingji/core/statistics/spending_insights.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';

DateTime _d(int y, int m, int day) => DateTime(y, m, day, 12);
Decimal _n(num v) => Decimal.parse(v.toString());

TransactionRecord _rec({
  TransactionKind kind = TransactionKind.expense,
  required num amount,
  String categoryName = '',
  required DateTime date,
}) =>
    TransactionRecord.create(
      kind: kind,
      amount: _n(amount),
      categoryName: categoryName,
      accountName: '',
      toAccountName: '',
      date: date,
    );

void main() {
  group('07 §14 涨跌徽章文案', () {
    test('上期 0、本期为正显示「新增」，不显示无穷百分比', () {
      final d = deltaBadgeText(current: _n(46), previous: Decimal.zero)!;
      expect(d.text, '新增 ¥46');
      expect(d.up, isTrue);
    });

    test('两期都是 0 不显示', () {
      expect(deltaBadgeText(current: Decimal.zero, previous: Decimal.zero),
          isNull);
    });

    test('结余跨零显示金额差，不显示失真的百分比', () {
      final d = deltaBadgeText(current: _n(574), previous: _n(-243))!;
      expect(d.text, '↑ ¥817');
      expect(d.up, isTrue);
      final down = deltaBadgeText(current: _n(-50), previous: _n(100))!;
      expect(down.text, '↓ ¥150');
      expect(down.up, isFalse);
    });

    test('普通情况仍是百分比，小于 0.05% 不显示', () {
      expect(deltaBadgeText(current: _n(150), previous: _n(100))!.text,
          '↑ 50%');
      expect(deltaBadgeText(current: _n(95), previous: _n(100))!.text,
          '↓ 5.0%');
      expect(deltaBadgeText(current: _n(100.01), previous: _n(100)), isNull);
    });
  });

  group('07 §14 洞察和对比卡与顶部徽章同一窗口', () {
    // 上月（5 月）后半月花了很多；本月今天是 6/10。
    final records = [
      _rec(amount: 100, categoryName: '餐饮', date: _d(2026, 5, 5)),
      _rec(amount: 900, categoryName: '餐饮', date: _d(2026, 5, 25)),
      _rec(amount: 60, categoryName: '交通', date: _d(2026, 5, 6)),
      _rec(amount: 200, categoryName: '餐饮', date: _d(2026, 6, 3)),
    ];
    final now = DateTime(2026, 6, 10, 9);

    test('当月比上月前 10 天，不拿上月整月', () {
      final w = SpendingInsights.comparableMonthWindows(records,
          year: 2026, month: 6, now: now);
      expect(w.sameProgress, isTrue);
      expect(w.current.totalExpense, _n(200));
      expect(w.previous.totalExpense, _n(160)); // 100 + 60，不含 5/25 的 900
      final lines = SpendingInsights.summaryLines(records,
          year: 2026, month: 6, now: now);
      // 旧算法：200 对 1060 → 「省了 81%」。现在：200 对 160 → 多了 25%。
      expect(lines.join(), contains('本月总支出比上月同期多了 25%'));
      expect(lines.join(), isNot(contains('省了')));
    });

    test('过去的月份整月对整月，不写「本月」', () {
      final w = SpendingInsights.comparableMonthWindows(records,
          year: 2026, month: 6, now: DateTime(2026, 8, 1));
      expect(w.sameProgress, isFalse);
      expect(w.previous.totalExpense, _n(1060));
      final lines = SpendingInsights.summaryLines(records,
          year: 2026, month: 6, now: DateTime(2026, 8, 1));
      expect(lines.join(), isNot(contains('本月')));
      expect(lines.join(), contains('6月总支出比上月省了'));
    });

    test('上月花过、本期没花的分类也进对比卡（D-STAT-008）', () {
      final w = SpendingInsights.comparableMonthWindows(records,
          year: 2026, month: 6, now: now);
      final rows = compareCategoryRows(
          w.current.expenseByCategory, w.previous.expenseByCategory);
      expect(rows.map((r) => r.name), ['餐饮', '交通']);
      expect(rows.last.cur, 0);
      expect(rows.last.prev, 60);
    });
  });

  group('07 D-STAT-010 / 案例 63 同期平均', () {
    // 今天 7/15。5 月开始记账：5 月花 100、6 月一分没花（真实 0）。
    final base = [
      _rec(amount: 100, date: _d(2026, 5, 3)),
      _rec(kind: TransactionKind.income, amount: 50, date: _d(2026, 6, 20)),
      _rec(amount: 30, date: _d(2026, 7, 2)),
    ];

    test('开始记账前的月不算，真实 0 月算进分母', () {
      final samples = computeMonthlyPaceSamples(
        records: base,
        year: 2026,
        month: 7,
        isCurrentMonth: true,
        now: DateTime(2026, 7, 15),
      );
      final r = monthlyPaceAverage(samples)!;
      expect(r.sampleCount, 2); // 5 月 + 6 月；1~4 月是记账前
      expect(r.average, _n(50)); // (100 + 0) / 2
      expect(monthlyPaceRelation(samples.last.pace, r.average), '偏低');
    });

    test('只有 1 个历史月时不给平均（页面和小组件同一门槛）', () {
      final samples = computeMonthlyPaceSamples(
        records: [
          _rec(amount: 100, date: _d(2026, 6, 3)),
          _rec(amount: 30, date: _d(2026, 7, 2)),
        ],
        year: 2026,
        month: 7,
        isCurrentMonth: true,
        now: DateTime(2026, 7, 15),
      );
      expect(kPaceMinSamples, 2);
      expect(monthlyPaceAverage(samples), isNull);
    });

    test('全额退款的原单和老数据负数冲账不计入', () {
      final samples = computeMonthlyPaceSamples(
        records: [
          _rec(amount: 100, date: _d(2026, 5, 3)),
          _rec(amount: 0, date: _d(2026, 6, 3)),
          _rec(amount: -40, date: _d(2026, 6, 4)),
          _rec(amount: 20, date: _d(2026, 7, 2)),
        ],
        year: 2026,
        month: 7,
        isCurrentMonth: true,
        now: DateTime(2026, 7, 15),
      );
      final june = samples.firstWhere((s) => s.label == '6月');
      expect(june.pace, Decimal.zero);
      expect(june.tracked, isTrue);
    });

    test('平均是 0：本期也是 0 算持平，本期有支出算偏高', () {
      expect(monthlyPaceRelation(Decimal.zero, Decimal.zero), '基本持平');
      expect(monthlyPaceRelation(_n(10), Decimal.zero), '偏高');
      expect(monthlyPaceRelation(_n(108), _n(100)), '基本持平');
      expect(monthlyPaceRelation(_n(109), _n(100)), '偏高');
    });
  });

  test('月度汇总仍按整月补零（未来日留空由图表层处理）', () {
    final s = StatisticsEngine.monthlySummary([], year: 2026, month: 6);
    expect(s.dailyTotals.length, 30);
  });
}
