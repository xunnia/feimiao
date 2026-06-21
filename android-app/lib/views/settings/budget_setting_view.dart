import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/models/transaction_record.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';

/// 预算设置页：月度总预算 + 分类预算（按大类）。
class BudgetSettingView extends StatefulWidget {
  const BudgetSettingView({super.key});

  @override
  State<BudgetSettingView> createState() => _BudgetSettingViewState();
}

class _BudgetSettingViewState extends State<BudgetSettingView> {
  final TextEditingController _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final budget = context.read<AppRepository>().monthlyBudget;
      if (budget != null && budget > Decimal.zero) {
        _amountCtrl.text = budget.toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _amountCtrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) return;
    final Decimal amount;
    try {
      amount = Decimal.parse(raw);
    } catch (_) {
      return;
    }
    if (amount < Decimal.zero) return;
    await context.read<AppRepository>().saveMonthlyBudget(amount);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('预算已保存'),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算'), centerTitle: true),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final budget = repo.monthlyBudget;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InputSection(
                controller: _amountCtrl,
                onSave: _save,
              ),
              const SizedBox(height: 8),
              Text(
                '设置后，记账页会按「(月预算 − 已花) ÷ 剩余天数」实时显示今日可花额度。设为 0 关闭预算。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (budget != null && budget > Decimal.zero) ...[
                const SizedBox(height: 24),
                _MonthProgressCard(
                  monthlyBudget: budget,
                  records: repo.allRecords,
                ),
              ],

              // ── 分类预算 ──
              const SizedBox(height: 28),
              _CategoryBudgetSection(repo: repo),
            ],
          );
        },
      ),
    );
  }
}

class _InputSection extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSave;

  const _InputSection({
    required this.controller,
    required this.onSave,
  });

  @override
  State<_InputSection> createState() => _InputSectionState();
}

class _InputSectionState extends State<_InputSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Decimal? get _parsed {
    final raw = widget.controller.text.replaceAll(',', '').trim();
    if (raw.isEmpty) return null;
    try {
      return Decimal.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = _parsed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '月度总预算',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '月度预算金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (parsed != null && parsed >= Decimal.zero)
                ? widget.onSave
                : null,
            child: const Text('保存预算'),
          ),
        ],
      ),
    );
  }
}

class _MonthProgressCard extends StatelessWidget {
  final Decimal monthlyBudget;
  final List<TransactionRecord> records;

  const _MonthProgressCard({
    required this.monthlyBudget,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = BudgetEngine.status(
      monthlyBudget: monthlyBudget,
      records: records,
    );
    final ratio = (MoneyFormat.toDouble(status.spentThisMonth) /
            MoneyFormat.toDouble(monthlyBudget).clamp(0.01, double.infinity))
        .clamp(0.0, 1.0);
    final isOver = status.isOverBudget;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本月进度',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '本月已花 ${MoneyFormat.string(status.spentThisMonth)} / 预算 ${MoneyFormat.string(monthlyBudget)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOver
                            ? AppColors.warning
                            : scheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: isOver ? AppColors.warning : scheme.primary,
              backgroundColor: scheme.outlineVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status.todayAllowance >= Decimal.zero
                ? '今日还可以花 ${MoneyFormat.string(status.todayAllowance)}'
                : '今日已超 ${MoneyFormat.string(-status.todayAllowance)}，缓一缓',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: status.todayAllowance >= Decimal.zero
                      ? scheme.onSurfaceVariant
                      : AppColors.warning,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分类预算（按大类）
// ---------------------------------------------------------------------------

class _CategoryBudgetSection extends StatelessWidget {
  final AppRepository repo;

  const _CategoryBudgetSection({required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tops = repo
        .categoriesForKindRanked(TransactionKind.expense); // 仅顶级大类

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分类预算',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '给单个大类单独设预算，点一行即可设置。本月该类（含子类）花费会实时显示进度。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tops.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 56,
                      color: scheme.outlineVariant.withValues(alpha: 0.4)),
                _CategoryBudgetTile(repo: repo, category: tops[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBudgetTile extends StatelessWidget {
  final AppRepository repo;
  final CategoryEntity category;

  const _CategoryBudgetTile({required this.repo, required this.category});

  Future<void> _edit(BuildContext context) async {
    final existing = repo.categoryBudgetFor(category.key);
    final ctrl = TextEditingController(
        text: existing != null ? existing.toStringAsFixed(2) : '');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${category.nameZh}」预算'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '月预算金额',
            prefixText: '¥ ',
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              child: Text('清除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (action == null) return;
    if (action == '__clear__') {
      await repo.saveCategoryBudget(category.key, Decimal.zero);
      return;
    }
    final v = Decimal.tryParse(action.replaceAll(',', '').trim()) ?? Decimal.zero;
    await repo.saveCategoryBudget(category.key, v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budget = repo.categoryBudgetFor(category.key);
    final spent = repo.monthSpentForTopCategory(category.id);
    final hasBudget = budget != null && budget > Decimal.zero;
    final ratio = hasBudget
        ? (spent / budget)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;
    final over = hasBudget && spent > budget;

    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            CatIcon(
              categoryKey: category.key,
              emoji: CategorySeed.emojiOf(category.key),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(category.nameZh,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                      Text(
                        hasBudget
                            ? '${MoneyFormat.string(spent)} / ${MoneyFormat.string(budget)}'
                            : '未设',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: over
                                  ? AppColors.warning
                                  : scheme.onSurfaceVariant,
                              // ignore: deprecated_member_use
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                      ),
                    ],
                  ),
                  if (hasBudget) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        color: over ? AppColors.warning : scheme.primary,
                        backgroundColor: scheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_forward, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
