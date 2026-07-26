import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass.dart';

/// iOS 风浮动菜单的一项。
class IosMenuItem {
  /// 可选：给菜单行挂 Key，方便测试定位（如归档动作行）。
  final Key? key;
  final String label;
  final IconData icon;
  final bool destructive;
  final bool selected;
  final VoidCallback onTap;

  const IosMenuItem({
    this.key,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.selected = false,
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
Future<void> showIosMenu(
  BuildContext anchorContext,
  List<IosMenuItem> items, {
  double? width,
  bool alignToAnchorLeft = false,
}) {
  final box = anchorContext.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.of(anchorContext).size;
  final menuWidth = width ?? 196.0;
  const margin = 8.0;

  // 右对齐到锚点右缘，越界时夹回屏幕内。
  double left = anchor.right - menuWidth;
  if (alignToAnchorLeft) left = anchor.left;
  if (left < margin) left = margin;
  if (left + menuWidth > screen.width - margin) {
    left = screen.width - margin - menuWidth;
  }
  // 默认弹在锚点下方；下方放不下（锚点靠近屏底，如记账卡芯片）就翻到上方。
  final estHeight = items.length * 45.0 + 4;
  final maxHeight = math.min(estHeight, screen.height - margin * 2).toDouble();
  double top = anchor.bottom + 4;
  var growUp = false;
  if (top + estHeight > screen.height - margin) {
    top = (anchor.top - 4 - maxHeight)
        .clamp(margin, screen.height - margin)
        .toDouble();
    growUp = true;
  }

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
                alignment: growUp ? Alignment.bottomRight : Alignment.topRight,
                scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
                child: _IosMenuCard(
                  items: items,
                  width: menuWidth,
                  maxHeight: maxHeight,
                ),
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
  final double maxHeight;

  const _IosMenuCard({
    required this.items,
    required this.width,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: GlassSurface(
            radius: 15,
            blur: 8,
            opacity: 0.55,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 0.5,
                        color: AppColors.hairline(Theme.of(context).colorScheme,
                            strength: 1.3),
                      ),
                    _IosMenuRow(key: items[i].key, item: items[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IosMenuRow extends StatelessWidget {
  final IosMenuItem item;

  const _IosMenuRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 文字跟随主题（深色模式下之前的硬编码深灰会看不清）。
    final color = item.destructive ? _kDestructiveRed : scheme.onSurface;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppColors.hairline(scheme),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // 对齐 Claude：图标在前、名称在后。
        child: Row(
          children: [
            Icon(item.icon, size: 19, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (item.selected) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_rounded, size: 18, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
