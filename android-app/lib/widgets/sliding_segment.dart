import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 分段切换（全 App 统一用它，别再各写各的）。
/// 2026-07-09 视觉升级批对齐参考图（iOS Cloudflare 客户端）：
/// 外层**灰底**胶囊（不再白底描边，太显眼），选中项=**白色滑块**平滑滑动，
/// 文字不加粗、只靠白滑块区分选中态。
class SlidingSegment<T> extends StatelessWidget {
  /// (值, 文案) 列表，等宽平分可用宽度。
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  const SlidingSegment({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final index =
        items.indexWhere((e) => e.$1 == value).clamp(0, items.length - 1);

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // 底轨跟主题走：暖橙出暖灰、简约白出中性灰（2026-10-01，原来一律冷黑透明）。
        color: AppColors.segmentTrack(scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / items.length;
          return Stack(
            children: [
              // 滑动的选中滑块：半透明白（实心白在半透明卡上太突兀，用户点名）
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: index * itemW,
                top: 0,
                bottom: 0,
                width: itemW,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF4A4540).withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (v, label) in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(v),
                        child: Center(
                          child: Text(
                            label,
                            // iOS 分段控件：选中项半粗、未选中略淡。
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: v == value
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: v == value
                                  ? scheme.onSurface
                                  : scheme.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
