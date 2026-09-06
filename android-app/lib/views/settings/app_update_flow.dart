import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../core/update/app_update.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

/// 检查更新流程（设置页手动触发 / 启动静默检查共用）。
/// [silent] = 启动静默模式：没更新或网络失败都不打扰用户。
///
/// 下载走系统 DownloadManager（切后台/锁屏/杀进程都继续，通知栏自带进度）；
/// 弹窗只是进度镜子，点「后台下载」关掉它下载照跑。冷启动能接上
/// 「下载完但还没装」的包，直接校验安装不重下。个别 ROM 禁用下载管理器时
/// 回退老的进程内下载。
Future<void> checkAppUpdate(BuildContext context, {bool silent = false}) async {
  await AppUpdate.cleanupObsoletePendingDownload();
  final info = await AppUpdate.check();
  if (!context.mounted) return;
  if (info == null) {
    if (!silent) showAppToast(context, '已是最新版本');
    return;
  }

  // 先看有没有挂起的同版本系统下载（比如上次切后台，系统已默默下完）。
  var pending = await AppUpdate.pendingDownload();
  if (!context.mounted) return;
  if (pending != null && pending.versionCode != info.versionCode) {
    await AppUpdate.discardPendingDownload(pending);
    pending = null;
    if (!context.mounted) return;
  }
  if (pending != null && pending.versionCode == info.versionCode) {
    final st = await AppUpdate.queryDownload(pending.id);
    if (!context.mounted) return;
    if (st != null && st.status == 'successful') {
      final ok = await showConfirmDialog(
        context,
        title: '新版本已下载好',
        message: 'v${info.versionName} 已在后台下载完成，现在安装？',
        confirmText: '安装',
        cancelText: '暂不',
      );
      if (!ok || !context.mounted) return;
      await _verifyAndInstall(context, info, pending.path);
      return;
    }
    if (st != null && !st.isTerminal) {
      // 还在下：不再入队新的，直接接上进度。
      await _watchDownload(context, info, pending.id);
      return;
    }
    // failed/missing：清掉重来。
    await AppUpdate.clearPendingDownload();
    if (!context.mounted) return;
  }

  final sizePart = info.sizeText.isEmpty ? '' : '（${info.sizeText}）';
  final notes = info.notes.trim();
  final ok = await showConfirmDialog(
    context,
    title: '发现新版本 v${info.versionName}',
    message: '${notes.isEmpty ? '修复问题并改进体验。' : notes}\n\n'
        '将下载安装包$sizePart，可切后台继续下载。',
    confirmText: '下载更新',
    cancelText: '暂不',
  );
  if (!ok || !context.mounted) return;

  final id = await AppUpdate.startBackgroundDownload(info);
  if (!context.mounted) return;
  if (id == null) {
    // 系统下载管理器不可用（个别 ROM 会禁用）：退回进程内下载。
    await _foregroundDownloadAndInstall(context, info);
    return;
  }
  await _watchDownload(context, info, id);
}

/// Open the historical-build picker.  A rollback entry is only actionable
/// when its install sequence is newer than the package currently installed;
/// this keeps the system installer from receiving an APK it must reject as a
/// downgrade.  Historical source versions are displayed separately from that
/// install sequence so the UI remains understandable.
Future<void> showRollbackCatalog(BuildContext context) async {
  final installedCode = await AppUpdate.installedVersionCode();
  final entries = await AppUpdate.fetchRollbackCatalog();
  if (!context.mounted) return;
  final selected = await showBlurSheet<AppRollbackInfo>(
    context,
    child: _RollbackSheet(
      installedVersionCode: installedCode,
      entries: entries,
    ),
  );
  if (selected == null || !context.mounted) return;
  await _downloadAndInstallRollback(context, selected);
}

class _RollbackSheet extends StatelessWidget {
  final int installedVersionCode;
  final List<AppRollbackInfo> entries;

