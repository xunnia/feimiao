import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// iOS 风输入框样式：圆角 + 浅灰填充 + 无边框（systemGray6 观感）。
/// 给表单里的 TextField 套用：`decoration: iosInputDecoration(context, hint: '…')`。
/// 需要 context 取主题：深色模式下填充用暖灰，不再是刺眼的浅灰。
InputDecoration iosInputDecoration(BuildContext context,
    {String? hint, String? prefix}) {
  const radius = 12.0;
  final scheme = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    // 提示文字调小调浅：不抢眼，只做轻提示。
    hintStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
    ),
    prefixText: prefix,
    filled: true,
    fillColor: AppColors.inputFill(scheme),
    isDense: true,
    counterText: '',
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    ),
  );
}

/// 弹出 iOS 风表单弹窗（对齐 Claude 的 Rename 弹窗）：
/// 居中圆角卡 + 左对齐标题/灰色副标题 + 自定义内容 + 底部两颗灰胶囊按钮。
/// 返回 true=点了保存/确认，false=取消或点外部关闭。
Future<bool> showIosFormDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget content,
  String confirmText = '保存',
  String cancelText = '取消',
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
          child: Padding(
            // 跟随键盘上移
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Center(
              child: _IosFormCard(
                title: title,
                subtitle: subtitle,
                content: content,
                confirmText: confirmText,
                cancelText: cancelText,
              ),
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _IosFormCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final String confirmText;
  final String cancelText;

  const _IosFormCard({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.confirmText,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxW = MediaQuery.of(context).size.width - 56;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW > 360 ? 360 : maxW),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.hairline(scheme)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题左对齐（对齐 Claude），副标题灰色小字。
              Text(
                title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: content,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _FormButton(
                      label: cancelText,
                      emphasis: false,
                      onTap: () => Navigator.of(context).pop(false),
                      scheme: scheme,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FormButton(
                      label: confirmText,
                      emphasis: true,
                      onTap: () => Navigator.of(context).pop(true),
                      scheme: scheme,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormButton extends StatelessWidget {
  final String label;
  final bool emphasis;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _FormButton({
    required this.label,
    required this.emphasis,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    // 对齐 Claude：两颗都是浅灰胶囊，确认键用深色字加粗区分。
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.inputFill(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline(scheme, strength: 0.8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
