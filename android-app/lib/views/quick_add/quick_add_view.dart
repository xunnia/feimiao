import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/budget/budget_engine.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import 'ai_quick_entry_view.dart';
import 'amount_keypad.dart';
import 'category_grid.dart';

/// 快记页：打开即键盘，目标 3 秒记完一笔。
/// 对应 iOS QuickAddView.swift。
class QuickAddView extends StatefulWidget {
  const QuickAddView({super.key});

  @override
  State<QuickAddView> createState() => _QuickAddViewState();
}

class _QuickAddViewState extends State<QuickAddView> {
  TransactionKind _kind = TransactionKind.expense;
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _selectedAccountId;
  DateTime _date = DateTime.now();
  final TextEditingController _noteController = TextEditingController();

  // 用于触发键盘区 rebuild 的计数器（AmountExpression 是可变对象）
  int _expressionVersion = 0;

  @override
  void initState() {
    super.initState();
    // 延后一帧等 provider 就绪
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
      final cats = repo.categoriesForKind(_kind);
      _selectedCategoryId ??= cats.firstOrNull?.id;
    });
  }

  void _onKindChanged(TransactionKind kind) {
    final repo = context.read<AppRepository>();
    setState(() {
      _kind = kind;
      final cats = repo.categoriesForKind(kind);
      _selectedCategoryId = cats.firstOrNull?.id;
    });
  }

  void _onExpressionChanged() {
    setState(() => _expressionVersion++);
  }

  Future<void> _save() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return; // 金额为 0 或负数，不记录

    final repo = context.read<AppRepository>();
    final accountId = _selectedAccountId ?? repo.accounts.firstOrNull?.id;
    if (accountId == null) return;

    await repo.addTransaction(
      kind: _kind,
      amount: amount,
      categoryId: _selectedCategoryId,
      accountId: accountId,
      note: _noteController.text.trim(),
      date: _date,
    );

    // 保存成功后返回首页；首页通过 context.watch<AppRepository>() 自动刷新。
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'AI 记账',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AiQuickEntryView(),
              ),
            ),
          ),
        ],
      ),
      // resizeToAvoidBottomInset false，因为我们用自定义键盘不需要系统键盘顶起
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // 1. 支出/收入分段切换
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<TransactionKind>(
              segments: const [
                ButtonSegment(value: TransactionKind.expense, label: Text('支出')),
                ButtonSegment(value: TransactionKind.income, label: Text('收入')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => _onKindChanged(s.first),
            ),
          ),

          // 2. 金额大字显示
          _AmountDisplay(expression: _expression, version: _expressionVersion),

          // 2b. 今日可花横幅（支出且已设预算时显示）
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

          // 3. 分类格（可滚动区域）
          Expanded(
            child: Consumer<AppRepository>(
              builder: (context, repo, _) {
                final cats = repo.categoriesForKind(_kind);
                return SingleChildScrollView(
                  child: CategoryGrid(
                    categories: cats,
                    selectedId: _selectedCategoryId,
                    onSelected: (cat) => setState(() => _selectedCategoryId = cat.id),
                  ),
                );
              },
            ),
          ),

          // 4. 底部：账户 + 日期 + 备注
          _DetailBar(
            accounts: context.watch<AppRepository>().accounts,
            selectedAccountId: _selectedAccountId,
            date: _date,
            noteController: _noteController,
            onAccountChanged: (id) => setState(() => _selectedAccountId = id),
            onDateChanged: (d) => setState(() => _date = d),
          ),

          // 5. 数字键盘
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
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

// ---------------------------------------------------------------------------
// 金额显示区
// ---------------------------------------------------------------------------

class _AmountDisplay extends StatelessWidget {
  final AmountExpression expression;
  final int version; // 强制 rebuild 用

  const _AmountDisplay({required this.expression, required this.version});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '¥',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              expression.displayText,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 底部详情栏：账户 + 日期 + 备注
// ---------------------------------------------------------------------------

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
    final selectedAccount = accounts.where((a) => a.id == selectedAccountId).firstOrNull
        ?? accounts.firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          // 账户选择器
          if (accounts.isNotEmpty)
            _AccountButton(
              account: selectedAccount,
              accounts: accounts,
              onChanged: onAccountChanged,
            ),
          const SizedBox(width: 8),

          // 日期选择
          _DateButton(date: date, onChanged: onDateChanged),
          const SizedBox(width: 8),

          // 备注输入
          Expanded(
            child: TextField(
              controller: noteController,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: '备注…',
                hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        avatar: const Icon(Icons.account_balance_wallet_outlined, size: 16),
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

// ---------------------------------------------------------------------------
// 今日可花横幅
// ---------------------------------------------------------------------------

class _TodayAllowanceBanner extends StatelessWidget {
  final BudgetStatus status;

  const _TodayAllowanceBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOver = status.todayAllowance < Decimal.zero;
    final bgColor = isOver
        ? AppColors.warning.withOpacity( 0.12)
        : scheme.primaryContainer.withOpacity( 0.5);
    final textColor = isOver ? AppColors.warning : scheme.onSurfaceVariant;

    final allowanceText = isOver
        ? '今日已超出节奏 ${MoneyFormat.string(-status.todayAllowance)}，缓一缓'
        : '今日可花 ${MoneyFormat.string(status.todayAllowance)} · 本月剩 ${MoneyFormat.string(status.remaining)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
