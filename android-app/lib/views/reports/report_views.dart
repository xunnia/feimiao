import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/report_job_runtime.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

Future<void> showReportLibrarySheet(BuildContext context) {
  return showBlurSheet<void>(
    context,
    child: const _ReportLibrarySheet(),
  );
}

void openReportReader(BuildContext context, ReportEntity report) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => ReportReaderView(report: report),
    ),
  );
}

class ReportDocumentCard extends StatelessWidget {
  final ReportEntity report;
  final bool compact;
  final VoidCallback? onTogglePinned;
  final VoidCallback? onRegenerate;
  final VoidCallback? onDelete;

  const ReportDocumentCard({
    super.key,
    required this.report,
    this.compact = false,
    this.onTogglePinned,
    this.onRegenerate,
    this.onDelete,
  });

  bool get _hasMenu =>
      onTogglePinned != null || onRegenerate != null || onDelete != null;

  void _showMenu(BuildContext context) {
    showIosMenu(context, [
      if (onTogglePinned != null)
        IosMenuItem(
          label: report.pinned ? '取消置顶' : '置顶',
          icon: report.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          onTap: onTogglePinned!,
        ),
      if (onRegenerate != null)
        IosMenuItem(
          label: '重新生成',
          icon: Icons.refresh,
          onTap: onRegenerate!,
        ),
      if (onDelete != null)
        IosMenuItem(
          label: '删除',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: onDelete!,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: () => openReportReader(context, report),
      onLongPress: _hasMenu ? () => _showMenu(context) : null,
      child: Container(
        height: compact ? 82 : 96,
        margin: EdgeInsets.only(bottom: compact ? 8 : 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppColors.hairline(scheme, strength: 1.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.055),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: compact ? 92 : 112,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: compact ? 25 : 30,
                    top: compact ? 13 : 15,
                    child: Transform.rotate(
                      angle: -0.09,
                      child: Container(
                        width: compact ? 58 : 68,
                        height: compact ? 74 : 86,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.hairline(scheme)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.035),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          CupertinoIcons.doc_text,
                          size: compact ? 22 : 26,
                          color: scheme.onSurface.withValues(alpha: 0.84),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: compact ? 12 : 16,
                  top: compact ? 10 : 13,
                  bottom: compact ? 10 : 13,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 15.5 : 17,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (report.pinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: compact ? 12 : 13,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.68),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'Document · MD',
                          style: TextStyle(
                            fontSize: compact ? 12.8 : 14,
                            fontWeight: FontWeight.w400,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportLibrarySheet extends StatefulWidget {
  const _ReportLibrarySheet();

  @override
  State<_ReportLibrarySheet> createState() => _ReportLibrarySheetState();
}

class _ReportLibrarySheetState extends State<_ReportLibrarySheet> {
  String? _type;
  final Set<int> _regeneratingReportIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final reports = repo.reports
        .where((r) => _type == null || r.type == _type)
        .toList(growable: false);
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          SheetHeader(
            title: '报告',
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: _ReportTypeFilter(
              value: _type,
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          Expanded(
            child: reports.isEmpty
                ? const _EmptyReports()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: reports.length,
                    itemBuilder: (_, i) => ReportDocumentCard(
                      report: reports[i],
                      compact: false,
                      onTogglePinned: () => _togglePinned(reports[i]),
                      onRegenerate: () => _regenerateReport(reports[i]),
                      onDelete: () => _deleteReport(reports[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePinned(ReportEntity report) async {
    await context.read<AppRepository>().setReportPinned(
          report.id,
          !report.pinned,
        );
  }

  Future<void> _deleteReport(ReportEntity report) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这份报告？',
      message: '删除后不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppRepository>().deleteReport(report.id);
    if (mounted) showAppToast(context, '已删除报告');
  }

  Future<void> _regenerateReport(ReportEntity report) async {
    if (!_regeneratingReportIds.add(report.id)) {
      showAppToast(context, '这份报告正在重新生成');
      return;
    }
    final repo = context.read<AppRepository>();
    final aiConfig = repo.aiProviderConfigFor(AiTaskType.report);
    if (!aiConfig.hasKey) {
      showAppToast(context, '先去「我的 → AI 记账设置」填写 API Key');
      _regeneratingReportIds.remove(report.id);
      return;
    }
    ReportJobEntity? job;
    try {
      job = await repo.createReportJob(
        question: '重新生成${report.title}',
        type: report.type,
        title: report.title,
        periodStart: report.periodStart,
        periodEnd: report.periodEnd,
        bookId: report.bookId,
        reportId: report.id,
      );
      if (!ReportJobRuntime.claim(job.id)) {
        await repo.updateReportJob(
          job.id,
          status: 'failed',
          error: 'duplicate in-process report job',
        );
        return;
      }
      await repo.updateReportJob(
        job.id,
        status: 'running',
        stage: 'generate',
      );
      if (mounted) showAppToast(context, '正在重新生成报告…');
      final answer = await LlmQuery.askReport(
        reportTitle: report.title,
        reportType: report.type,
        config: aiConfig,
        transactionsText: _buildReportContext(repo, report),
      );
      final markdown = _ensureReportMarkdown(report.title, answer);
      await repo.updateReportContent(
        report.id,
        summary: _reportSummaryFromMarkdown(markdown),
        markdown: markdown,
      );
      await repo.updateReportJob(
        job.id,
        status: 'completed',
        stage: 'save',
        reportId: report.id,
      );
      if (mounted) showAppToast(context, '报告已重新生成');
    } catch (error) {
      if (job != null) {
        try {
          await repo.updateReportJob(
            job.id,
            status: 'failed',
            error: error.toString(),
          );
        } catch (_) {}
      }
      if (mounted) showAppToast(context, '重新生成失败，稍后再试');
    } finally {
      if (job != null) ReportJobRuntime.release(job.id);
      _regeneratingReportIds.remove(report.id);
    }
  }
}

class _ReportTypeFilter extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ReportTypeFilter({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String?, String)>[
      (null, '全部'),
      ('weekly', '周报'),
      ('monthly', '月报'),
      ('yearly', '年报'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final item in items) ...[
          Expanded(
            child: PressableScale(
              onPressed: () => onChanged(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == item.$1
                      ? scheme.onSurface.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: value == item.$1
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (item != items.last) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Text(
          '还没有报告。生成周报、月报或年报后，会在这里统一查看。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

class ReportReaderView extends StatelessWidget {
  final ReportEntity report;

  const ReportReaderView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(report.title),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Text(
              _reportTypeLabel(report.type),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText.rich(
              TextSpan(
                children: _markdownSpans(
                  report.markdown.isEmpty ? report.summary : report.markdown,
                  Theme.of(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _ensureReportMarkdown(String title, String answer) {
  final trimmed = answer.trim();
  if (trimmed.startsWith('# ')) return trimmed;
  return '# $title\n\n$trimmed';
}

String _reportSummaryFromMarkdown(String markdown) {
  final summaryLines = <String>[];
  var inLeadSection = false;
  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    if (RegExp(r'^##\s+(本月一句话|摘要)').hasMatch(line)) {
      inLeadSection = true;
      continue;
    }
    if (inLeadSection && RegExp(r'^#{1,6}\s+').hasMatch(line)) break;
    if (!inLeadSection || line.isEmpty || line.startsWith('|')) continue;
    final cleaned = line
        .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
        .replaceAll('**', '')
        .trim();
    if (cleaned.isNotEmpty) summaryLines.add(cleaned);
  }

  final cleanedLines = summaryLines.isNotEmpty ? summaryLines : <String>[];
  if (cleanedLines.isEmpty) {
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('|')) continue;
      if (RegExp(r'^#{1,6}\s+').hasMatch(line)) continue;
      final cleaned = line
          .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
          .replaceAll('**', '')
          .trim();
      if (cleaned.isNotEmpty) cleanedLines.add(cleaned);
    }
  }
  final cleaned = cleanedLines.join(' ');
  if (cleaned.length <= 160) return cleaned;
  return '${cleaned.substring(0, 160)}…';
}

String _buildReportContext(AppRepository repo, ReportEntity report) {
  final start = DateTime(
    report.periodStart.year,
    report.periodStart.month,
    report.periodStart.day,
  );
  final endExclusive = DateTime(
    report.periodEnd.year,
    report.periodEnd.month,
    report.periodEnd.day,
  ).add(const Duration(days: 1));
  final days = endExclusive.difference(start).inDays.clamp(1, 366);
  final prevEnd = start;
  final prevStart = start.subtract(Duration(days: days));

  bool inRange(TransactionEntity t, DateTime s, DateTime e) =>
      !t.date.isBefore(s) && t.date.isBefore(e) && !t.excluded;

  final visibleTransactions = report.bookId == null
      ? repo.visibleTransactions
      : repo.visibleTransactionsForBookView(report.bookId!);
  final records = report.bookId == null
      ? repo.allRecords
      : repo.recordsForBookView(report.bookId!);
  Decimal netOf(TransactionEntity transaction) => report.bookId == null
      ? repo.netAmountOf(transaction)
      : repo.netAmountAcrossBooks(transaction);
  final current = visibleTransactions
      .where((t) => inRange(t, start, endExclusive))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  final previous =
      visibleTransactions.where((t) => inRange(t, prevStart, prevEnd));
  final categorySummary = StatisticsEngine.rangeSummary(
    records,
    start: start,
    end: report.periodEnd,
  );

  ({Decimal expense, Decimal income, int expenseCount}) summarize(
    Iterable<TransactionEntity> rows,
  ) {
    var expense = Decimal.zero;
    var income = Decimal.zero;
    var expenseCount = 0;
    for (final t in rows) {
      if (t.txKind == TransactionKind.expense) {
        final net = netOf(t);
        if (net > Decimal.zero) {
          expense += net;
          expenseCount++;
        }
      } else if (t.txKind == TransactionKind.income) {
        income += t.amount;
      }
    }
    return (expense: expense, income: income, expenseCount: expenseCount);
  }

  final curSummary = summarize(current);
  final prevSummary = summarize(previous);
  final avgExpense = curSummary.expenseCount == 0
      ? Decimal.zero
      : Decimal.parse(
          (curSummary.expense.toDouble() / curSummary.expenseCount)
              .toStringAsFixed(2),
        );

  final weekTotals = <int, Decimal>{};
  for (final t in current) {
    if (t.txKind != TransactionKind.expense) continue;
    final net = netOf(t);
    if (net <= Decimal.zero) continue;
    final dayOffset = t.date.difference(start).inDays;
    final week = dayOffset ~/ 7 + 1;
    weekTotals[week] = (weekTotals[week] ?? Decimal.zero) + net;
  }

  final cats = categorySummary.expenseByCategory;
  final topTxns = current
      .where((t) => t.txKind == TransactionKind.expense)
      .map((t) => (txn: t, net: netOf(t)))
      .where((e) => e.net > Decimal.zero)
      .toList()
    ..sort((a, b) => b.net.compareTo(a.net));

  String fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String percent(Decimal part, Decimal total) {
    if (total <= Decimal.zero) return '0.0%';
    return '${(part.toDouble() / total.toDouble() * 100).toStringAsFixed(1)}%';
  }

  final sb = StringBuffer()
    ..writeln('报告标题：${report.title}')
    ..writeln(
        '报告周期：${start.year}-${start.month}-${start.day} 至 ${report.periodEnd.year}-${report.periodEnd.month}-${report.periodEnd.day}')
    ..writeln('【本期准确合计】')
    ..writeln('- 支出：${MoneyFormat.string(curSummary.expense)}')
    ..writeln('- 收入：${MoneyFormat.string(curSummary.income)}')
    ..writeln(
        '- 结余：${MoneyFormat.string(curSummary.income - curSummary.expense)}')
    ..writeln('- 支出笔数：${curSummary.expenseCount} 笔')
    ..writeln('- 笔均支出：${MoneyFormat.string(avgExpense)}')
    ..writeln()
    ..writeln('【上一周期参考】')
    ..writeln('- 支出：${MoneyFormat.string(prevSummary.expense)}')
    ..writeln('- 收入：${MoneyFormat.string(prevSummary.income)}')
    ..writeln('- 支出笔数：${prevSummary.expenseCount} 笔')
    ..writeln()
    ..writeln('【分类支出明细（按金额降序）】');
  if (cats.isEmpty) {
    sb.writeln('无支出分类数据。');
  } else {
    for (final e in cats.take(12)) {
      sb.writeln(
          '${e.name}|${MoneyFormat.string(e.total)}|${percent(e.total, curSummary.expense)}');
    }
  }
  sb
    ..writeln()
    ..writeln('【单笔最大的支出】');
  if (topTxns.isEmpty) {
    sb.writeln('无支出明细。');
  } else {
    for (final e in topTxns.take(10)) {
      final t = e.txn;
      sb.writeln(
          '${fmtDate(t.date)}|${t.categoryNameZh}|${MoneyFormat.string(e.net)}|${t.note}');
    }
  }
  sb
    ..writeln()
    ..writeln('【时间分布（按 7 天一段）】');
  for (final e in weekTotals.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    sb.writeln('第${e.key}段|${MoneyFormat.string(e.value)}');
  }
  sb
    ..writeln()
    ..writeln('【账目明细（最近最多 180 条，金额为退款后净额）】');
  for (final t in current.take(180)) {
    final kind = t.txKind == TransactionKind.income
        ? '收'
        : (t.txKind == TransactionKind.transfer ? '转' : '支');
    final amount = t.txKind == TransactionKind.expense ? netOf(t) : t.amount;
    sb.writeln(
        '${fmtDate(t.date)}|$kind|${t.categoryNameZh}|${MoneyFormat.string(amount)}|${t.note}');
  }
  return sb.toString();
}

String _reportTypeLabel(String type) {
  return switch (type) {
    'weekly' => 'Document · MD · 周报',
    'yearly' => 'Document · MD · 年报',
    _ => 'Document · MD · 月报',
  };
}

List<InlineSpan> _markdownSpans(String text, ThemeData theme) {
  final scheme = theme.colorScheme;
  final base = TextStyle(
    fontSize: 15.5,
    height: 1.56,
    fontWeight: FontWeight.w400,
    fontVariations: const [FontVariation('wght', 350)],
    color: scheme.onSurface.withValues(alpha: 0.92),
  );
  final heading = base.copyWith(
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation('wght', 520)],
    color: scheme.onSurface,
  );
  final subheading = base.copyWith(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation('wght', 500)],
    color: scheme.onSurface,
  );
  final numberStyle = base.copyWith(
    fontFamily: 'Nunito',
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final spans = <InlineSpan>[];
  final numberPattern = RegExp(r'[+\-￥¥]?\d[\d,]*(?:\.\d+)?%?');

  void addWithNumbers(String value, TextStyle style) {
    var start = 0;
    for (final m in numberPattern.allMatches(value)) {
      if (m.start > start) {
        spans
            .add(TextSpan(text: value.substring(start, m.start), style: style));
      }
      spans.add(TextSpan(text: m.group(0), style: numberStyle.merge(style)));
      start = m.end;
    }
    if (start < value.length) {
      spans.add(TextSpan(text: value.substring(start), style: style));
    }
  }

  void addInlineBold(String value, TextStyle style) {
    final parts = value.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      addWithNumbers(
        parts[i],
        i.isOdd
            ? style.copyWith(
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation('wght', 500)],
              )
            : style,
      );
    }
  }

  final lines = text.trim().split('\n');
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trimRight();
    final line = raw.trimLeft();
    if (line.isEmpty) {
      spans.add(const TextSpan(text: '\n', style: TextStyle(fontSize: 8)));
      continue;
    }
    final headingMatch = RegExp(r'^(#{1,6})\s+').firstMatch(line);
    if (headingMatch != null) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n', style: TextStyle(fontSize: 8)));
      }
      addInlineBold(
        line.substring(headingMatch.end),
        headingMatch.group(1)!.length == 1 ? heading : subheading,
      );
      spans.add(const TextSpan(text: '\n'));
      continue;
    }
    final unordered = RegExp(r'^[-*]\s+').firstMatch(line);
    final ordered = RegExp(r'^(\d+)[.)]\s+').firstMatch(line);
    if (unordered != null) {
      spans.add(TextSpan(text: '•  ', style: base));
      addInlineBold(line.substring(unordered.end), base);
    } else if (ordered != null) {
      spans.add(TextSpan(text: '${ordered.group(1)}.  ', style: numberStyle));
      addInlineBold(line.substring(ordered.end), base);
    } else {
      addInlineBold(line, base);
    }
    if (i != lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return spans;
}
