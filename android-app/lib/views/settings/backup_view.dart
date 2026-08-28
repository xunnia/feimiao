import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../widgets/ios_dialogs.dart';
import '../../widgets/app_buttons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';

/// 数据层继续保留迁移前保护备份；常规页面只展示最近三个恢复点，避免
/// 多次升级留下的保护文件把列表无限拉长。
@visibleForTesting
List<File> localBackupsForDisplay(List<File> files, {int limit = 3}) {
  if (limit <= 0) return const <File>[];
  return List<File>.unmodifiable(files.take(limit));
}

/// 本地备份 / 恢复（不涉及云）：
/// - 导出：把脱敏数据库 + 收据图片打成 zip 分享出去。
/// - 恢复：从一个备份包覆盖当前数据（不可撤销，覆盖前自动留 .bak 兜底）。
/// - 本机备份：自动保留最近 3 份，点一下就能恢复。
class BackupView extends StatefulWidget {
  const BackupView({super.key});

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  late Future<List<File>> _backups;

  @override
  void initState() {
    super.initState();
    _backups = context.read<AppRepository>().localBackupFiles();
  }

  void _reloadBackups() {
    setState(() {
      _backups = context.read<AppRepository>().localBackupFiles();
    });
  }

  Future<void> _export(BuildContext context) async {
    final repo = context.read<AppRepository>();
    try {
      final file = await repo.exportBackupPackage();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await Share.shareXFiles(
        [XFile(file.path, name: file.uri.pathSegments.last)],
        text: '肥喵完整账本备份（$stamp，包含账本和收据图片，不含 AI API Key）',
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, '导出失败，请重试', icon: Icons.error_outline);
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    final repo = context.read<AppRepository>();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'db', 'bak'],
    );
    if (!context.mounted) return;
    final path = (result != null && result.files.isNotEmpty)
        ? result.files.first.path
        : null;
    if (path == null) return;

    final ok = await showConfirmDialog(
      context,
      title: '从备份恢复？',
      message: '将用所选文件覆盖当前全部账目数据，且不可撤销。\n'
          '（系统会在覆盖前自动保留一份 .bak 兜底。）\n\n'
          '确认选的是肥喵记账导出的备份文件吗？\n'
          '新版 .zip 会恢复收据图片；旧版 .db 只恢复账本数据库。',
      confirmText: '确认恢复',
      destructive: true,
    );
    if (!ok) return;

