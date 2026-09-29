import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_extensions.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_provider_health.dart';
import '../../core/ai/ai_run.dart';
import '../../data/app_repository.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/settings_ui.dart';

/// 「任务与诊断」页的「任务」分段：AI 运行记录和报告任务。
class AiTaskCenterBody extends StatelessWidget {
  const AiTaskCenterBody({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return FutureBuilder<List<AiRun>>(
        future: repo.loadAiRuns(limit: 100),
        builder: (context, snapshot) {
          final runs = snapshot.data ?? const <AiRun>[];
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              if (runs.isEmpty)
                const SettingsGroup(
                  children: [
                    SettingsRow(
                      leading: Icon(CupertinoIcons.checkmark_circle),
                      title: '暂无 AI 任务',
                      subtitle: '发送消息或生成报告后，任务会显示在这里。',
                    ),
                  ],
                )
              else
                SettingsGroup(
                  children: [
                    for (final run in runs)
                      SettingsRow(
                        leading: Icon(_runIcon(run.mode)),
                        title: run.mode.label,
                        subtitle:
                            '${run.config.providerLabel} · ${run.config.model.isEmpty ? '未指定模型' : run.config.model}',
                        trailing: Text(
                          run.status.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: _runColor(context, run.status),
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AiRunDetailView(run: run),
                          ),
                        ),
                      ),
                  ],
                ),
              FutureBuilder<List<ReportJobEntity>>(
                future: repo.pendingReportJobs(),
                builder: (context, snapshot) {
                  final jobs = snapshot.data ?? const <ReportJobEntity>[];
                  if (jobs.isEmpty) return const SizedBox.shrink();
                  return SettingsGroup(
                    children: [
                      for (final job in jobs)
                        SettingsRow(
                          leading: const Icon(CupertinoIcons.doc_text),
                          title: job.title,
                          subtitle: '报告任务 · ${job.stage}',
                          trailing: Text(job.status),
                        ),
                    ],
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Text(
                  '运行记录只保留状态、耗时和配置快照，不包含密钥或完整账本内容。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          );
        },
    );
  }

  static IconData _runIcon(AiRunMode mode) => switch (mode) {
        AiRunMode.record => CupertinoIcons.money_yen_circle,
        AiRunMode.chat => CupertinoIcons.chat_bubble_2,
        AiRunMode.query => CupertinoIcons.search,
        AiRunMode.report ||
        AiRunMode.scheduledReport =>
          CupertinoIcons.doc_text,
        AiRunMode.import => CupertinoIcons.arrow_down_doc,
        AiRunMode.localModel => CupertinoIcons.desktopcomputer,
      };

  static Color _runColor(BuildContext context, AiRunStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      AiRunStatus.failed => scheme.error,
      AiRunStatus.completed || AiRunStatus.rolledBack => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
  }
}

/// A privacy-safe run inspection page. Event payloads are deliberately
/// summarized instead of rendering arbitrary provider output or reasoning.
class AiRunDetailView extends StatelessWidget {
  final AiRun run;

  const AiRunDetailView({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('AI 任务详情'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                leading: Icon(_iconForMode(run.mode)),
                title: run.mode.label,
                subtitle:
                    '${run.config.providerLabel} · ${run.config.model.isEmpty ? '未指定模型' : run.config.model}',
                trailing: Text(
                  run.status.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AiTaskCenterBody._runColor(context, run.status),
                  ),
                ),
              ),
              SettingsRow(
                title: '思考强度',
                subtitle: run.config.effort,
              ),
              SettingsRow(
                title: '请求方式',
                subtitle: run.config.endpointType,
              ),
              SettingsRow(
                title: '开始时间',
                subtitle: _formatDate(run.createdAt),
              ),
              if (run.errorMessage.trim().isNotEmpty)
                SettingsRow(
                  title: '错误',
                  subtitle: run.errorMessage,
                  titleColor: scheme.error,
                ),
            ],
          ),
          SettingsSectionLabel('运行过程'),
          FutureBuilder<List<AiRunEvent>>(
            future: repo.loadAiRunEvents(run.id),
            builder: (context, snapshot) {
              final events = snapshot.data ?? const <AiRunEvent>[];
              if (events.isEmpty &&
                  snapshot.connectionState == ConnectionState.done) {
                return const SettingsGroup(
                  children: [SettingsRow(title: '暂无过程记录')],
                );
              }
              return SettingsGroup(
                children: [
                  for (final event in events)
                    SettingsRow(
                      leading: Icon(_iconForEvent(event.type)),
                      title: _labelForEvent(event.type),
                      subtitle: _eventSubtitle(event),
                    ),
                ],
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Text(
              '过程记录只显示阶段和计数，不保存密钥、完整提示词或原始思考内容。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconForMode(AiRunMode mode) =>
      AiTaskCenterBody._runIcon(mode);

  static IconData _iconForEvent(AiRunEventType type) => switch (type) {
        AiRunEventType.runStarted => CupertinoIcons.play_circle,
        AiRunEventType.stageChanged => CupertinoIcons.arrow_right_circle,
        AiRunEventType.contextReady => CupertinoIcons.doc_text,
        AiRunEventType.attachmentReady => CupertinoIcons.paperclip,
        AiRunEventType.toolRequested ||
        AiRunEventType.toolResult =>
          CupertinoIcons.wrench,
        AiRunEventType.confirmationRequired => CupertinoIcons.checkmark_shield,
        AiRunEventType.delta => CupertinoIcons.text_append,
        AiRunEventType.reasoning => CupertinoIcons.lightbulb,
        AiRunEventType.source => CupertinoIcons.link,
        AiRunEventType.proposalReady => CupertinoIcons.list_bullet,
        AiRunEventType.retry => CupertinoIcons.refresh,
        AiRunEventType.committed => CupertinoIcons.checkmark_circle,
        AiRunEventType.rolledBack => CupertinoIcons.arrow_counterclockwise,
        AiRunEventType.completed => CupertinoIcons.checkmark_seal,
        AiRunEventType.failed => CupertinoIcons.exclamationmark_triangle,
        AiRunEventType.cancelled => CupertinoIcons.stop_circle,
      };

  static String _labelForEvent(AiRunEventType type) => switch (type) {
        AiRunEventType.runStarted => '任务已创建',
        AiRunEventType.stageChanged => '阶段更新',
        AiRunEventType.contextReady => '上下文已准备',
        AiRunEventType.attachmentReady => '附件已准备',
        AiRunEventType.toolRequested => '请求工具',
        AiRunEventType.toolResult => '工具返回',
        AiRunEventType.confirmationRequired => '等待确认',
        AiRunEventType.delta => '回复流式更新',
        AiRunEventType.reasoning => '思考摘要更新',
        AiRunEventType.source => '来源更新',
        AiRunEventType.proposalReady => '记账方案已生成',
        AiRunEventType.retry => '正在重试',
        AiRunEventType.committed => '已写入账本',
        AiRunEventType.rolledBack => '已撤销',
        AiRunEventType.completed => '任务完成',
        AiRunEventType.failed => '任务失败',
        AiRunEventType.cancelled => '任务已取消',
      };

  static String _eventSubtitle(AiRunEvent event) {
    final payload = event.payload;
    final details = <String>[];
    final stage = payload['stage']?.toString().trim() ?? '';
    if (stage.isNotEmpty) details.add(stage);
    final items = payload['items'];
    if (items is num) details.add('${items.toInt()} 项');
    final count = payload['count'];
    if (count is num) details.add('${count.toInt()} 项');
    details
        .add(_formatDate(DateTime.fromMillisecondsSinceEpoch(event.createdMs)));
    return details.join(' · ');
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

/// 复制脱敏的诊断摘要（「任务与诊断」页「诊断」分段右上角按钮）。
Future<void> copyAiDiagnostics(BuildContext context) async {
  final repo = context.read<AppRepository>();
  final runs = await repo.loadAiRuns(limit: 20);
  final health = repo.aiProviderHealth;
  final buffer = StringBuffer('肥喵 AI 诊断摘要\n');
  for (final item in health) {
    buffer.writeln(
      '${item.providerId}: ${item.statusLabel}, 成功${item.successCount}, 失败${item.failureCount}, 平均首字${item.averageLatencyMs}ms',
    );
  }
  for (final run in runs.take(10)) {
    buffer.writeln(
      '${run.createdAt.toIso8601String()} ${run.mode.label} ${run.status.label} ${run.errorCode}',
    );
  }
  await Clipboard.setData(ClipboardData(text: buffer.toString()));
  if (context.mounted) showAppToast(context, '诊断摘要已复制');
}

/// 「任务与诊断」页的「诊断」分段：服务商健康和耗时。
class AiDiagnosticsBody extends StatelessWidget {
  const AiDiagnosticsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        SettingsGroup(
          children: [
            if (repo.aiProviders.isEmpty)
              const SettingsRow(
                leading: Icon(CupertinoIcons.info),
                title: '还没有服务商',
              ),
            for (final provider in repo.aiProviders)
              _HealthRow(
                provider: provider,
                health: repo.aiProviderHealthFor(provider.id),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Text(
            '诊断内容经过脱敏，只用于定位连接、超时和模型目录问题。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  final AiConfiguredProvider provider;
  final AiProviderHealth health;

  const _HealthRow({required this.provider, required this.health});

  @override
  Widget build(BuildContext context) => SettingsRow(
        leading: Icon(
          health.isCoolingDown
              ? CupertinoIcons.exclamationmark_triangle
              : CupertinoIcons.waveform_path_ecg,
        ),
        title: provider.label,
        subtitle: health.averageLatencyMs > 0
            ? '${health.statusLabel} · 平均首字 ${health.averageLatencyMs}ms'
            : health.statusLabel,
        trailing: Text(
          '${health.successCount}/${health.successCount + health.failureCount}',
          style: const TextStyle(fontSize: 12),
        ),
      );
}

/// 添加一条可控记忆（「记忆」页「可控记忆」分段右上角按钮）。
Future<void> addAiMemory(BuildContext context) async {
  final phrase = TextEditingController();
  final content = TextEditingController();
  final result = await showIosFormDialog(
    context,
    title: '添加一条记忆',
    subtitle: '只在匹配到触发短语时使用',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: phrase,
          textInputAction: TextInputAction.next,
          decoration: iosInputDecoration(context, hint: '触发短语'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: content,
          maxLines: 3,
          decoration: iosInputDecoration(context, hint: '要记住的内容'),
        ),
      ],
    ),
    confirmText: '保存',
    cancelText: '取消',
  );
  if (result == true && context.mounted) {
    final memory = await context.read<AppRepository>().addAiMemory(
          phrase: phrase.text,
          content: content.text,
          consent: true,
        );
    if (context.mounted) {
      showAppToast(context, memory == null ? '内容不能为空' : '已添加记忆');
    }
  }
  phrase.dispose();
  content.dispose();
}

/// 「记忆」页的「可控记忆」分段：只保留用户明确授权的偏好。
class AiMemoryControlBody extends StatelessWidget {
  const AiMemoryControlBody({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        SettingsGroup(
          children: repo.aiMemories.isEmpty
              ? const [
                  SettingsRow(
                    leading: Icon(CupertinoIcons.lock_shield),
                    title: '没有已授权记忆',
                    subtitle: '喵不会在没有确认的情况下自动保存内容。',
                  ),
                ]
              : [
                  for (final memory in repo.aiMemories)
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.text_bubble),
                      title: memory.phrase,
                      subtitle: memory.content,
                      trailing: AppCircleButton(
                        icon: CupertinoIcons.delete,
                        onPressed: () => repo.deleteAiMemory(memory.id),
                      ),
                    ),
                ],
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              leading: const Icon(CupertinoIcons.trash),
              title: '忘记全部记忆',
              titleColor: Theme.of(context).colorScheme.error,
              onTap: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: '忘记全部记忆？',
                  message: '历史账单不会受影响。',
                  confirmText: '忘记',
                  destructive: true,
                );
                if (ok && context.mounted) {
                  await repo.forgetAllAiMemories();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class AiReportScheduleView extends StatelessWidget {
  const AiReportScheduleView({super.key});

  Future<void> _add(BuildContext context) async {
    final repo = context.read<AppRepository>();
    final schedule = AiReportSchedule(
      id: '',
      title: '每月账本报告',
      reportType: 'monthly',
      periodKind: 'monthly',
      dayValue: 1,
      providerId: repo.chatCurrentProviderId ?? '',
      model: repo.chatCurrentModel ?? '',
      effort: repo.chatReasoningEffort.storageKey,
    );
    await repo.saveAiReportSchedule(schedule);
    if (context.mounted) showAppToast(context, '已添加每月报告');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('定时报表'),
        centerTitle: true,
        actions: [
          AppCircleButton(
            icon: CupertinoIcons.add,
            onPressed: () => _add(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          SettingsGroup(
            children: repo.aiReportSchedules.isEmpty
                ? const [SettingsRow(title: '还没有定时报表')]
                : [
                    for (final schedule in repo.aiReportSchedules)
                      SettingsRow(
                        leading: const Icon(CupertinoIcons.calendar),
                        title: schedule.title,
                        subtitle:
                            '${schedule.periodKind == 'weekly' ? '每周' : '每月'} · 下次 ${_formatDate(schedule.nextRun)}',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppSwitch(
                              value: schedule.enabled,
                              semanticLabel: schedule.title,
                              onChanged: (value) => repo.saveAiReportSchedule(
                                schedule.copyWith(enabled: value),
                              ),
                            ),
                            AppCircleButton(
                              icon: CupertinoIcons.delete,
                              onPressed: () =>
                                  repo.deleteAiReportSchedule(schedule.id),
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
