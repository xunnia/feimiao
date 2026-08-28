import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/report_execution_fence.dart';
import '../../core/ai/report_generation_service.dart';
import '../../core/ai/report_job_runtime.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import '../settings/ai_privacy_consent.dart';

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
    final aiConfig = repo.aiProviderConfigFor(AiTaskType.chatQuery);
    if (!aiConfig.hasCredential) {
      showAppToast(context, '先去「我的 → AI 记账设置」配置 API Key 或 OAuth');
      _regeneratingReportIds.remove(report.id);
      return;
    }
    if (!repo.aiSkillAllowsTool('report_writer', 'read_ledger')) {
      showAppToast(context, '报告生成助手已关闭，请先在 AI 设置中重新开启');
      _regeneratingReportIds.remove(report.id);
      return;
    }
    // 隐私闸门：重新生成同样会把账本上下文发给 AI，必须先同意。
    final consented = await ensureAiPrivacyConsent(
      context,
      config: aiConfig,
    );
    if (!consented || !mounted) {
      if (mounted) showAppToast(context, '未同意 AI 隐私说明，报告不会重新生成');
      _regeneratingReportIds.remove(report.id);
      return;
    }
    ReportJobEntity? job;
    ReportGenerationLease? lease;
    String? runtimeKey;
    try {
      final baseLease = await repo.acquireReportGenerationLease();
      final createdJob = await repo.guardReportGeneration(
        baseLease,
        () => repo.createReportJob(
          question: '重新生成${report.title}',
          type: report.type,
          title: report.title,
          periodStart: report.periodStart,
          periodEnd: report.periodEnd,
          bookId: report.bookId,
          reportId: report.id,
        ),
      );
      job = createdJob;
      lease = baseLease.bind(
        jobId: createdJob.id,
        jobUuid: createdJob.uuid,
      );
      runtimeKey = lease.runtimeKey;
      if (!ReportJobRuntime.claim(runtimeKey)) {
        return;
      }
      if (mounted) showAppToast(context, '正在重新生成报告…');
      final uiDatabaseGeneration = repo.databaseGeneration;
      await ReportGenerationService.generate(
        repo,
        createdJob,
        lease: lease,
      );
      if (repo.databaseGeneration != uiDatabaseGeneration) {
        throw const ReportGenerationInvalidated();
      }
      if (mounted) showAppToast(context, '报告已重新生成');
    } on ReportGenerationInvalidated {
      if (mounted) showAppToast(context, '数据库已恢复，本次重新生成已取消');
    } catch (error) {
      if (job != null && lease != null) {
        try {
          await repo.guardReportGeneration(
            lease,
            () => repo.updateReportJob(
              job!.id,
              expectedUuid: job.uuid,
              status: 'failed',
              error: error.toString(),
            ),
          );
        } catch (_) {}
      }
      if (mounted) showAppToast(context, '重新生成失败，稍后再试');
    } finally {
      if (runtimeKey != null) ReportJobRuntime.release(runtimeKey);
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
