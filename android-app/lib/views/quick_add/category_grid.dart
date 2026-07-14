import 'dart:math' show min;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/category_seed.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pressable_scale.dart';

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

  /// 显示成半透明的分类（分类管理页用来标「已隐藏」）。
  final Set<int> dimmedIds;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.expandableIds = const <int>{},
    this.expandedId,
    this.subLabels = const <int, String>{},
    this.dimmedIds = const <int>{},
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
        final item = _CategoryItem(
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
        return dimmedIds.contains(cat.id)
            ? Opacity(opacity: 0.4, child: item)
            : item;
      },
    );
  }
}

/// Shared hierarchical category selector used by manual entry and every
/// category-selection sheet. Parent categories stay in their original row;
/// children open immediately below that row while the surrounding content is
/// softened, matching the manual-entry interaction.
class HierarchicalCategoryPicker extends StatefulWidget {
  final List<CategoryEntity> categories;
  final List<CategoryEntity> children;
  final int? selectedId;
  final int? selectedParentId;
  final int? expandedParentId;
  final Set<int> expandableIds;
  final Map<int, String> subLabels;
  final ValueChanged<CategoryEntity> onParentSelected;
  final ValueChanged<CategoryEntity> onChildSelected;
  final VoidCallback onClosePanel;

  /// Content underneath the category rows, such as the manual-entry controls.
  /// It remains in place and is blurred while the child panel is open.
  final Widget? obscuredChild;

  const HierarchicalCategoryPicker({
    super.key,
    required this.categories,
    required this.children,
    required this.selectedId,
    required this.selectedParentId,
    required this.expandedParentId,
    required this.expandableIds,
    required this.onParentSelected,
    required this.onChildSelected,
    required this.onClosePanel,
    this.subLabels = const <int, String>{},
    this.obscuredChild,
  });

  @override
  State<HierarchicalCategoryPicker> createState() =>
      _HierarchicalCategoryPickerState();
}

class _HierarchicalCategoryPickerState
    extends State<HierarchicalCategoryPicker> {
  static const double _rowExtent = 92;
  static const double _maxRowsHeight = 184;
  final LayerLink _panelLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    const columns = 5;
    final rows = <List<CategoryEntity>>[];
    for (var i = 0; i < widget.categories.length; i += columns) {
      rows.add(widget.categories.sublist(
        i,
        min(i + columns, widget.categories.length),
      ));
    }

    final panelOpen = widget.expandedParentId != null;
    final activeRow = !panelOpen
        ? -1
        : rows.indexWhere(
            (row) => row.any((c) => c.id == widget.expandedParentId),
          );
    final rootHeight =
        rows.isEmpty ? 0.0 : min(rows.length * _rowExtent + 4, _maxRowsHeight);
    final reservedPanelHeight = panelOpen && widget.obscuredChild == null
        ? min(232.0, ((widget.children.length + 5) ~/ 6) * 76.0 + 20)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rows.isNotEmpty)
                  SizedBox(
                    height: rootHeight,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      itemExtent: _rowExtent,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = SizedBox(
                          height: _rowExtent,
                          child: _CategoryRowGrid(
                            categories: rows[index],
                            selectedId: widget.selectedParentId,
                            expandableIds: widget.expandableIds,
                            expandedId: widget.expandedParentId,
                            subLabels: {
                              for (final entry in widget.subLabels.entries)
                                if (entry.value.isNotEmpty)
                                  entry.key: entry.value,
                            },
                            onSelected: widget.onParentSelected,
                          ),
                        );
                        if (index == activeRow) {
                          return CompositedTransformTarget(
                            link: _panelLink,
                            child: row,
                          );
                        }
                        return _CategoryObscuredRegion(
                          obscured: panelOpen,
                          onTap: widget.onClosePanel,
                          child: row,
                        );
                      },
                    ),
                  ),
                if (widget.obscuredChild != null)
                  _CategoryObscuredRegion(
                    obscured: panelOpen,
                    sigma: 3,
                    opacity: 0.3,
                    onTap: widget.onClosePanel,
                    child: widget.obscuredChild!,
                  )
                else
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: double.infinity,
                      height: reservedPanelHeight,
                    ),
                  ),
              ],
            ),
            if (panelOpen && widget.children.isNotEmpty)
              CompositedTransformFollower(
                link: _panelLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: HierarchicalSubcategoryPanel(
                    children: widget.children,
                    selectedId: widget.selectedId,
                    onSelected: widget.onChildSelected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryObscuredRegion extends StatelessWidget {
  final bool obscured;
  final Widget child;
  final VoidCallback onTap;
  final double sigma;
  final double opacity;

  const _CategoryObscuredRegion({
    required this.obscured,
    required this.child,
    required this.onTap,
    this.sigma = 1.8,
    this.opacity = 0.65,
  });

  @override
  Widget build(BuildContext context) {
    if (!obscured) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AbsorbPointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Opacity(opacity: opacity, child: child),
        ),
      ),
    );
  }
}

class _CategoryRowGrid extends StatelessWidget {
  final List<CategoryEntity> categories;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;
  final Set<int> expandableIds;
  final int? expandedId;
  final Map<int, String> subLabels;

  const _CategoryRowGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.expandableIds,
    required this.expandedId,
    required this.subLabels,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < 5; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: index >= categories.length
                  ? const SizedBox.shrink()
                  : KeyedSubtree(
                      key: ValueKey('category-parent-${categories[index].id}'),
                      child: _CategoryItem(
                        category: categories[index],
                        isSelected: categories[index].id == selectedId,
                        showChevron:
                            expandableIds.contains(categories[index].id),
                        expanded: categories[index].id == expandedId,
                        subLabel: subLabels[categories[index].id],
                        scheme: scheme,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelected(categories[index]);
                        },
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class HierarchicalSubcategoryPanel extends StatelessWidget {
  final List<CategoryEntity> children;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;

  const HierarchicalSubcategoryPanel({
    super.key,
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('subcategory-panel'),
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline(scheme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 232),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 12,
            crossAxisSpacing: 4,
            childAspectRatio: 0.74,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) {
            final category = children[index];
            final selected = category.id == selectedId;
            return PressableScale(
              key: ValueKey('category-child-${category.id}'),
              onPressed: () {
                HapticFeedback.selectionClick();
                onSelected(category);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? scheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CatIcon(
                      categoryKey: category.key,
                      emoji: CategorySeed.emojiOf(category.key),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    category.nameZh,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
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
    final seed =
        CategorySeed.all.where((s) => s.key == category.key).firstOrNull;
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
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: subLabel == null ? null : 10,
                  height: subLabel == null ? null : 1.25,
                  color:
                      isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
            // 选了二级时允许两行，保证「大类·二级名」的二级名能露出来。
            maxLines: subLabel == null ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
