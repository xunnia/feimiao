import 'package:flutter/material.dart';

/// iOS 风底部弹层「抓手」：顶部居中一条小圆条，暗示可下拉关闭。
///
/// 放在 sheet 内容最顶端即可。各弹层共用同一外观，保持一致。
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
