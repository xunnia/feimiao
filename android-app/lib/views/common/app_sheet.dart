import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 统一的底部弹层外观：圆角顶 + 可滚动撑高 + surface 底色。
///
/// 各处弹层都走它，避免重复抄样式。用法：
/// ```dart
/// await appSheet<void>(context, child: const SomeSheet());
/// ```
Future<T?> appSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    // 弹层撑满时顶部必须让出状态栏（真机键盘顶起后会怼进状态栏）。
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => child,
  );
}

/// 可拖拽内容专用的统一弹层入口。
/// [DraggableScrollableSheet] 需要由 ModalBottomSheet 提供有界的高度，
/// 因此不能直接塞进 [showBlurSheet]；所有此类页面仍通过这个入口收口
/// 遮罩、系统安全区和透明背景，页面内部只负责拖拽内容。
Future<T?> showDraggableAppSheet<T>(
  BuildContext context, {
  required Widget child,
  double barrierOpacity = 0.18,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: barrierOpacity.clamp(0, 1)),
    builder: (_) => child,
  );
}

/// 重量级底部弹层（与手动记账/AI 面板同一套出场）：
/// 背景高斯模糊渐入 + 浮层上滑淡入 + 键盘弹起时整卡上移。
/// 「同类功能同一种设计」——新的大弹层一律用它。
Future<T?> showBlurSheet<T>(
  BuildContext context, {
  required Widget child,
  EdgeInsets inset = EdgeInsets.zero,
  double radius = 24,

  /// Claude's attachment sheet dims the conversation without applying a
  /// backdrop blur. Other heavyweight forms keep the original blurred entry.
  bool blurBackground = true,
  double barrierOpacity = 0.12,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: barrierOpacity.clamp(0, 1)),
    transitionDuration: const Duration(milliseconds: 240),
    // 顶部安全区必须开：键盘把弹层顶到屏幕顶时，头部不许进状态栏
    // （SafeArea 会把已消费的 top padding 从子树 MediaQuery 移除，
    // 各弹层内部自带的 SafeArea 不会二次垫高）。
    pageBuilder: (ctx, _, __) => SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Padding(
          padding: inset,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: (MediaQuery.sizeOf(ctx).width - inset.horizontal)
                  .clamp(0, double.infinity),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Material(
                  color: Theme.of(ctx).colorScheme.surface,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final transition = FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
      if (!blurBackground) return transition;
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10 * anim.value,
          sigmaY: 10 * anim.value,
        ),
        child: transition,
      );
    },
  );
}
