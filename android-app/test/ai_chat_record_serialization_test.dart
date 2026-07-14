import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';
import 'package:qingji/core/budget/budget_period.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

/// 记账卡跨重启恢复：编码→解码往返一致，坏数据不崩。
void main() {
  test('记账卡 JSON 往返：entries/cats/txnIds/saved/deleted 全一致', () {
    final entries = [
      ParsedEntry(
        amount: Decimal.parse('23.88'),
        kind: TransactionKind.expense,
        categoryKey: 'snacks',
        note: '烧烤',
        date: DateTime(2026, 7, 4),
        timePrecision: TransactionTimePrecision.exact,
        confidence: 0.95,
      ),
      ParsedEntry(
        amount: null, // 没认出金额的占位条目
        kind: TransactionKind.income,
        categoryKey: null,
        note: '待补金额',
        date: DateTime(2026, 7, 1),
        timePrecision: TransactionTimePrecision.dateOnly,
      ),
    ];
    final json = encodeRecordCard(
      entries: entries,
      catIds: [42, null],
      txnIds: [1001, null],
      saved: true,
      feedback: '记好啦',
      deleted: {1},
    );

    final d = decodeRecordCard(json);
    expect(d.entries, hasLength(2));
    expect(d.entries[0].amount, Decimal.parse('23.88'));
    expect(d.entries[0].kind, TransactionKind.expense);
    expect(d.entries[0].categoryKey, 'snacks');
    expect(d.entries[0].note, '烧烤');
    expect(d.entries[0].date, DateTime(2026, 7, 4));
    expect(d.entries[0].timePrecision, TransactionTimePrecision.exact);
    expect(d.entries[1].amount, isNull);
    expect(d.entries[1].kind, TransactionKind.income);
    expect(d.entries[1].timePrecision, TransactionTimePrecision.dateOnly);
    expect(d.catIds, [42, null]);
    expect(d.txnIds, [1001, null]);
    expect(d.saved, isTrue);
    expect(d.feedback, '记好啦');
    expect(d.deleted, {1});
  });

  test('坏 JSON 抛出（调用方 try/catch 跳过该卡，不崩恢复流程）', () {
    expect(() => decodeRecordCard('{不是合法json'), throwsA(anything));
  });

  test('legacy record card without precision stays unknown', () {
    final decoded = decodeRecordCard('''{
      "saved": true,
      "entries": [{
        "amt": "12",
        "kind": "expense",
        "note": "legacy",
        "date": 1783987200000
      }]
    }''');

    expect(
      decoded.entries.single.timePrecision,
      TransactionTimePrecision.legacyUnknown,
    );
  });

  test('旧退款卡 JSON 恢复后保留关联并回退未知时间精度', () {
    final decoded = decodeRefundCard('''{
      "originalId": 18,
      "refundId": 29,
      "title": "淘宝连衣裙",
      "categoryName": "服饰鞋包",
      "bookName": "总账本",
      "amount": "30",
      "originalAmount": "100",
      "refundedAfter": "30",
      "date": 1783008000000
    }''');

    expect(decoded.originalId, 18);
    expect(decoded.refundId, 29);
    expect(decoded.amount, Decimal.fromInt(30));
    expect(decoded.originalAmount, Decimal.fromInt(100));
    expect(decoded.refundedAfter, Decimal.fromInt(30));
    expect(decoded.title, '淘宝连衣裙');
    expect(
      decoded.timePrecision,
      TransactionTimePrecision.legacyUnknown,
    );
  });

  test('新版退款卡 JSON 恢复日期精度', () {
    final decoded = decodeRefundCard('''{
      "originalId": 18,
      "refundId": 29,
      "title": "淘宝连衣裙",
      "categoryName": "服饰鞋包",
      "bookName": "总账本",
      "amount": "30",
      "originalAmount": "100",
      "refundedAfter": "30",
      "date": 1783008000000,
      "timePrecision": "date_only"
    }''');

    expect(decoded.timePrecision, TransactionTimePrecision.dateOnly);
  });

  test('报告卡 JSON 只保存轻量引用，坏数据返回 null', () {
    const report = ReportEntity(
      id: 88,
      type: 'monthly',
      title: '2026年6月消费月报',
      summary: '摘要',
      markdown: '# 2026年6月消费月报',
      periodStartMs: 1780243200000,
      periodEndMs: 1782748800000,
      createdMs: 1782777600000,
    );

    final json = encodeReportChatMessage(report, '6月餐饮上涨，需要关注。');
    final decoded = decodeReportChatMessage(json);
    expect(decoded, isNotNull);
    expect(decoded!.reportId, 88);
    expect(decoded.summary, '6月餐饮上涨，需要关注。');
    expect(decodeReportChatMessage('{坏json'), isNull);
  });

  test('报告类型与周期按用户问题识别，不默认错用当前月', () {
    final now = DateTime(2026, 7, 6);
    expect(reportTypeOf('帮我生成6月消费月报'), 'monthly');
    expect(reportTypeOf('帮我生成6月的报告。'), 'monthly');
    expect(reportTypeOf('做一份上个月的总结'), 'monthly');
    expect(reportTypeOf('做一份本周周报'), 'weekly');
    expect(reportTypeOf('今年消费年报'), 'yearly');
    expect(reportTypeOf('年度消费报告'), 'yearly');
    expect(reportTypeOf('2025年消费报告'), 'yearly');
    expect(reportTypeOf('2025年6月消费月报'), 'monthly');
    expect(reportTypeOf('这个月花了多少'), isNull);

    final period = reportPeriodOf(
      'monthly',
      now,
      question: '帮我生成6月的报告。',
    );
    expect(period.start, DateTime(2026, 6, 1));
    expect(period.end, DateTime(2026, 6, 30));
    expect(reportTitleOf('monthly', period), '2026年6月消费月报');

    final yearly = reportPeriodOf(
      'yearly',
      now,
      question: '帮我生成2025年消费报告',
    );
    expect(yearly.start, DateTime(2025, 1, 1));
    expect(yearly.end, DateTime(2025, 12, 31));
    expect(reportTitleOf('yearly', yearly), '2025年消费年报');
  });

  test('报告摘要跳过 Markdown 标题，只保留正文判断', () {
    final markdown = reportMarkdown(
      '2026年6月消费月报',
      '## 摘要\n\n**6月总支出** ¥5,749.15，餐饮上涨，需要关注。\n\n## 建议\n- 餐饮预算设为 ¥1,100',
    );

    final summary = reportSummary(markdown);
    expect(summary, startsWith('6月总支出 ¥5,749.15'));
    expect(summary, isNot(contains('2026年6月消费月报')));
    expect(summary, isNot(contains('摘要')));
  });

  test('报告文档只在 AI 成功回答后创建', () {
    expect(
      shouldCreateReportDocument(reportType: 'monthly', aiAnswered: true),
      isTrue,
    );
    expect(
      shouldCreateReportDocument(reportType: 'monthly', aiAnswered: false),
      isFalse,
    );
    expect(
      shouldCreateReportDocument(reportType: null, aiAnswered: true),
      isFalse,
    );
  });

  test('AI 历史预算上下文不会混入当前周期的今日指标', () {
    final asOf = DateTime(2026, 7, 13, 12);
    final plan = BudgetPeriod(
      id: 1,
      bookId: 1,
      start: DateTime(2026, 1, 1),
      total: Decimal.fromInt(3100),
    );
    BudgetWindowResult resolve(DateTime month) => BudgetWindowResolver.resolve(
          query: BudgetWindowQuery(
            viewKind: BudgetViewKind.calendarMonth,
            bookId: 1,
            referenceDate: month,
            asOf: asOf,
            knowledgeCutoff: asOf,
          ),
          periods: [plan],
        );

    final historical = resolve(DateTime(2026, 6));
    final current = resolve(DateTime(2026, 7));

    expect(historical.currentCycleDailyStatus, isNotNull);
    expect(
      formatBudgetContextForAi(historical),
      isNot(contains('按预算平均今日可用')),
    );
    expect(
      formatBudgetContextForAi(current),
      contains('按预算平均今日可用'),
    );
  });
}
