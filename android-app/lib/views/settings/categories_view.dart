import 'package:flutter/material.dart';

import '../../widgets/ios_dialogs.dart';
import 'package:provider/provider.dart';

import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';

/// 分类管理页：按收/支分组，**大类分组 + 子类缩进**列出，支持新增、改名、删除。
class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分类管理'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新增分类',
              onPressed: () => _showAddSheet(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '支出'),
              Tab(text: '收入'),
            ],
          ),
        ),
        body: Consumer<AppRepository>(
          builder: (context, repo, _) {
            final expenses =
                repo.categoriesForKind(TransactionKind.expense);
            final incomes =
                repo.categoriesForKind(TransactionKind.income);

            return TabBarView(
              children: [
                _CategoryList(
                  categories: expenses,
                  kind: TransactionKind.expense,
                ),
                _CategoryList(
                  categories: incomes,
                  kind: TransactionKind.income,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddCategorySheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// 分类列表（单一收/支类型）：大类一组，子类缩进列在其下
// ---------------------------------------------------------------------------

class _CategoryList extends StatelessWidget {
  final List<CategoryEntity> categories;
  final TransactionKind kind;

  const _CategoryList({required this.categories, required this.kind});

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_outline,
                size: 56,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              '还没有分类',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final tops = categories.where((c) => c.isTopLevel).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        for (final top in tops) ...[
          _tile(context, top, isChild: false),
          for (final child in categories.where((c) => c.parentId == top.id))
            _tile(context, child, isChild: true),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, CategoryEntity cat,
      {required bool isChild}) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: isChild ? 38 : 16, right: 4),
      minLeadingWidth: 0,
      leading: CatIcon(
        categoryKey: cat.key,
        emoji: CategorySeed.emojiOf(cat.key),
        size: isChild ? 30 : 38,
      ),
      title: Text(
        cat.nameZh,
        style: isChild
            ? Theme.of(context).textTheme.bodyMedium
            : Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '改名',
            onPressed: () => _showRenameSheet(context, cat),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '删除',
            onPressed: () => _confirmDelete(context, cat),
          ),
        ],
      ),
    );
  }

  void _showRenameSheet(BuildContext context, CategoryEntity cat) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RenameCategorySheet(category: cat),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, CategoryEntity cat) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除分类',
      message: '确认删除「${cat.nameZh}」？\n关联的历史记录不会被删除。',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await context.read<AppRepository>().deleteCategory(cat.id);
    }
  }
}

// ---------------------------------------------------------------------------
// 新增分类底部弹层（自定义分类用 emoji/标签兜底显示，不再有“假图标选择器”）
// ---------------------------------------------------------------------------

class _AddCategorySheet extends StatefulWidget {
  const _AddCategorySheet();

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  TransactionKind _kind = TransactionKind.expense;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '新增分类',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          SegmentedButton<TransactionKind>(
            segments: const [
              ButtonSegment(
                  value: TransactionKind.expense, label: Text('支出')),
              ButtonSegment(
                  value: TransactionKind.income, label: Text('收入')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '分类名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          final name = _nameCtrl.text.trim();
                          final key =
                              'custom_${DateTime.now().millisecondsSinceEpoch}';
                          await context.read<AppRepository>().addCategory(
                                key: key,
                                nameZh: name,
                                nameEn: name,
                                kind: _kind,
                              );
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 改名底部弹层
// ---------------------------------------------------------------------------

class _RenameCategorySheet extends StatefulWidget {
  final CategoryEntity category;

  const _RenameCategorySheet({required this.category});

  @override
  State<_RenameCategorySheet> createState() => _RenameCategorySheetState();
}

class _RenameCategorySheetState extends State<_RenameCategorySheet> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category.nameZh);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '修改分类名称',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '分类名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          await context
                              .read<AppRepository>()
                              .renameCategory(
                                widget.category.id,
                                nameZh: _nameCtrl.text.trim(),
                                nameEn: _nameCtrl.text.trim(),
                              );
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
