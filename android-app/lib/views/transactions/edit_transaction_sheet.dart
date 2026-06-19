import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../widgets/tag_selector.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 编辑已有账目的底部大卡。
///
/// 复用 [CategoryGrid] + [AmountKeypad]，预填原有数据；保存调用
/// [AppRepository.updateTransaction]。右上角可删除。
/// 分类区与记账页一致：大类网格 + ▼ + 点开展开子类网格面板。
class EditTransactionSheet extends StatefulWidget {
  final TransactionEntity transaction;

  const EditTransactionSheet({super.key, required this.transaction});

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TransactionKind _kind;
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _activeParentId; // 当前展开的大类
  int? _selectedAccountId;
  late DateTime _date;
  late final TextEditingController _noteController;
  late List<int> _tagIds;
  int _expressionVersion = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    // 段控只有支出/收入；转账退化为支出处理（当前 UI 不产生转账）
    _kind =
        t.txKind == TransactionKind.transfer ? TransactionKind.expense : t.txKind;
    _expression.loadAmount(t.amount);
    _selectedCategoryId = t.categoryId;
    _selectedAccountId = t.accountId;
    _date = t.date;
    _noteController = TextEditingController(text: t.note);
    _tagIds = List<int>.of(t.tagIds);
    // 解析当前分类所属大类，用于展开其子类
    final repo = context.read<AppRepository>();
    final cat =
        repo.categories.where((c) => c.id == _selectedCategoryId).firstOrNull;
    _activeParentId = cat == null ? null : (cat.parentId ?? cat.id);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onKindChanged(TransactionKind kind) {
    final repo = context.read<AppRepository>();
    setState(() {
      _kind = kind;
      final all = repo.categoriesForKind(kind);
      // 切换收支后，若原分类不属于该类型，回退到第一个大类
      if (!all.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = repo.categoriesForKindRanked(kind).firstOrNull?.id;
      }
      final cat = all.where((c) => c.id == _selectedCategoryId).firstOrNull;
      _activeParentId = cat == null ? null : (cat.parentId ?? cat.id);
    });
  }

  void _onExpressionChanged() => setState(() => _expressionVersion++);

  Future<void> _save() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return;
    final repo = context.read<AppRepository>();
    final accountId = _selectedAccountId ?? repo.accounts.firstOrNull?.id;
    if (accountId == null) return;

    await repo.updateTransaction(
      id: widget.transaction.id,
      kind: _kind,
      amount: amount,
      categoryId: _selectedCategoryId,
      accountId: accountId,
      note: _noteController.text.trim(),
      date: _date,
      tagIds: _tagIds,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔账？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppRepository>().deleteTransaction(widget.transaction.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = screenH * 0.92 - bottomInset;

    return SizedBox(
      height: maxH.clamp(300.0, screenH * 0.92),
      child: Column(
        children: [
          // 拖动条
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // 顶部栏：支出/收入 + 删除 + 关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<TransactionKind>(
                    segments: const [
                      ButtonSegment(
                          value: TransactionKind.expense, label: Text('支出')),
                      ButtonSegment(
                          value: TransactionKind.income, label: Text('收入')),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => _onKindChanged(s.first),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: _delete,
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 金额显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('¥',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _expression.displayText,
                    key: ValueKey(_expressionVersion),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_expression.isCompound)
                  Text('= ${_expression.value.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),

          // 分类网格（大类）+ 子类展开面板
          Expanded(
            child: Consumer<AppRepository>(
              builder: (context, repo, _) {
                final cats = repo.categoriesForKindRanked(_kind);
                final expandable = <int>{
                  for (final c in cats)
                    if (repo.childrenOf(c.id).isNotEmpty) c.id
                };
                final children = _activeParentId == null
                    ? const <CategoryEntity>[]
                    : repo.childrenOf(_activeParentId!);
                int? parentHighlight = _activeParentId;
                if (parentHighlight == null &&
                    _selectedCategoryId != null &&
                    cats.any((c) => c.id == _selectedCategoryId)) {
                  parentHighlight = _selectedCategoryId;
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      CategoryGrid(
                        categories: cats,
                        selectedId: parentHighlight,
                        expandableIds: expandable,
                        expandedId: _activeParentId,
                        onSelected: (cat) => setState(() {
                          final hasKids = expandable.contains(cat.id);
                          _activeParentId =
                              (hasKids && _activeParentId != cat.id)
                                  ? cat.id
                                  : null;
                          _selectedCategoryId = cat.id;
                        }),
                      ),
                      if (children.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: CategoryGrid(
                            categories: children,
                            selectedId: _selectedCategoryId,
                            onSelected: (c) => setState(
                                () => _selectedCategoryId = c.id),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 标签选择
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TagSelector(
              selectedIds: _tagIds,
              onChanged: (v) => setState(() => _tagIds = v),
            ),
          ),

          // 账户 + 日期 + 备注
          _DetailBar(
            accounts: context.watch<AppRepository>().accounts,
            selectedAccountId: _selectedAccountId,
            date: _date,
            noteController: _noteController,
            onAccountChanged: (id) => setState(() => _selectedAccountId = id),
            onDateChanged: (d) => setState(() => _date = d),
          ),

          // 数字键盘
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: AmountKeypad(
              expression: _expression,
              onExpressionChanged: _onExpressionChanged,
              onSave: _save,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部详情栏（账户 + 日期 + 备注）—— 与 manual_add_sheet 同款，独立一份避免耦合
// ─────────────────────────────────────────────────────────────────────────────

class _DetailBar extends StatelessWidget {
  final List<AccountEntity> accounts;
  final int? selectedAccountId;
  final DateTime date;
  final TextEditingController noteController;
  final ValueChanged<int?> onAccountChanged;
  final ValueChanged<DateTime> onDateChanged;

  const _DetailBar({
    required this.accounts,
    required this.selectedAccountId,
    required this.date,
    required this.noteController,
    required this.onAccountChanged,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedAccount =
        accounts.where((a) => a.id == selectedAccountId).firstOrNull ??
            accounts.firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          if (accounts.isNotEmpty)
            PopupMenuButton<int>(
              initialValue: selectedAccount?.id,
              onSelected: onAccountChanged,
              itemBuilder: (_) => accounts
                  .map((a) => PopupMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              child: Chip(
                avatar: const Icon(Icons.account_balance_wallet_outlined,
                    size: 16),
                label: Text(selectedAccount?.name ?? '账户'),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) onDateChanged(picked);
            },
            child: Chip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_dateLabel()),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: noteController,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: '备注…',
                hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: scheme.outline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    if (d == today.subtract(const Duration(days: 1))) return '昨天';
    return '${date.month}月${date.day}日';
  }
}

/// 打开编辑大卡的便捷方法（统一 sheet 外观）。
Future<void> showEditTransactionSheet(
    BuildContext context, TransactionEntity transaction) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => EditTransactionSheet(transaction: transaction),
  );
}
