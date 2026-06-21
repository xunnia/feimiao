import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;

import '../quick_add/screenshot_entry.dart';
import '../settings/import_export_view.dart';

/// 「更多功能」底部面板：支付截图识别 / 导入账单 / 导出账单。
/// 首页输入栏与 AI 面板的 [+] 共用，保证两处行为一致。
void showRecordExtrasSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '更多功能',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _ExtrasItem(
            icon: Icons.image_outlined,
            label: '支付截图识别',
            onTap: () {
              Navigator.pop(ctx);
              recognizeScreenshotAndEntry(context);
            },
          ),
          _ExtrasItem(
            icon: Icons.upload_file_outlined,
            label: '导入账单',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const ImportExportView(),
                ),
              );
            },
          ),
          _ExtrasItem(
            icon: Icons.download_outlined,
            label: '导出账单',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const ImportExportView(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class _ExtrasItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExtrasItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
      title: Text(label),
      trailing: Icon(CupertinoIcons.chevron_forward, size: 20, color: scheme.outline),
      onTap: onTap,
    );
  }
}
