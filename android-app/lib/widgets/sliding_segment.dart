import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Telegram 聊天文件夹式分段切换（全 App 统一用它，别再各写各的）：
/// 外层白色大胶囊（细边+淡影），里面一颗浅灰小胶囊**平滑滑动**到选中项，
/// 文字粗细渐变过渡——不是两边各自变色的"闪烁"效果。
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
    final index = items.indexWhere((e) => e.$1 == value).clamp(0, items.length - 1);

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline(scheme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / items.length;
          return Stack(
            children: [
              // 滑动的选中小胶囊
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: index * itemW,
                top: 0,
                bottom: 0,
                width: itemW,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
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
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface,
                              fontWeight: v == value
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            child: Text(label),
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
