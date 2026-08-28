import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 确认弹窗（2026-07-10 二轮对齐 iOS Cloudflare 客户端原图，用户逐条点名）：
/// 磨砂卡（透色不透字）+ 发丝细边 + 标题/正文左对齐（16/w500 + 灰正文）
/// + 底部两颗灰底等宽胶囊（文字主色 w500、危险=超支橙，守不用红铁律）。
///
/// 返回 true = 确认，false/取消/点外部 = false。全 App 的删除/确认都走它。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
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
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: Center(
            child: _ConfirmCard(
              title: title,
              message: message,
              confirmText: confirmText,
              cancelText: cancelText,
              destructive: destructive,
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// 使用统一毛玻璃外壳展示阻塞或自定义内容。
/// 与 [showConfirmDialog] 共用遮罩和入场动效，避免页面再直接调用
/// Material 的 AlertDialog/showDialog。
Future<T?> showFrostedDialog<T>(
  BuildContext context, {
  required Widget child,
  bool barrierDismissible = true,
  String barrierLabel = '关闭',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (ctx, anim, _, page) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: page,
        ),
      );
    },
  );
}

/// 磨砂弹窗卡（图二 Cloudflare 风）：背景高斯模糊——只透出底下的颜色、
/// 看不清文字；半透明白/暖灰 tint + 发丝细边 + 大圆角 + 落影。
/// 全 App 的中心弹窗一律套它，别再手写 Container+纯色/半透明底。
/// （弹窗是瞬态浮层，这一处 BackdropFilter 不违反常驻模糊的性能铁律。）
class FrostedDialogCard extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  const FrostedDialogCard({
    super.key,
    required this.child,
    this.maxWidth = 320,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 18),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width - 64;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: screenW > maxWidth ? maxWidth : screenW),
        child: DecoratedBox(
          // 影子画在裁剪外面，不然被 ClipRRect 剪掉。
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF332F2C).withValues(alpha: 0.84)
                      : Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.hairline(scheme)),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗正文的灰色（图二那种明确的中灰，别用 M3 的 onSurfaceVariant——
/// 它是深灰紫，看着跟黑字没区别）。
Color dialogBodyColor(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.55);

/// 弹窗胶囊按钮：灰底 + 主色文字 w500（危险传 AppColors.warning）。
class DialogPillButton extends StatelessWidget {
  final String label;
  final Color? foreground;
  final VoidCallback onTap;
  final double height;

  const DialogPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.foreground,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 明确的灰底（图二），不是白底：浅色黑 7%、深色白 12%。
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.action(scheme).copyWith(
            fontWeight: FontWeight.w500,
            color: foreground ?? scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  final String title;
  final String? message;
  final String confirmText;
  final String cancelText;
  final bool destructive;

  const _ConfirmCard({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    required this.destructive,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FrostedDialogCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图二（Cloudflare iOS）规格：标题 16/w500 左对齐。
          Text(
            title,
            textAlign: TextAlign.start,
            style: AppType.sheetTitle(scheme).copyWith(fontSize: 16),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              textAlign: TextAlign.start,
              style: AppType.secondary(scheme).copyWith(
                fontSize: 14,
                height: 1.55,
                color: dialogBodyColor(scheme),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DialogPillButton(
                  label: cancelText,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DialogPillButton(
                  label: confirmText,
                  foreground: destructive ? AppColors.warning : null,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
