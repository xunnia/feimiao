import 'package:decimal/decimal.dart';

import '../../data/app_repository.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';
import '../money_format.dart';
import '../statistics/statistics_engine.dart';
import 'ai_provider_config.dart';
import 'llm_query.dart';
import 'report_document.dart';

typedef ReportStageCallback = Future<void> Function(String stage);

class ReportGenerationService {
  ReportGenerationService._();

  static Future<ReportEntity> generate(
    AppRepository repo,
    ReportJobEntity job, {
    ReportStageCallback? onStage,
  }) async {
    final config = repo.aiProviderConfigFor(AiTaskType.report);
    if (!config.hasKey) {
      await repo.updateReportJob(
        job.id,
        status: 'failed',
        error: '未配置报告 AI API Key',
      );
      throw StateError('report AI API key is missing');
    }

    Future<void> stage(String value, {String? status}) async {
      await repo.updateReportJob(job.id, status: status, stage: value);
      await onStage?.call(value);
    }

    await stage('collect', status: 'running');
    final data = _ReportData(repo, job);
    final context = data.buildContext();
    await stage('generate');

    String answer;
    LlmQueryException? firstError;
    try {
      answer = await LlmQuery.askReport(
        reportTitle: job.title,
        reportType: job.type,
        config: config,
        transactionsText: context,
      );
    } on LlmQueryException catch (error) {
      firstError = error;
      await stage('fallback');
      try {
        answer = await LlmQuery.ask(
          question: '请生成一份完整 Markdown 报告：${job.title}。'
              '不要写聊天式寒暄，正文包含摘要、核心指标、分类分析、重点关注和行动建议。',
          config: config,
          transactionsText: context,
        );
      } on LlmQueryException catch (fallbackError) {
        answer = data.buildLocalFallback(
          '${firstError.message}; ${fallbackError.message}',
        );
      }
    }

    await stage('save');
    final markdown = ReportDocumentFormatter.markdown(job.title, answer);
    final summary = ReportDocumentFormatter.summary(markdown);
    return repo.completeReportJob(
      jobId: job.id,
      summary: summary,
      markdown: markdown,
    );
  }
}

class _ReportData {
  final AppRepository repo;
  final ReportJobEntity job;
  late final DateTime start = DateTime(
    job.periodStart.year,
    job.periodStart.month,
    job.periodStart.day,
  );
  late final DateTime endInclusive = DateTime(
    job.periodEnd.year,
    job.periodEnd.month,
    job.periodEnd.day,
  );
  late final DateTime endExclusive = endInclusive.add(const Duration(days: 1));
  late final int days = endExclusive.difference(start).inDays.clamp(1, 366);
  late final DateTime previousStart = start.subtract(Duration(days: days));
  late final DateTime previousEnd = start;
  late final int reportBookId =
      job.bookId ?? repo.currentBook?.id ?? repo.books.first.id;
  late final List<TransactionEntity> visible =
      repo.visibleTransactionsForBookView(reportBookId);
  late final List<TransactionRecord> records =
      repo.recordsForBookView(reportBookId);
  late final List<TransactionEntity> current = visible
      .where((transaction) => _inRange(transaction, start, endExclusive))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  late final List<TransactionEntity> previous = visible
      .where((transaction) => _inRange(transaction, previousStart, previousEnd))
      .toList(growable: false);
  late final RangeSummary categorySummary = StatisticsEngine.rangeSummary(
    records,
    start: start,
    end: endInclusive,
  );
  late final _Totals currentTotals = _summarize(current);
  late final _Totals previousTotals = _summarize(previous);

  _ReportData(this.repo, this.job);

  bool _inRange(TransactionEntity transaction, DateTime from, DateTime to) =>
      !transaction.excluded &&
      !transaction.date.isBefore(from) &&
      transaction.date.isBefore(to);

  Decimal _netOf(TransactionEntity transaction) =>
      repo.netAmountAcrossBooks(transaction);

