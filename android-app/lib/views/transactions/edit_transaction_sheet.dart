import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../widgets/tag_selector.dart';
import '../common/app_sheet.dart';
import '../common/receipt_picker.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 编辑已有账目的底部大卡。支出/收入按分类编辑；转账按「从→到账户」编辑。
class EditTransactionSheet extends StatefulWidget {
  final TransactionEntity transaction;

  const EditTransactionSheet({super.key, required this.transaction});

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TransactionKind _kind;
  late final bool _isTransfer; // 原始就是转账 —— 编辑时保持转账，不转成支出
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _activeParentId;
  int? _selectedAccountId; // 转账时=「从」账户
  int? _toAccountId; // 转账时=「到」账户
  late DateTime _date;
  late final TextEditingController _noteController;
  late List<int> _tagIds;
  late bool _reimbursable;
  String? _imagePath;
  int _expressionVersion = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _isTransfer = t.txKind == TransactionKind.transfer;
    _kind = t.txKind;
    _expression.loadAmount(t.amount);
    _selectedCategoryId = t.categoryId;
    _selectedAccountId = t.accountId;
    _toAccountId = t.toAccountId;
    _date = t.date;
    _noteController = TextEditingController(text: t.note);
    _tagIds = List<int>.of(t.tagIds);
    _reimbursable = t.reimbursable;
    _imagePath = t.imagePath.isEmpty ? null : t.imagePath;
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
      if (kind != TransactionKind.expense) _reimbursable = false;
      final all = repo.categoriesForKind(kind);
      if (!all.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = repo.categoriesForKindRanked(kind).firstOrNull?.id;
      }
      final cat = all.where((c) => c.id == _selectedCategoryId).firstOrNull;
      _activeParentId = cat == null ? null : (cat.parentId ?? cat.id);
    });
  }

  void _onExpressionChanged() => setState(() => _expressionVersion++);

  Future<void> _pickReceipt() async {
    final path = await pickAndSaveReceipt(context);
    if (path != null && mounted) setState(() => _imagePath = path);
  }

  Future<void> _save() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return;
    final repo = context.read<AppRepository>();
    final accountId = _selectedAccountId ?? repo.accounts.firstOrNull?.id;
    if (accountId == null) return;

    if (_isTransfer) {
      final to = _toAccountId;
      if (to == null || to == accountId) return; // 转账要两个不同账户
      await repo.updateTransaction(
        id: widget.transaction.id,
        kind: TransactionKind.transfer,
        amount: amount,
        categoryId: null,
        accountId: accountId,
        toAccountId: to,
        note: _noteController.text.trim(),
        date: _date,
        tagIds: _tagIds,
      );
    } else {
      await repo.updateTransaction(
        id: widget.transaction.id,
        kind: _kind,
        amount: amount,
        categoryId: _selectedCategoryId,
        accountId: accountId,
        note: _noteController.text.trim(),
        date: _date,
        tagIds: _tagIds,
        reimbursable: _kind == TransactionKind.expense ? _reimbursable : false,
        imagePath: _imagePath ?? '',
      );
      // 学习用户纠正:改了分类且有备注 → 记住「备注 → 新分类」,下次 AI 自动套用。
      final note = _noteController.text.trim();
      if (_selectedCategoryId != null &&
          _selectedCategoryId != widget.transaction.categoryId &&
          note.isNotEmpty) {
        final newKey = repo.categories
            .where((c) => c.id == _selectedCategoryId)
            .firstOrNull
            ?.key;
        if (newKey != null) {
          await repo.learnCategory(
              phrase: note, kind: _kind, categoryKey: newKey);
        }
      }
    }
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
    final accounts = context.watch<AppRepository>().accounts;

    return SizedBox(
      height: maxH.clamp(300.0, screenH * 0.92),
      child: Column(
        children: [
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

          // 顶部栏：支出/收入段控（转账则显示固定标题）+ 删除 + 关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _isTransfer
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '转账',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                          ),
                        )
                      : SegmentedButton<TransactionKind>(
                          segments: const [
                            ButtonSegment(
                                value: TransactionKind.expense,
                                label: Text('支出')),
                            ButtonSegment(
                                value: TransactionKind.income,
                                label: Text('收入')),
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

          // 中部：转账=账户选择；否则=分类网格 + 子类面板
          Expanded(
            child: _isTransfer
                ? _buildTransferBody(context, accounts, scheme)
                : Consumer<AppRepository>(
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
                                margin:
                                    const EdgeInsets.fromLTRB(12, 2, 12, 10),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
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

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: TagSelector(
              selectedIds: _tagIds,
              onChanged: (v) => setState(() => _tagIds = v),
            ),
          ),

          // 待报销 + 收据（转账不显示）
          if (!_isTransfer)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
              child: Row(
                children: [
                  if (_kind == TransactionKind.expense)
                    FilterChip(
                      label: const Text('待报销'),
                      avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                      selected: _reimbursable,
                      onSelected: (v) => setState(() => _reimbursable = v),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  const Spacer(),
                  if (_imagePath == null)
                    TextButton.icon(
                      onPressed: _pickReceipt,
                      icon: const Icon(Icons.photo_camera_outlined, size: 16),
                      label: const Text('收据'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ReceiptThumb(
                        path: _imagePath!,
                        size: 38,
                        onRemove: () => setState(() => _imagePath = null),
                      ),
                    ),
                ],
              ),
            ),

          // 账户 + 日期 + 备注（转账隐藏账户，账户在上方选）
          _DetailBar(
            accounts: accounts,
            selectedAccountId: _selectedAccountId,
            date: _date,
            noteController: _noteController,
            showAccount: !_isTransfer,
            onAccountChanged: (id) => setState(() => _selectedAccountId = id),
            onDateChanged: (d) => setState(() => _date = d),
          ),

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

  Widget _buildTransferBody(
      BuildContext context, List<AccountEntity> accounts, ColorScheme scheme) {
    if (accounts.length < 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        child: Text(
          '转账需要至少两个账户。',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final from = accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final to = accounts.where((a) => a.id == _toAccountId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _accField(context, '从', from?.name ?? '选择', accounts,
                    exclude: _toAccountId,
                    onChanged: (id) => setState(() {
                          _selectedAccountId = id;
                          if (_toAccountId == id) {
                            _toAccountId = accounts
                                .where((a) => a.id != id)
                                .firstOrNull
                                ?.id;
                          }
                        })),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward,
                    color: scheme.primary, size: 22),
              ),
              Expanded(
                child: _accField(context, '到', to?.name ?? '选择', accounts,
                    exclude: _selectedAccountId,
                    onChanged: (id) => setState(() => _toAccountId = id)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '转账只在账户之间移动，不计入收支',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _accField(BuildContext context, String label, String name,
      List<AccountEntity> accounts,
      {required int? exclude, required ValueChanged<int?> onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    final options = accounts.where((a) => a.id != exclude).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        PopupMenuButton<int>(
          onSelected: onChanged,
          itemBuilder: (_) => options
              .map((a) => PopupMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                Icon(Icons.expand_more,
                    size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部详情栏（账户 + 日期 + 备注）
// ─────────────────────────────────────────────────────────────────────────────

class _DetailBar extends StatelessWidget {
  final List<AccountEntity> accounts;
  final int? selectedAccountId;
  final DateTime date;
  final TextEditingController noteController;
  final bool showAccount;
  final ValueChanged<int?> onAccountChanged;
  final ValueChanged<DateTime> onDateChanged;

  const _DetailBar({
    required this.accounts,
    required this.selectedAccountId,
    required this.date,
    required this.noteController,
    required this.showAccount,
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
          if (showAccount && accounts.isNotEmpty) ...[
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
          ],
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

/// 打开编辑大卡的便捷方法（统一走 appSheet 外观）。
Future<void> showEditTransactionSheet(
    BuildContext context, TransactionEntity transaction) {
  return appSheet<void>(
    context,
    child: EditTransactionSheet(transaction: transaction),
  );
}
