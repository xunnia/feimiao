import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/category_seed.dart';
import '../../data/app_repository.dart';

/// 子类横排：点大类后展示其子类 chip（手动卡与编辑页共用）。
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                    Text(CategorySeed.emojiOf(c.key),
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
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

  String get _emoji {
    // 通过 CategorySeed 查找对应 emoji（找不到给个标签兜底）
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
          // 圆形图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(_emoji, style: const TextStyle(fontSize: 24)),
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
