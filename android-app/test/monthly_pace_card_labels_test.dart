// 本月进度卡 X 轴月份标签口径。
//
// 回归背景：标签曾写成 '${7 - offset}'（柱子序号 1..6），而当月那根用真实
// 月份 '$month月'，X 轴就变成「1 2 3 4 5 6 8月」——前六个是序号、最后一个
// 是月份，两种口径混在一条轴上，用户会以为上个月的数据丢了。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/widgets/monthly_pace_card.dart';

/// 每个月都放一笔支出，保证 7 根柱子都有数（有数才算得出「平均」线）。
List<TransactionRecord> _recordsAround(DateTime anchor) => [
      for (var offset = 6; offset >= 0; offset--)
        TransactionRecord(
          id: 'expense-$offset',
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(200 + offset * 35),
          categoryName: '食品',
          date: DateTime(anchor.year, anchor.month - offset, 3),
        ),
    ];

Future<void> _pumpCard(WidgetTester tester, DateTime anchor) async {
  final records = _recordsAround(anchor);
  final summary = StatisticsEngine.monthlySummary(
    records,
    year: anchor.year,
    month: anchor.month,
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MonthlyPaceCard(
          records: records,
          summary: summary,
          year: anchor.year,
          month: anchor.month,
          isCurrentMonth: false,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('X 轴标注真实月份，上个月不会从轴上消失', (tester) async {
    // 8 月视角：前六根柱子应是 2..7 月，最后一根是「8月」。
    await _pumpCard(tester, DateTime(2026, 8));

    for (final month in [2, 3, 4, 5, 6, 7]) {
      expect(
        find.text('$month'),
        findsOneWidget,
        reason: '$month 月应该在 X 轴上（7 月曾因序号标签而看起来丢失）',
      );
    }
    expect(find.text('8月'), findsOneWidget, reason: '当月标签带「月」字以区分');

    // 旧实现的序号标签是 1..6：'1' 在正确实现里不该出现
    // （8 月往前推六个月是 2..7 月，不含 1 月）。
    expect(
      find.text('1'),
      findsNothing,
      reason: '不该再出现柱子序号标签',
    );
  });

  testWidgets('跨年时回退到上一年的月份', (tester) async {
    // 2 月视角：前六根应是上年 8..12 月 + 本年 1 月。
    await _pumpCard(tester, DateTime(2026, 2));

    for (final month in [8, 9, 10, 11, 12, 1]) {
      expect(
        find.text('$month'),
        findsOneWidget,
        reason: '跨年月份 $month 应正确显示（DateTime 归一负数月份）',
      );
    }
    expect(find.text('2月'), findsOneWidget);
  });
}
