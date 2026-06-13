import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';

/// 分类管理页：按收/支分组列出，支持新增、改名、删除。
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
// 分类列表（单一收/支类型）
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
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: categories.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final icon = _iconForKey(cat.key);
        return ListTile(
          leading: Icon(icon),
          title: Text(cat.nameZh),
          subtitle: Text(
            cat.nameEn,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
      },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确认删除「${cat.nameZh}」？\n关联的历史记录不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppRepository>().deleteCategory(cat.id);
    }
  }

  /// 根据 key 返回对应图标（和 CategorySeed 保持一致，自定义分类用 label 图标兜底）。
  static IconData _iconForKey(String key) {
    const map = <String, IconData>{
      'dining': Icons.restaurant,
      'groceries': Icons.shopping_cart,
      'transport': Icons.directions_bus,
      'shopping': Icons.shopping_bag,
      'entertainment': Icons.sports_esports,
      'housing': Icons.home,
      'utilities': Icons.bolt,
      'medical': Icons.medical_services,
      'education': Icons.menu_book,
      'travel': Icons.flight,
      'pets': Icons.pets,
      'gifts': Icons.card_giftcard,
      'subscription': Icons.autorenew,
      'other': Icons.more_horiz,
      'salary': Icons.payments,
      'bonus': Icons.star,
      'investment': Icons.trending_up,
      'redPacket': Icons.mail,
      'refund': Icons.undo,
      'otherIncome': Icons.add_circle,
    };
    return map[key] ?? Icons.label_outline;
  }
}

// ---------------------------------------------------------------------------
// 可选图标列表（确认均为 Material Icons 标准图标）
// ---------------------------------------------------------------------------

/// 提供给用户挑选的图标列表，只包含已在 Material Icons 中确认存在的图标。
const List<_IconOption> _kPickerIcons = [
  _IconOption(icon: Icons.restaurant, label: '餐饮'),
  _IconOption(icon: Icons.shopping_cart, label: '购物车'),
  _IconOption(icon: Icons.directions_bus, label: '公交'),
  _IconOption(icon: Icons.shopping_bag, label: '购物袋'),
  _IconOption(icon: Icons.sports_esports, label: '游戏'),
  _IconOption(icon: Icons.home, label: '住房'),
  _IconOption(icon: Icons.bolt, label: '电费'),
  _IconOption(icon: Icons.medical_services, label: '医疗'),
  _IconOption(icon: Icons.menu_book, label: '书籍'),
  _IconOption(icon: Icons.flight, label: '机票'),
  _IconOption(icon: Icons.pets, label: '宠物'),
  _IconOption(icon: Icons.card_giftcard, label: '礼品'),
  _IconOption(icon: Icons.autorenew, label: '订阅'),
  _IconOption(icon: Icons.more_horiz, label: '其他'),
  _IconOption(icon: Icons.payments, label: '工资'),
  _IconOption(icon: Icons.star, label: '奖金'),
  _IconOption(icon: Icons.trending_up, label: '理财'),
  _IconOption(icon: Icons.mail, label: '红包'),
  _IconOption(icon: Icons.undo, label: '退款'),
  _IconOption(icon: Icons.add_circle, label: '新增'),
  _IconOption(icon: Icons.coffee, label: '咖啡'),
  _IconOption(icon: Icons.local_taxi, label: '打车'),
  _IconOption(icon: Icons.fitness_center, label: '健身'),
  _IconOption(icon: Icons.local_hospital, label: '医院'),
  _IconOption(icon: Icons.phone_android, label: '手机'),
  _IconOption(icon: Icons.laptop, label: '电脑'),
  _IconOption(icon: Icons.child_care, label: '育儿'),
  _IconOption(icon: Icons.sports_basketball, label: '运动'),
];

class _IconOption {
  final IconData icon;
  final String label;

  const _IconOption({required this.icon, required this.label});
}

// ---------------------------------------------------------------------------
// 新增分类底部弹层
// ---------------------------------------------------------------------------

class _AddCategorySheet extends StatefulWidget {
  const _AddCategorySheet();

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  TransactionKind _kind = TransactionKind.expense;
  IconData _selectedIcon = Icons.label_outline;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

          // 收/支切换
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

          // 名称输入
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
          const SizedBox(height: 12),

          // 图标选择
          Text(
            '选择图标',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: GridView.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _kPickerIcons.length,
              itemBuilder: (context, index) {
                final opt = _kPickerIcons[index];
                final selected = _selectedIcon == opt.icon;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = opt.icon),
                  child: Tooltip(
                    message: opt.label,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: selected
                            ? Border.all(
                                color: scheme.primary, width: 2)
                            : null,
                      ),
                      child: Icon(
                        opt.icon,
                        size: 22,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 操作按钮
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
                          // 以时间戳生成唯一 key，防止与种子数据冲突
                          final key =
                              'custom_${DateTime.now().millisecondsSinceEpoch}';
                          await context.read<AppRepository>().addCategory(
                                key: key,
                                nameZh: name,
                                nameEn: name, // 用户自定义分类英文名同中文名
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
