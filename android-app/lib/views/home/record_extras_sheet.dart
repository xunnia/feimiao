import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;

import '../../widgets/settings_ui.dart';
import '../quick_add/screenshot_entry.dart';
import '../settings/import_export_view.dart';

/// 「更多功能」底部面板：支付截图识别 / 导入账单 / 导出账单。
/// 首页输入栏与 AI 面板的 [+] 共用，保证两处行为一致。
void showRecordExtrasSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: '更多功能', onClose: () => Navigator.pop(ctx)),
          SettingsGroup(
            children: [
              SettingsRow(
                leading: const Icon(Icons.image_outlined),
                title: '支付截图识别',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  recognizeScreenshotAndEntry(context);
                },
              ),
              SettingsRow(
                leading: const Icon(Icons.upload_file_outlined),
                title: '导入账单',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const ImportExportView(),
                    ),
                  );
                },
              ),
              SettingsRow(
                leading: const Icon(Icons.download_outlined),
                title: '导出账单',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const ImportExportView(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
