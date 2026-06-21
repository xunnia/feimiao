import 'dart:ui';

import 'package:flutter/material.dart';

/// iOS 风浮动菜单的一项。
class IosMenuItem {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback onTap;

  const IosMenuItem({
    required this.label,
    required this.icon,
    this.destructive = false,
    required this.onTap,
  });
}

const Color _kDestructiveRed = Color(0xFFFF3B30);

/// 弹出 iOS 风浮动菜单：毛玻璃背景 + 连续大圆角 + 发丝分隔，
/// 锚定在被点元素 [anchorContext] 下方、右对齐，带缩放淡入。
///
/// 用法：
/// ```dart
/// Builder(builder: (ctx) => GestureDetector(
///   onTap: () => showIosMenu(ctx, [IosMenuItem(...), ...]),
///   child: Icon(Icons.more_horiz),
/// ))
/// ```
Future<void> showIosMenu(BuildContext anchorContext, List<IosMenuItem> items) {
  final box = anchorContext.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.of(anchorContext).size;
  const menuWidth = 196.0;
  const margin = 8.0;

  // 右对齐到锚点右缘，越界时夹回屏幕内。
  double left = anchor.right - menuWidth;
  if (left < margin) left = margin;
  if (left + menuWidth > screen.width - margin) {
    left = screen.width - margin - menuWidth;
  }
  final top = anchor.bottom + 4;

  return showGeneralDialog<void>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: '菜单',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
                child: _IosMenuCard(items: items, width: menuWidth),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _IosMenuCard extends StatelessWidget {
  final List<IosMenuItem> items;
  final double width;

  const _IosMenuCard({required this.items, required this.width});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: width,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.80),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  _IosMenuRow(item: items[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IosMenuRow extends StatelessWidget {
  final IosMenuItem item;

  const _IosMenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color =
        item.destructive ? _kDestructiveRed : const Color(0xFF1A1A1A);
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.black.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
            Icon(item.icon, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}