    final lower = path.toLowerCase();
    final bool success;
    try {
      success = lower.endsWith('.zip')
          ? await repo.restoreBackupPackage(path)
          : await repo.restoreDatabaseFromFile(path);
    } on StateError catch (e) {
      // 恢复中途的保护性拦截（如快照完整性校验失败）要说给用户听，
      // 不能静默吞掉让恢复看起来没反应。
      if (context.mounted) {
        showAppToast(context, '恢复失败：${e.message}', icon: Icons.error_outline);
      }
      return;
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, '恢复失败，请重试', icon: Icons.error_outline);
      }
      return;
    }
    if (context.mounted) {
      showAppToast(
        context,
        success ? '恢复成功，建议重启 App 让数据完全刷新' : '恢复失败，已尽力回滚到原数据',
        icon: success ? Icons.check_circle : Icons.error_outline,
      );
    }
  }

  Future<void> _createLocalBackup(BuildContext context) async {
    final repo = context.read<AppRepository>();
    final file = await repo.createLocalBackupNow();
    if (!context.mounted) return;
    showAppToast(
      context,
      file == null ? '备份失败，请稍后重试' : '已创建本机备份',
      icon: file == null ? Icons.error_outline : Icons.check_circle,
    );
    _reloadBackups();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('备份与恢复'),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            icon: Icons.ios_share,
            title: '导出备份',
            desc:
                '导出完整备份包（账本数据库 + 收据图片 + manifest 校验），默认不包含 AI API Key。换手机或手机出问题时用它恢复。',
            buttonText: '导出',
            onTap: () => _export(context),
          ),
          const SizedBox(height: 16),
          _Card(
            icon: Icons.settings_backup_restore,
            title: '从备份恢复',
            desc:
                '选择之前导出的 .zip 完整备份包恢复；也兼容旧 .db/.bak 数据库备份。⚠️ 不可撤销，会替换现在的全部账目（覆盖前自动留一份 .bak）。',
            buttonText: '选择文件恢复',
            danger: true,
            onTap: () => _restore(context),
          ),
          const SizedBox(height: 16),
          // ── 本机备份列表（每周自动 + 升级前自动 + 恢复前兜底）──
          FutureBuilder<List<File>>(
            future: _backups,
            builder: (context, snap) {
              final files = localBackupsForDisplay(
                snap.data ?? const <File>[],
              );
              return Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.card(scheme),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '本机备份',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '喵会自动保留最近 3 份本机备份。点一条即可恢复到那个时间点。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    AppPillButton(
                      label: '立即备份',
                      onPressed: () => _createLocalBackup(context),
                      borderColor: AppColors.hairline(scheme),
                    ),
                    const SizedBox(height: 8),
                    if (files.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '还没有本机备份，点「立即备份」先存一份当前数据。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.68),
                                  ),
                        ),
                      )
                    else
                      for (final f in files)
                        _BackupRow(
                          file: f,
                          onRestore: () => _restoreLocal(context, f),
                        ),
                  ],
                ),
              );
            },
          ),
          Text(
            '说明：完整备份包含账本和收据图片，不包含 AI API Key。建议定期导出一份备份存到网盘，避免换机或丢失手机时账目丢失。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreLocal(BuildContext context, File f) async {
    final repo = context.read<AppRepository>();
    final ok = await showConfirmDialog(
      context,
      title: '恢复到这份备份？',
      message: '当前全部账目将被替换成「${_backupLabel(f)}」时的数据，不可撤销。\n'
          '（覆盖前仍会自动留一份 .bak 兜底。）',
      confirmText: '恢复',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final bool success;
    try {
      success = await repo.restoreDatabaseFromFile(f.path);
    } on StateError catch (e) {
      if (context.mounted) {
        showAppToast(context, '恢复失败：${e.message}', icon: Icons.error_outline);
      }
      if (mounted) _reloadBackups();
      return;
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, '恢复失败，请重试', icon: Icons.error_outline);
      }
      if (mounted) _reloadBackups();
      return;
    }
    if (context.mounted) {
      showAppToast(
        context,
        success ? '恢复成功，建议重启 App 让数据完全刷新' : '恢复失败，已尽力回滚到原数据',
        icon: success ? Icons.check_circle : Icons.error_outline,
      );
    }
    _reloadBackups();
  }
}

/// 备份文件的人话标签：auto-20260703 → 自动备份；pre-v15 → 升级前；.bak → 恢复前兜底。
String _backupLabel(File f) {
  final name = f.uri.pathSegments.last;
  final auto = RegExp(r'auto-(\d{4})(\d{2})(\d{2})').firstMatch(name);
  if (auto != null) {
    return '自动备份 ${auto.group(1)}/${int.parse(auto.group(2)!)}/${int.parse(auto.group(3)!)}';
  }
  final manual = RegExp(r'manual-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})')
      .firstMatch(name);
  if (manual != null) {
    return '手动备份 ${manual.group(1)}/${int.parse(manual.group(2)!)}'
        '/${int.parse(manual.group(3)!)} ${manual.group(4)}:${manual.group(5)}';
  }
  final pre = RegExp(r'pre-v(\d+)').firstMatch(name);
  if (pre != null) return '升级前备份';
  return '恢复前的兜底备份';
}

class _BackupRow extends StatelessWidget {
  final File file;
  final VoidCallback onRestore;

  const _BackupRow({required this.file, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stat = file.statSync();
    final t = stat.modified;
    final sizeMb = (stat.size / 1024 / 1024).toStringAsFixed(1);
    return InkWell(
      onTap: onRestore,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_backupLabel(file),
                      style: const TextStyle(fontSize: 13.5)),
                  Text(
                    '${t.year}/${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} · $sizeMb MB',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(Icons.settings_backup_restore,
                    size: 24, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final String buttonText;
  final bool danger;
  final VoidCallback onTap;

  const _Card({
    required this.icon,
    required this.title,
    required this.desc,
    required this.buttonText,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: danger ? AppColors.warning : scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppPillButton(
              label: buttonText,
              onPressed: onTap,
              foregroundColor: danger ? AppColors.warning : scheme.onSurface,
              borderColor: danger
                  ? AppColors.warning.withValues(alpha: 0.72)
                  : AppColors.hairline(scheme),
            ),
          ),
        ],
      ),
    );
  }
}
