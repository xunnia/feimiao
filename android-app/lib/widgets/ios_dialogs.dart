import 'package:flutter/cupertino.dart';

/// iOS 风确认弹窗（居中圆角 + 横排按钮，危险操作红字）。
///
/// 返回 true = 确认，false/取消 = false。全 App 的删除/确认都走它，
/// 保持一致的 iOS 观感。
///
/// 用法：
/// ```dart
/// final ok = await showConfirmDialog(context,
///     title: '删除这笔账？', confirmText: '删除', destructive: true);
/// if (ok) { ... }
/// ```
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message),
            ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
