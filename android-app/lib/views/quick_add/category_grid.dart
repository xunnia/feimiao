import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/category_seed.dart';
import '../../data/app_repository.dart';

/// 分类九宫格（5 列），对应 iOS CategoryGrid.swift。
///
/// 选中态：深蓝填充圆形图标 + 蓝色文字。
/// 未选中：灰色背景圆形图标 + 次要文字色。
class CategoryGrid extends StatelessWidget {
  final List<CategoryEntity> categories;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
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
        final isSelected = cat.id == selectedId;
        return _CategoryItem(
          category: cat,
          isSelected: isSelected,
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
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.category,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  IconData get _icon {
    // 通过 CategorySeed 查找对应图标
    final seed = CategorySeed.all.where((s) => s.key == category.key).firstOrNull;
    return seed?.icon ?? Icons.label_outline;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 圆形图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
            ),
            child: Icon(
              _icon,
              size: 22,
              color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            category.nameZh,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
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
