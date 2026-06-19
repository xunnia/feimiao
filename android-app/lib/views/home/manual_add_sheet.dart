import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/budget/budget_engine.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tag_selector.dart';
import '../common/receipt_picker.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 手动记账大卡片（模态底部弹出）。
class ManualAddSheet extends StatefulWidget {
  final VoidCallback onSwitchToAi;

  const ManualAddSheet({super.key, required this.onSwitchToAi});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  TransactionKind _kind = TransactionKind.expense;
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _activeParentId;
  int? _selectedAccountId;
  int? _toAccountId;
  DateTime _date = DateTime.now();
  final TextEditingController _noteController = TextEditingController();
  List<int> _tagIds = [];
  bool _reimbursable = false;
  String? _imagePath;
  int _expressionVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaults());
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _applyDefaults() {
    final repo = context.read<AppRepository>();
    setState(() {
      _selectedAccountId ??= repo.accounts.firstOrNull?.id;
      final cats = repo.categoriesForKindRanked(_kind);
      _selectedCategoryId ??= cats.firstOrNull?.id;
    });
  }

  void _onKindChanged(TransactionKind kind) {
    if (kind == _kind) return;
    final repo = context.read<AppRepository>();
    setState(() {
      _kind = kind;
      _reimbursable = false;
      _imagePath = null;
      if (kind == TransactionKind.transfer) {
        _selectedAccountId ??= repo.accounts.firstOrNull?.id;
        _toAccountId = repo.accounts
            .where((a) => a.id != _selectedAccountId)
            .firstOrNull
            ?.id;
      } else {
        final cats = repo.categoriesForKindRanked(kind);
        _selectedCategoryId = cats.firstOrNull?.id;
        _activeParentId = null;
      }
    });
  }

  void _onExpressionChanged() => setState(() => _expressionVersion++);

  Future<void> _pickReceipt() async {
    final path = await pickAndSaveReceipt(context);
    if (path != null && mounted) setState(() => _imagePath = path);
  }

  Future<bool> _commit() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return false;

    final repo = context.read<AppRepository>();
    final from = _selectedAccountId ?? repo.accounts.firstOrNull?.id;
    if (from == null) return false;

    if (_kind == TransactionKind.transfer) {
      final to = _toAccountId;
      if (to == null || to == from) return false;
      await repo.addTransaction(
        kind: TransactionKind.transfer,
        amount: amount,
        categoryId: null,
        accountId: from,
        toAccountId: to,
        note: _noteController.text.trim(),
        date: _date,
        tagIds: _tagIds,
      );
    } else {
      await repo.addTransaction(
        kind: _kind,
        amount: amount,
        categoryId: _selectedCategoryId,
        accountId: from,
        note: _noteController.text.trim(),
        date: _date,
        tagIds: _tagIds,
        reimbursable: _reimbursable,
        imagePath: _imagePath ?? '',
      );
    }
    return true;
  }

  Future<void> _save() async {
    if (await _commit() && mounted) Navigator.pop(context);
  }

  Future<void> _saveAndContinue() async {
    if (await _commit()) {
      _expression.clear();
      _noteController.clear();
      _reimbursable = false;
      _imagePath = null;
      if (mounted) setState(() => _expressionVersion++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = screenH * 0.92 - bottomInset;
    final isTransfer = _kind == TransactionKind.transfer;

    return SizedBox(
      height: maxH.clamp(300.0, screenH * 0.92),
      child: Column(
        children: [
          const _DragHandle(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _KindTabs(selected: _kind, onChanged: _onKindChanged),
                ),
                const SizedBox(width: 8),
                _ModePill(label: '手动记账', onTap: widget.onSwitchToAi),
                const SizedBox(width: 8),
                _ToolCircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 中部：分类区 或 转账区
          Expanded(
            child: Consumer<AppRepository>(
              builder: (context, repo, _) {
                if (isTransfer) {
                  return _TransferBody(
                    accounts: repo.accounts,
                    fromId: _selectedAccountId,
                    toId: _toAccountId,
                    onFrom: (id) => setState(() {
                      _selectedAccountId = id;
                      if (_toAccountId == id) {
                        _toAccountId = repo.accounts
                            .where((a) => a.id != id)
                            .firstOrNull
                            ?.id;
                      }
                    }),
                    onTo: (id) => setState(() => _toAccountId = id),
                  );
                }
                final scheme = Theme.of(context).colorScheme;
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
                      const SizedBox(height: 4),
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
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
            child: TagSelector(
              selectedIds: _tagIds,
              onChanged: (v) => setState(() => _tagIds = v),
            ),
          ),

          // 待报销开关（仅支出）+ 收据（非转账）
          if (!isTransfer)
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

          // 今日可花横幅（支出时按需显示）
          if (_kind == TransactionKind.expense)
            Consumer<AppRepository>(
              builder: (context, repo, _) {
                final budget = repo.monthlyBudget;
                if (budget == null) return const SizedBox.shrink();
                final status = BudgetEngine.status(
                  monthlyBudget: budget,
                  records: repo.allRecords,
                );
                return _TodayAllowanceBanner(status: status);
              },
            ),

          // 金额 + 日期/备注 成组卡片
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return Container(
                margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _AmountDisplay(
                        expression: _expression, version: _expressionVersion),
                    _DetailBar(
                      accounts: context.watch<AppRepository>().accounts,
                      selectedAccountId: _selectedAccountId,
                      date: _date,
                      noteController: _noteController,
                      showAccount: !isTransfer,
                      onAccountChanged: (id) =>
                          setState(() => _selectedAccountId = id),
                      onDateChanged: (d) => setState(() => _date = d),
                    ),
                  ],
                ),
              );
            },
          ),

          // 数字键盘
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 2),
            child: AmountKeypad(
              expression: _expression,
              onExpressionChanged: _onExpressionChanged,
              onSave: _save,
              onSaveAndContinue: _saveAndContinue,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 顶部 kind 文字 tab（支出 / 收入 / 转账）
// ─────────────────────────────────────────────────────────────────────────────

class _KindTabs extends StatelessWidget {
  final TransactionKind selected;
  final ValueChanged<TransactionKind> onChanged;

  const _KindTabs({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget sep() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('｜',
              style: TextStyle(color: scheme.outlineVariant, fontSize: 15)),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tab(context, '支出', TransactionKind.expense, scheme),
        sep(),
        _tab(context, '收入', TransactionKind.income, scheme),
        sep(),
        _tab(context, '转账', TransactionKind.transfer, scheme),
      ],
    );
  }

  Widget _tab(BuildContext context, String label, TransactionKind kind,
      ColorScheme scheme) {
    final isSel = kind == selected;
    return GestureDetector(
      onTap: () => onChanged(kind),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
              color: isSel ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(
              color: isSel ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 转账区：从账户 → 到账户
// ─────────────────────────────────────────────────────────────────────────────

class _TransferBody extends StatelessWidget {
  final List<AccountEntity> accounts;
  final int? fromId;
  final int? toId;
  final ValueChanged<int?> onFrom;
  final ValueChanged<int?> onTo;

  const _TransferBody({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.onFrom,
    required this.onTo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (accounts.length < 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        child: Text(
          '转账需要至少两个账户。\n先到「设置 → 账户」里添加一个吧～',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final from = accounts.where((a) => a.id == fromId).firstOrNull;
    final to = accounts.where((a) => a.id == toId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _accTile(context, '从', from?.name ?? '选择',
                    exclude: toId, onChanged: onFrom),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward,
                    color: scheme.primary, size: 22),
              ),
              Expanded(
                child: _accTile(context, '到', to?.name ?? '选择',
                    exclude: fromId, onChanged: onTo),
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

  Widget _accTile(BuildContext context, String label, String name,
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
// 拖动条
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 金额显示
// ─────────────────────────────────────────────────────────────────────────────

class _AmountDisplay extends StatelessWidget {
  final AmountExpression expression;
  final int version;

  const _AmountDisplay({required this.expression, required this.version});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '¥',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              expression.displayText,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (expression.isCompound) ...[
            const SizedBox(width: 8),
            Text(
              '= ${expression.value.toStringAsFixed(2)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 详情行：账户 + 日期 + 备注
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          if (showAccount && accounts.isNotEmpty) ...[
            _AccountButton(
              account: selectedAccount,
              accounts: accounts,
              onChanged: onAccountChanged,
            ),
            const SizedBox(width: 8),
          ],
          _DateButton(date: date, onChanged: onDateChanged),
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
}

class _AccountButton extends StatelessWidget {
  final AccountEntity? account;
  final List<AccountEntity> accounts;
  final ValueChanged<int?> onChanged;

  const _AccountButton({
    required this.account,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      initialValue: account?.id,
      onSelected: onChanged,
      itemBuilder: (_) => accounts
          .map((a) => PopupMenuItem(value: a.id, child: Text(a.name)))
          .toList(),
      child: Chip(
        avatar:
            const Icon(Icons.account_balance_wallet_outlined, size: 16),
        label: Text(account?.name ?? '账户'),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _DateButton({required this.date, required this.onChanged});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == yesterday) return '昨天';
    return '${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
      child: Chip(
        avatar: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(_label()),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 今日可花横幅
// ─────────────────────────────────────────────────────────────────────────────

class _TodayAllowanceBanner extends StatelessWidget {
  final BudgetStatus status;

  const _TodayAllowanceBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOver = status.todayAllowance < Decimal.zero;
    final bgColor = isOver
        ? AppColors.warning.withValues(alpha: 0.12)
        : scheme.primaryContainer.withValues(alpha: 0.5);
    final textColor = isOver ? AppColors.warning : scheme.onSurfaceVariant;

    final allowanceText = isOver
        ? '今日已超出节奏 ${MoneyFormat.string(-status.todayAllowance)}，缓一缓'
        : '今日可花 ${MoneyFormat.string(status.todayAllowance)} · 本月剩 ${MoneyFormat.string(status.remaining)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        allowanceText,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 统一圆形工具按钮
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ToolCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 模式胶囊
// ─────────────────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ModePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
