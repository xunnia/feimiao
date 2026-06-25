import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/budget/budget_engine.dart';
import '../../core/haptics.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/tag_selector.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 手动记账大卡片（模态底部弹出）。
///
/// 用 showModalBottomSheet(isScrollControlled: true) 全高弹出。
/// 顶部拖动条 + 支出/收入分段 + "AI助手"胶囊 + X 关闭。
/// 主体复用 CategoryGrid + _AmountDisplay + AmountKeypad。
/// 保存后自动关闭（Navigator.pop）。
class ManualAddSheet extends StatefulWidget {
  /// 点击"AI助手"时的回调（由调用方切换到 AiFocusedInputSheet）。
  final VoidCallback onSwitchToAi;

  const ManualAddSheet({super.key, required this.onSwitchToAi});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  TransactionKind _kind = TransactionKind.expense;
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _activeParentId; // 当前展开的大类（用于显示其子类）
  int? _selectedAccountId;
  DateTime _date = DateTime.now();
  final TextEditingController _noteController = TextEditingController();
  List<int> _tagIds = [];
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
      _activeParentId ??= _selectedCategoryId;
    });
  }

  void _onKindChanged(TransactionKind kind) {
    final repo = context.read<AppRepository>();
    setState(() {
      _kind = kind;
      final cats = repo.categoriesForKindRanked(kind);
      _selectedCategoryId = cats.firstOrNull?.id;
      _activeParentId = _selectedCategoryId;
    });
  }

  void _onExpressionChanged() => setState(() => _expressionVersion++);

  Future<void> _save() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return;

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
      tagIds: _tagIds,
    );

    Haptics.of(Haptic.success);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // isScrollControlled: true のsheet では高さ制約を自分で持つ必要がある。
    // 画面高さの 92% を上限に、キーボード分を引いた残り全体を使う。
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = screenH * 0.92 - bottomInset;

    return SizedBox(
      height: maxH.clamp(300.0, screenH * 0.92),
      child: Column(
        children: [
        // ── 顶部拖动条 ──
        const _DragHandle(),

        // ── 顶部栏：分段 + AI助手胶囊 + 关闭 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Row(
            children: [
              // 支出 / 收入
              Expanded(
                child: CupertinoSlidingSegmentedControl<TransactionKind>(
                  groupValue: _kind,
                  onValueChanged: (v) {
                    if (v != null) _onKindChanged(v);
                  },
                  children: const {
                    TransactionKind.expense: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('支出'),
                    ),
                    TransactionKind.income: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('收入'),
                    ),
                  },
                ),
              ),
              const SizedBox(width: 8),

              // 模式胶囊：显示当前模式（手动），点一下切到 AI
              _ModePill(
                label: '手动记账',
                onTap: widget.onSwitchToAi,
              ),
              const SizedBox(width: 8),

              // 关闭
              _ToolCircleButton(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // ── 金额显示 ──
        _AmountDisplay(
            expression: _expression, version: _expressionVersion),

        // ── 今日可花横幅（支出时按需显示）──
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

        // ── 分类格（Expanded 撑满剩余空间）──
        Expanded(
          child: Consumer<AppRepository>(
            builder: (context, repo, _) {
              final cats = repo.categoriesForKindRanked(_kind);
              final children = _activeParentId == null
                  ? const <CategoryEntity>[]
                  : repo.childrenOf(_activeParentId!);
              return SingleChildScrollView(
                child: Column(
                  children: [
                    // 大类网格：选中=当前展开的大类
                    CategoryGrid(
                      categories: cats,
                      selectedId: _activeParentId,
                      onSelected: (cat) => setState(() {
                        _activeParentId = cat.id;
                        _selectedCategoryId = cat.id; // 不选子类则记到大类
                      }),
                    ),
                    // 子类横排（选了大类且其有子类时出现）
                    if (children.isNotEmpty)
                      SubcategoryRow(
                        children: children,
                        selectedId: _selectedCategoryId,
                        onSelected: (c) =>
                            setState(() => _selectedCategoryId = c.id),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        // ── 标签选择 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TagSelector(
            selectedIds: _tagIds,
            onChanged: (v) => setState(() => _tagIds = v),
          ),
        ),

        // ── 账户 + 日期 + 备注 ──
        _DetailBar(
          accounts: context.watch<AppRepository>().accounts,
          selectedAccountId: _selectedAccountId,
          date: _date,
          noteController: _noteController,
          onAccountChanged: (id) => setState(() => _selectedAccountId = id),
          onDateChanged: (d) => setState(() => _date = d),
        ),

        // ── 数字键盘 ──
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
// 底部详情栏：账户 + 日期 + 备注
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
        border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          if (accounts.isNotEmpty)
            _AccountButton(
              account: selectedAccount,
              accounts: accounts,
              onChanged: onAccountChanged,
            ),
          const SizedBox(width: 8),
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

// ─────────────────────────────────────────────────────────────────────────────
// 统一圆形工具按钮（透明底 + 淡阴影，对标 Claude）—— iOS 按压手感
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ToolCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
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
// 模式胶囊（透明底 + swap_horiz 前置图标 + 不加粗）—— iOS 按压手感
// ─────────────────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ModePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
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
