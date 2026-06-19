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
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => child,
  );
}
