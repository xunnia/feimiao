import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../widgets/settings_ui.dart';
import '../quick_add/category_grid.dart';
import 'app_sheet.dart';

Future<CategoryEntity?> showCategoryPickerSheet(
  BuildContext context, {
  required TransactionKind kind,
  int? selectedId,
  String title = '选择分类',
  String? subtitle,
}) {
  return showBlurSheet<CategoryEntity>(
    context,
    child: _CategoryPickerSheet(
      kind: kind,
      selectedId: selectedId,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  final TransactionKind kind;
  final int? selectedId;
  final String title;
  final String? subtitle;

  const _CategoryPickerSheet({
    required this.kind,
    required this.selectedId,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  int? _selectedId;
  int? _expandedParentId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    final selected = widget.selectedId == null
        ? null
        : context
            .read<AppRepository>()
            .categories
            .where((category) => category.id == widget.selectedId)
            .firstOrNull;
    // Preserve the previous restore behavior: editing an existing child
    // selection opens its parent once. Subsequent user collapse is respected
    // because build never derives expansion from the selection again.
    _expandedParentId = selected?.parentId;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final tops = repo.categoriesForKindRanked(widget.kind);
    final selected = _selectedId == null
        ? null
        : repo.categories.where((c) => c.id == _selectedId).firstOrNull;
    final expandable = <int>{
      for (final c in tops)
        if (repo.visibleChildrenOf(c.id).isNotEmpty) c.id,
    };
    final children = _expandedParentId == null
        ? const <CategoryEntity>[]
        : repo.childrenOfRanked(_expandedParentId!);
    final subLabels = selected != null && selected.parentId != null
        ? {selected.parentId!: selected.nameZh}
        : const <int, String>{};
    final selectedParentId = selected?.parentId ?? selected?.id;

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              onClose: () => Navigator.pop(context),
              actionLabel: '保存',
              onAction: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
                child: HierarchicalCategoryPicker(
                  categories: tops,
                  children: children,
                  selectedId: _selectedId,
                  selectedParentId: selectedParentId,
                  expandedParentId: _expandedParentId,
                  expandableIds: expandable,
                  subLabels: subLabels,
                  onParentSelected: (category) {
                    final hasChildren = expandable.contains(category.id);
                    setState(() {
                      _selectedId = category.id;
                      _expandedParentId = hasChildren
                          ? (_expandedParentId == category.id
                              ? null
                              : category.id)
                          : null;
                    });
                  },
                  onChildSelected: (category) => setState(() {
                    _selectedId = category.id;
                    _expandedParentId = null;
                  }),
                  onClosePanel: () => setState(() => _expandedParentId = null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
