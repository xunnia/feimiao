import 'package:flutter/material.dart';

/// iOS 风输入框样式：圆角 + 浅灰填充 + 无边框（systemGray6 观感）。
/// 给表单里的 TextField 套用：`decoration: iosInputDecoration(hint: '…')`。
InputDecoration iosInputDecoration({String? hint, String? prefix}) {
  const radius = 12.0;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    prefixText: prefix,
    filled: true,
    fillColor: const Color(0xFFF2F2F7), // iOS systemGray6
    isDense: true,
    counterText: '',
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: Color(0xFF7D8B9B), width: 1.4),
    ),
  );
}

/// 弹出 iOS 风表单弹窗：居中圆角卡 + 标题 + 自定义内容 + 取消/保存。
/// 返回 true=点了保存/确认，false=取消或点外部关闭。
Future<bool> showIosFormDialog(
  BuildContext context, {
  required String title,
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
  final Widget content;
  final String confirmText;
  final String cancelText;

  const _IosFormCard({
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxW = MediaQuery.of(context).size.width - 56;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW > 360 ? 360 : maxW),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
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
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
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
                      filled: false,
                      onTap: () => Navigator.of(context).pop(false),
                      scheme: scheme,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FormButton(
                      label: confirmText,
                      filled: true,
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
  final bool filled;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _FormButton({
    required this.label,
    required this.filled,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? scheme.primary : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