  const _RollbackSheet({
    required this.installedVersionCode,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...entries]
      ..sort((a, b) => b.sourceVersionCode.compareTo(a.sourceVersionCode));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '历史版本',
            subtitle: '选择经过签名校验的版本；安装前建议先备份账本',
            onClose: () => Navigator.of(context).pop(),
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 34),
              child: Text(
                '暂时没有可用的历史版本',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SettingsGroup(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    for (final entry in sorted)
                      _RollbackRow(
                        entry: entry,
                        installedVersionCode: installedVersionCode,
                        onTap: entry.installVersionCode > installedVersionCode
                            ? () => Navigator.of(context).pop(entry)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RollbackRow extends StatelessWidget {
  final AppRollbackInfo entry;
  final int installedVersionCode;
  final VoidCallback? onTap;

  const _RollbackRow({
    required this.entry,
    required this.installedVersionCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = onTap != null;
    final suffix = available
        ? '可安装'
        : entry.installVersionCode == installedVersionCode
            ? '当前版本'
            : '需重新生成兼容包';
    return SettingsRow(
      leading: const Icon(CupertinoIcons.arrow_counterclockwise),
      title: 'v${entry.versionName}',
      titleColor:
          available ? null : scheme.onSurfaceVariant.withValues(alpha: 0.58),
      subtitle:
          '$suffix · 安装序号 ${entry.installVersionCode} · 原版本 ${entry.sourceVersionCode}',
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 18,
        color:
            scheme.onSurfaceVariant.withValues(alpha: available ? 0.82 : 0.36),
      ),
      onTap: onTap,
    );
  }
}

Future<void> _downloadAndInstallRollback(
  BuildContext context,
  AppRollbackInfo entry,
) async {
  final installedCode = await AppUpdate.installedVersionCode();
  if (!context.mounted) return;
  if (entry.installVersionCode <= installedCode) {
    showAppToast(
      context,
      '这个回退包的安装序号不高于当前版本，系统不会允许覆盖',
      icon: Icons.info_outline,
    );
    return;
  }
  final confirmed = await showConfirmDialog(
    context,
    title: '安装历史版本？',
    message: '将安装 v${entry.versionName}。账本数据会保留，但旧代码必须兼容当前数据库；建议先导出备份。',
    confirmText: '下载并安装',
    cancelText: '取消',
  );
  if (!confirmed || !context.mounted) return;
  final info = entry.installInfo;
  await _foregroundDownloadAndInstall(context, info);
}

/// 轮询系统下载进度并镜像到弹窗；「后台下载」只关弹窗不停下载。
/// 只要 App 还活着，下载完成就自动接校验+安装；App 被杀则由下次
/// checkAppUpdate 的挂起分支接续。
Future<void> _watchDownload(
  BuildContext context,
  AppUpdateInfo info,
  int downloadId,
) async {
  final progress = ValueNotifier<double>(0);
  var dialogOpen = false;

  void closeDialog() {
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  dialogOpen = true;
  _showProgressDialog(
    context,
    info: info,
    progress: progress,
    onBackground: () {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
      showAppToast(context, '已转入后台下载，可在通知栏看进度');
    },
  );

  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return; // App 侧退出：系统下载自己继续
    final st = await AppUpdate.queryDownload(downloadId);
    if (st == null) continue; // 偶发通道抖动，下一轮再查
    if (st.status == 'successful') {
      closeDialog();
      // App 在后台时不拉安装器（Android 拦后台起 Activity，白拉还会清掉
      // 挂起记录导致重下）；留着记录，用户回来后走「已下载好」分支安装。
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final pending = await AppUpdate.pendingDownload();
      if (!context.mounted) return;
      final path = pending?.path ?? '';
      await _verifyAndInstall(context, info, path);
      return;
    }
    if (st.status == 'failed' || st.status == 'missing') {
      closeDialog();
      await AppUpdate.clearPendingDownload();
      if (context.mounted) {
        showAppToast(context, '下载失败，请稍后重试', icon: Icons.error_outline);
      }
      return;
    }
    progress.value = st.progress;
  }
}

/// 校验 SHA256 后拉起安装器；校验失败删包清记录（防装坏包）。
Future<void> _verifyAndInstall(
  BuildContext context,
  AppUpdateInfo info,
  String path,
) async {
  if (path.isEmpty || !await File(path).exists()) {
    await AppUpdate.clearPendingDownload();
    if (context.mounted) {
      showAppToast(context, '安装包不见了，请重新下载', icon: Icons.error_outline);
    }
    return;
  }
  final okHash = await AppUpdate.verifyFileSha256(path, info.sha256);
  if (!okHash) {
    try {
      await File(path).delete();
    } catch (_) {}
    await AppUpdate.clearPendingDownload();
    if (context.mounted) {
      showAppToast(context, '安装包校验失败，请重新下载', icon: Icons.error_outline);
    }
    return;
  }
  final launched = await AppUpdate.install(File(path));
  if (launched) {
    // 交给安装器了，挂起记录使命完成（装没装成由系统接管）。
    await AppUpdate.clearPendingDownload();
  } else if (context.mounted) {
    showAppToast(context, '拉起安装器失败，请重试', icon: Icons.error_outline);
  }
}

/// 兜底：老的进程内流式下载（DownloadManager 不可用时才走到这）。
Future<void> _foregroundDownloadAndInstall(
  BuildContext context,
  AppUpdateInfo info,
) async {
  final progress = ValueNotifier<double>(0);
  var dialogOpen = true;
  _showProgressDialog(context, info: info, progress: progress);

  void closeDialog() {
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  try {
    final file = await AppUpdate.download(
      info,
      onProgress: (v) => progress.value = v,
    );
    closeDialog();
    final launched = await AppUpdate.install(file);
    if (!launched && context.mounted) {
      showAppToast(context, '拉起安装器失败，请重试', icon: Icons.error_outline);
    }
  } catch (e) {
    closeDialog();
    if (context.mounted) {
      showAppToast(context, '下载失败，请稍后重试', icon: Icons.error_outline);
    }
  }
}

/// 下载进度弹窗（图二风格：大圆角卡、左对齐、浅底胶囊按钮）。
/// [onBackground] 非空时显示「后台下载」按钮。
void _showProgressDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required ValueNotifier<double> progress,
  VoidCallback? onBackground,
}) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '下载中',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final scheme = Theme.of(ctx).colorScheme;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: Center(
            // 磨砂卡+发丝边+灰底胶囊：走全局弹窗零件，和确认弹窗一张皮。
            child: FrostedDialogCard(
              maxWidth: 300,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在下载 v${info.versionName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    onBackground != null
                        ? '切后台也会继续下载，完成后回到肥喵即可安装'
                        : '下载完成后会自动跳转安装',
                    style: TextStyle(
                      fontSize: 13,
                      color: dialogBodyColor(scheme),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (_, v, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: v > 0 ? v : null,
                            minHeight: 8,
                            color: scheme.primary,
                            backgroundColor: AppColors.inputFill(scheme),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          v > 0 ? '${(v * 100).toStringAsFixed(0)}%' : '连接中…',
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'Nunito',
                            color: dialogBodyColor(scheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onBackground != null) ...[
                    const SizedBox(height: 18),
                    DialogPillButton(
                      label: '后台下载',
                      onTap: onBackground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