  _Totals _summarize(Iterable<TransactionEntity> rows) {
    var expense = Decimal.zero;
    var income = Decimal.zero;
    var expenseCount = 0;
    var incomeCount = 0;
    for (final transaction in rows) {
      if (transaction.txKind == TransactionKind.expense) {
        final net = _netOf(transaction);
        if (net > Decimal.zero) {
          expense += net;
          expenseCount++;
        }
      } else if (transaction.txKind == TransactionKind.income) {
        income += transaction.amount;
        incomeCount++;
      }
    }
    return _Totals(
      expense: expense,
      income: income,
      expenseCount: expenseCount,
      incomeCount: incomeCount,
    );
  }

  String buildContext() {
    final average = currentTotals.expenseCount == 0
        ? Decimal.zero
        : Decimal.parse(
            (currentTotals.expense.toDouble() / currentTotals.expenseCount)
                .toStringAsFixed(2),
          );
    final weekTotals = <int, Decimal>{};
    for (final transaction in current) {
      if (transaction.txKind != TransactionKind.expense) continue;
      final net = _netOf(transaction);
      if (net <= Decimal.zero) continue;
      final week = transaction.date.difference(start).inDays ~/ 7 + 1;
      weekTotals[week] = (weekTotals[week] ?? Decimal.zero) + net;
    }
    final topTransactions = current
        .where((transaction) => transaction.txKind == TransactionKind.expense)
        .map((transaction) =>
            (transaction: transaction, net: _netOf(transaction)))
        .where((item) => item.net > Decimal.zero)
        .toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    String percentage(Decimal part, Decimal total) {
      if (total <= Decimal.zero) return '0.0%';
      return '${(part.toDouble() / total.toDouble() * 100).toStringAsFixed(1)}%';
    }

    final buffer = StringBuffer()
      ..writeln('报告标题：${job.title}')
      ..writeln('报告类型：${job.type}')
      ..writeln('报告周期：${_date(start)} 至 ${_date(endInclusive)}')
      ..writeln()
      ..writeln('【本期准确合计】')
      ..writeln('- 支出：${MoneyFormat.string(currentTotals.expense)}')
      ..writeln('- 收入：${MoneyFormat.string(currentTotals.income)}')
      ..writeln(
        '- 结余：${MoneyFormat.string(currentTotals.income - currentTotals.expense)}',
      )
      ..writeln('- 支出笔数：${currentTotals.expenseCount}')
      ..writeln('- 笔均支出：${MoneyFormat.string(average)}')
      ..writeln()
      ..writeln('【上一等长周期参考】')
      ..writeln(
        '- 周期：${_date(previousStart)} 至 ${_date(previousEnd.subtract(const Duration(days: 1)))}',
      )
      ..writeln('- 支出：${MoneyFormat.string(previousTotals.expense)}')
      ..writeln('- 收入：${MoneyFormat.string(previousTotals.income)}')
      ..writeln('- 支出笔数：${previousTotals.expenseCount}')
      ..writeln()
      ..writeln('【分类支出明细】');

    final categories = categorySummary.expenseByCategory;
    if (categories.isEmpty) {
      buffer.writeln('无支出分类数据。');
    } else {
      for (final category in categories.take(20)) {
        buffer.writeln(
          '- ${category.name}：${MoneyFormat.string(category.total)}'
          '（${percentage(category.total, currentTotals.expense)}）',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('【周度/分段支出】');
    if (weekTotals.isEmpty) {
      buffer.writeln('无分段支出数据。');
    } else {
      for (final week in weekTotals.keys.toList()..sort()) {
        buffer.writeln('- 第 $week 周：${MoneyFormat.string(weekTotals[week]!)}');
      }
    }

    buffer
      ..writeln()
      ..writeln('【最大支出明细（最多 20 笔）】');
    if (topTransactions.isEmpty) {
      buffer.writeln('无支出明细。');
    } else {
      for (final item in topTransactions.take(20)) {
        final transaction = item.transaction;
        buffer.writeln(
          '- ${_date(transaction.date)}｜${transaction.categoryNameZh}｜'
          '${MoneyFormat.string(item.net)}｜${transaction.note}',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('【全部可见明细（最多 240 笔，金额为退款后的净额）】');
    for (final transaction in current.take(240)) {
      final kind = switch (transaction.txKind) {
        TransactionKind.income => '收入',
        TransactionKind.transfer => '转账',
        TransactionKind.expense => '支出',
      };
      final amount = transaction.txKind == TransactionKind.expense
          ? _netOf(transaction)
          : transaction.amount;
      buffer.writeln(
        '${_date(transaction.date)}|$kind|${transaction.categoryNameZh}|'
        '${MoneyFormat.string(amount)}|${transaction.note}',
      );
    }
    return buffer.toString();
  }

  String buildLocalFallback(String error) {
    final average = currentTotals.expenseCount == 0
        ? Decimal.zero
        : Decimal.parse(
            (currentTotals.expense.toDouble() / currentTotals.expenseCount)
                .toStringAsFixed(2),
          );
    final categories = categorySummary.expenseByCategory;
    final topTransactions = current
        .where((transaction) => transaction.txKind == TransactionKind.expense)
        .map((transaction) =>
            (transaction: transaction, net: _netOf(transaction)))
        .where((item) => item.net > Decimal.zero)
        .toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    String percentage(Decimal part, Decimal total) {
      if (total <= Decimal.zero) return '0.0%';
      return '${(part.toDouble() / total.toDouble() * 100).toStringAsFixed(1)}%';
    }

    String change(Decimal current, Decimal previous) {
      final difference = current - previous;
      if (difference == Decimal.zero) return '持平';
      return '${difference > Decimal.zero ? '增加' : '减少'} '
          '${MoneyFormat.string(difference.abs())}';
    }

    final buffer = StringBuffer()
      ..writeln('# ${job.title}')
      ..writeln()
      ..writeln('## 摘要')
      ..writeln()
      ..writeln('- 报告周期：${_date(start)} 至 ${_date(endInclusive)}。')
      ..writeln(
        '- 本期支出 **${MoneyFormat.string(currentTotals.expense)}**，'
        '收入 **${MoneyFormat.string(currentTotals.income)}**，'
        '结余 **${MoneyFormat.string(currentTotals.income - currentTotals.expense)}**。',
      )
      ..writeln(
        '- 对比上一等长周期，支出${change(currentTotals.expense, previousTotals.expense)}。',
      )
      ..writeln()
      ..writeln('## 一、核心指标')
      ..writeln()
      ..writeln('| 指标 | 本期 | 上一等长周期 |')
      ..writeln('| --- | ---: | ---: |')
      ..writeln(
        '| 支出 | ${MoneyFormat.string(currentTotals.expense)} | '
        '${MoneyFormat.string(previousTotals.expense)} |',
      )
      ..writeln(
        '| 收入 | ${MoneyFormat.string(currentTotals.income)} | '
        '${MoneyFormat.string(previousTotals.income)} |',
      )
      ..writeln('| 支出笔数 | ${currentTotals.expenseCount} | '
          '${previousTotals.expenseCount} |')
      ..writeln('| 笔均支出 | ${MoneyFormat.string(average)} | - |')
      ..writeln()
      ..writeln('## 二、分类支出')
      ..writeln();
    if (categories.isEmpty) {
      buffer.writeln('- 本期没有可计入统计的分类支出。');
    } else {
      for (final category in categories.take(6)) {
        buffer.writeln(
          '- **${category.name}**：${MoneyFormat.string(category.total)}，'
          '占 ${percentage(category.total, currentTotals.expense)}。',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## 三、值得回看')
      ..writeln();
    if (topTransactions.isEmpty) {
      buffer.writeln('- 本期没有可列出的支出明细。');
    } else {
      for (final item in topTransactions.take(5)) {
        final transaction = item.transaction;
        buffer.writeln(
          '- ${_date(transaction.date)}｜${transaction.categoryNameZh}｜'
          '${MoneyFormat.string(item.net)}｜'
          '${transaction.note.isEmpty ? '无备注' : transaction.note}',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## 四、下阶段建议')
      ..writeln()
      ..writeln('- 优先复盘占比最高的分类和大额订单，区分一次性支出与长期习惯。')
      ..writeln('- 对偶发波动保持中性判断，连续多个周期重复出现后再调整预算。')
      ..writeln()
      ..writeln('<!-- AI fallback: ${_shortError(error)} -->');
    return buffer.toString();
  }

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 100) return text;
    return '${text.substring(0, 100)}…';
  }
}

class _Totals {
  final Decimal expense;
  final Decimal income;
  final int expenseCount;
  final int incomeCount;

  const _Totals({
    required this.expense,
    required this.income,
    required this.expenseCount,
    required this.incomeCount,
  });
}
