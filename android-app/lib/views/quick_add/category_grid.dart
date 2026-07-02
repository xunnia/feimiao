import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/category_seed.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../data/app_repository.dart';

/// 子类横排 chip（旧版，编辑页仍在用；手动卡已改为咔皮式展开面板）。
class SubcategoryRow extends StatelessWidget {
  final List<CategoryEntity> children;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;

  const SubcategoryRow({
    super.key,
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in children)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(c);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
                decoration: BoxDecoration(
                  color: selectedId == c.id
                      ? scheme.primary.withValues(alpha: 0.14)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: selectedId == c.id
                      ? Border.all(color: scheme.primary, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CatIcon(
                      categoryKey: c.key,
                      emoji: CategorySeed.emojiOf(c.key),
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.nameZh,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selectedId == c.id
                                ? scheme.primary
                                : scheme.onSurface,
                            fontWeight: selectedId == c.id
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分类网格（5 列）。自有 iOS 风方块图标；选中=主色描边环。
///
/// [expandableIds] 里的大类会在右下角显示 ▼ 提示（有子类可展开）；
/// [expandedId] 为当前已展开的大类，其 ▼ 翻转为 ▲。
class CategoryGrid extends StatelessWidget {
  final List<CategoryEntity> categories;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;
  final Set<int> expandableIds;
  final int? expandedId;

  /// 大类 id -> 已选中的二级分类名：显示成「大类·二级」（缩略）。
  final Map<int, String> subLabels;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.expandableIds = const <int>{},
    this.expandedId,
    this.subLabels = const <int, String>{},
  });

  static const int _columns = 5;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return _CategoryItem(
          category: cat,
          isSelected: cat.id == selectedId,
          showChevron: expandableIds.contains(cat.id),
          expanded: cat.id == expandedId,
          subLabel: subLabels[cat.id],
          scheme: scheme,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected(cat);
          },
        );
      },
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final CategoryEntity category;
  final bool isSelected;
  final bool showChevron;
  final bool expanded;
  final String? subLabel;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.category,
    required this.isSelected,
    required this.showChevron,
    required this.expanded,
    this.subLabel,
    required this.scheme,
    required this.onTap,
  });

  String get _emoji {
    final seed = CategorySeed.all.where((s) => s.key == category.key).firstOrNull;
    return seed?.emoji ?? '🏷️';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 方块图标 + 选中描边环 + 右下角 ▼
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CatIcon(
                  categoryKey: category.key,
                  emoji: _emoji,
                  size: 44,
                ),
              ),
              if (showChevron)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: scheme.outlineVariant, width: 0.5),
                    ),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 选中=加粗但保持黑色（不变蓝）；选了二级时后缀「·二级名」缩略显示。
          Text(
            subLabel == null ? category.nameZh : '${category.nameZh}·$subLabel',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: subLabel == null ? null : 10,
                  color:
                      isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
