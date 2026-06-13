import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/transaction_record.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';

/// 月度预算设置子页。
///
/// 顶部输入框设置金额，已设置时显示本月执行进度卡片。
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
      appBar: AppBar(title: const Text('月度预算'), centerTitle: true),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final budget = repo.monthlyBudget;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 输入区
              _InputSection(
                controller: _amountCtrl,
                onSave: _save,
              ),
              const SizedBox(height: 8),
              Text(
                '设置后，记账页会按「(月预算 − 已花) ÷ 剩余天数」实时显示今日可花额度，超速消费当天就能看到，而不是月底才发现超支。设为 0 关闭预算。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              // 本月进度卡片
              if (budget != null && budget > Decimal.zero) ...[
                const SizedBox(height: 24),
                _MonthProgressCard(
                  monthlyBudget: budget,
                  records: repo.allRecords,
                ),
              ],
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
