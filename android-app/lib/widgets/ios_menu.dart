import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;

import '../core/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'app_line_icon.dart';
import 'glass.dart';

/// iOS 风浮动菜单的一项。
class IosMenuItem {
  /// 可选：给菜单行挂 Key，方便测试定位（如归档动作行）。
  final Key? key;
  final String label;
  final IconData? icon;
  final AppLineIconData? lineIcon;
  final bool destructive;
  final bool selected;

  /// Optional secondary text (for example a message timestamp). Disabled
  /// rows are rendered as informational headers and do not dismiss the menu.
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const IosMenuItem({
    this.key,
    required this.label,
    this.icon,
    this.lineIcon,
    this.destructive = false,
    this.selected = false,
    this.subtitle,
    this.enabled = true,
    required this.onTap,
  }) : assert(icon != null || lineIcon != null);
}

AppLineIconData? _standardLineIcon(IconData? icon) {
  if (icon == Icons.copy_outlined ||
      icon == Icons.copy_all_outlined ||
      icon == CupertinoIcons.doc_on_doc) {
    return AppLineIcons.copy;
  }
  if (icon == Icons.edit_outlined ||
      icon == Icons.drive_file_rename_outline ||
      icon == CupertinoIcons.pencil) {
    return AppLineIcons.pencil;
  }
  if (icon == Icons.delete_outline ||
      icon == Icons.delete_forever_outlined ||
      icon == Icons.delete_sweep_outlined ||
      icon == CupertinoIcons.delete) {
    return AppLineIcons.trash;
  }
  if (icon == Icons.star_outline ||
      icon == Icons.star ||
      icon == CupertinoIcons.star ||
      icon == CupertinoIcons.star_fill) {
    return AppLineIcons.star;
  }
  return null;
}

/// Shared neutral scrim for compact option menus and anchored AI selectors.
///
/// The highlighted anchor is cut out of the scrim instead of being copied into
/// the overlay. That keeps the real control in its original position while the
/// rest of the page recedes, matching the Claude/iOS long-press interaction.
class AppMenuScrim extends StatelessWidget {
  final Rect highlightRect;
  final double radius;

  const AppMenuScrim({
    super.key,
    required this.highlightRect,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: ClipPath(
        key: const ValueKey('unified-ios-menu-scrim'),
        clipper: _MenuScrimClipper(
          highlightRect: highlightRect,
          radius: radius,
        ),
        child: ColoredBox(
          // Keep the underlying page recognizable. A neutral black scrim is
          // less muddy than tinting the whole page blue-gray and matches the
          // iOS/Claude option sheets where secondary content only recedes.
          color: Colors.black.withValues(alpha: dark ? 0.42 : 0.18),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MenuScrimClipper extends CustomClipper<Path> {
  final Rect highlightRect;
  final double radius;

  const _MenuScrimClipper({
    required this.highlightRect,
    required this.radius,
  });

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(
      RRect.fromRectAndRadius(highlightRect, Radius.circular(radius)),
    );

  @override
  bool shouldReclip(covariant _MenuScrimClipper oldDelegate) =>
      oldDelegate.highlightRect != highlightRect ||
      oldDelegate.radius != radius;
}

/// 弹出 iOS 风浮动菜单：毛玻璃背景 + 连续大圆角，
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
  Key? cardKey,
  bool alignToAnchorTop = false,
}) {
  final box = anchorContext.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  final screen = _viewportSize(anchorContext);
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
  final estHeight = items.length * 44.0 + 8;
  final maxHeight = math.min(estHeight, screen.height - margin * 2).toDouble();
  double top = alignToAnchorTop ? anchor.top : anchor.bottom + 4;
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
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: anim,
              child: AppMenuScrim(
                highlightRect: anchor.inflate(1.5),
                radius: math.min(18, anchor.shortestSide / 2 + 4),
              ),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                alignment: growUp ? Alignment.bottomRight : Alignment.topRight,
                scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
                child: cardKey == null
                    ? _IosMenuCard(
                        key: const ValueKey('unified-ios-menu-card'),
                        items: items,
                        width: menuWidth,
                        maxHeight: maxHeight,
                      )
                    : KeyedSubtree(
                        key: cardKey,
                        child: _IosMenuCard(
                          key: const ValueKey('unified-ios-menu-card'),
                          items: items,
                          width: menuWidth,
                          maxHeight: maxHeight,
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Size _viewportSize(BuildContext context) {
  final renderViews = RendererBinding.instance.renderViews;
  if (renderViews.isNotEmpty) return renderViews.first.size;
  final view = View.of(context);
  return Size(
    view.physicalSize.width / view.devicePixelRatio,
    view.physicalSize.height / view.devicePixelRatio,
  );
}

class _IosMenuCard extends StatelessWidget {
  final List<IosMenuItem> items;
  final double width;
  final double maxHeight;

  const _IosMenuCard({
    super.key,
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: GlassSurface(
            radius: 20,
            blur: 10,
            opacity: 0.94,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    _IosMenuRow(key: item.key, item: item),
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
    final lineIcon = item.lineIcon ?? _standardLineIcon(item.icon);
    // 文字跟随主题（深色模式下之前的硬编码深灰会看不清）。
    final color = item.destructive
        ? AppColors.warning
        : item.enabled
            ? scheme.onSurface
            : scheme.onSurfaceVariant.withValues(alpha: 0.62);
    return InkWell(
      onTap: !item.enabled
          ? null
          : () {
              Haptics.selection();
              Navigator.of(context).pop();
              item.onTap();
            },
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(13),
      highlightColor: scheme.onSurface.withValues(alpha: 0.055),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: item.selected
              ? scheme.onSurface.withValues(alpha: 0.065)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          // 对齐 Claude：图标在前、名称在后。
          child: Row(
            children: [
              if (item.selected)
                SizedBox(
                  key: ValueKey('chat-filter-check-${item.label}'),
                  width: 8,
                  height: 1,
                ),
              if (lineIcon != null)
                AppLineIcon(lineIcon, size: 20, color: color)
              else
                Icon(item.icon, size: 19, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: item.subtitle == null
                    ? Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.menuItem(color),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.menuItem(color),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.menuSubtitle(
                              scheme.onSurfaceVariant.withValues(
                                alpha: item.enabled ? 0.72 : 0.58,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (item.selected) ...[
                const SizedBox(width: 10),
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
