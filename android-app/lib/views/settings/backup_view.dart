import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../widgets/ios_dialogs.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_repository.dart';

/// 本地备份 / 恢复（不涉及云）：
/// - 导出：把整个账本数据库文件分享出去（存到微信/网盘/邮件/本地皆可）。
/// - 恢复：从一个备份文件覆盖当前数据（不可撤销，覆盖前自动留 .bak 兜底）。
class BackupView extends StatelessWidget {
  const BackupView({super.key});

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<AppRepository>();
    try {
      final path = await repo.databaseFilePath();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await Share.shareXFiles(
        [XFile(path, name: 'qingji-backup-$stamp.db')],
        text: '轻记账本备份（$stamp）',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('导出失败，请重试')),
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<AppRepository>();

    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (!context.mounted) return;
    final path =
        (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
    if (path == null) return;

    final ok = await showConfirmDialog(
      context,
      title: '从备份恢复？',
      message: '将用所选文件覆盖当前全部账目数据，且不可撤销。\n'
          '（系统会在覆盖前自动保留一份 .bak 兜底。）\n\n'
          '确认选的是轻记导出的备份文件吗？',
      confirmText: '确认恢复',
      destructive: true,
    );
    if (!ok) return;

    final success = await repo.restoreDatabaseFromFile(path);
    messenger.showSnackBar(
      SnackBar(
        content: Text(success
            ? '恢复成功，建议重启 App 让数据完全刷新'
            : '恢复失败，已尽力回滚到原数据'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            icon: Icons.ios_share,
            title: '导出备份',
            desc: '把整个账本导出成一个文件，分享/保存到微信、网盘、邮件或本地都行。换手机或手机出问题时用它恢复。',
            buttonText: '导出',
            onTap: () => _export(context),
          ),
          const SizedBox(height: 16),
          _Card(
            icon: Icons.settings_backup_restore,
            title: '从备份恢复',
            desc: '选一个之前导出的备份文件，覆盖当前数据。⚠️ 不可撤销，会替换现在的全部账目（覆盖前自动留一份 .bak）。',
            buttonText: '选择文件恢复',
            danger: true,
            onTap: () => _restore(context),
          ),
          const SizedBox(height: 16),
          Text(
            '说明：轻记是纯本地 App，数据只在你手机上。建议定期导出一份备份存到网盘，避免换机或丢失手机时账目丢失。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
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
        color: Colors.white,
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
              Icon(icon, color: danger ? scheme.error : scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w500),
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
          SizedBox(
            width: double.infinity,
            child: danger
                ? OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                    child: Text(buttonText),
                  )
                : FilledButton(
                    onPressed: onTap,
                    child: Text(buttonText),
                  ),
          ),
        ],
      ),
    );
  }
}
