import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/recurring_rule.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/mascot.dart';

String _d2(int n) => n.toString().padLeft(2, '0');
String _dateStr(DateTime d) => '${d.year}-${_d2(d.month)}-${_d2(d.day)}';

/// 定时记账(周期记账)管理页:列出规则,可启停、编辑、删除、新增。
class RecurringView extends StatelessWidget {
  const RecurringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('定时记账'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增规则',
            onPressed: () => showRecurringEditSheet(context, null),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final rules = repo.recurringRules;
          if (rules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(mood: MascotMood.idle, size: 72, animate: true),
                  const SizedBox(height: 12),
                  Text('还没有定时记账',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    '房租、订阅、工资这类固定收支,设一次自动记',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              for (final r in rules) _RuleCard(rule: r, repo: repo),
            ],
          );
        },
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final RecurringRule rule;
  final AppRepository repo;

  const _RuleCard({required this.rule, required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat =
        repo.categories.where((c) => c.id == rule.categoryId).firstOrNull;
    final catKey = cat?.key ?? '';
    final title = rule.note.isNotEmpty
        ? rule.note
        : (cat?.nameZh ?? (rule.txKind == TransactionKind.income ? '收入' : '支出'));
    final amtColor = rule.txKind == TransactionKind.income
        ? AppColors.income(scheme)
        : scheme.onSurface;
    final amtText =
        '${rule.txKind == TransactionKind.income ? '+' : '-'}¥${rule.amount}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showRecurringEditSheet(context, rule),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              CatIcon(
                  categoryKey: catKey,
                  emoji: catKey.isEmpty ? '🔁' : CategorySeed.emojiOf(catKey),
                  size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${rule.recurPeriod.label} · 下次 ${_dateStr(rule.nextDue)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                amtText,
                style: TextStyle(
                  color: rule.enabled ? amtColor : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Nunito',
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: rule.enabled,
                onChanged: (v) => repo.setRecurringEnabled(rule.id, v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新增 / 编辑周期规则表单。[rule] 为 null 时新增。
Future<void> showRecurringEditSheet(
    BuildContext context, RecurringRule? rule) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecurringEditSheet(rule: rule),
  );
}

class _RecurringEditSheet extends StatefulWidget {
  final RecurringRule? rule;
  const _RecurringEditSheet({required this.rule});

  @override
  State<_RecurringEditSheet> createState() => _RecurringEditSheetState();
}

class _RecurringEditSheetState extends State<_RecurringEditSheet> {
  late TransactionKind _kind;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  int? _categoryId;
  int? _accountId;
  late RecurPeriod _period;
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _kind = r?.txKind ?? TransactionKind.expense;
    _amountCtrl =
        TextEditingController(text: r == null ? '' : r.amount.toString());
    _noteCtrl = TextEditingController(text: r?.note ?? '');
    _categoryId = r?.categoryId;
    _accountId = r?.accountId;
    _period = r?.recurPeriod ?? RecurPeriod.monthly;
    _startDate = r?.nextDue ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.read<AppRepository>();
    final cats = repo.categoriesForKind(_kind);
    final accounts = repo.accounts;
    // 账户:为空或指向已删除账户时,回落到第一个(否则 Dropdown 会断言崩)。
    if (_accountId == null || !accounts.any((a) => a.id == _accountId)) {
      _accountId = accounts.firstOrNull?.id;
    }
    // 若当前选中分类不在本类型下,清空
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    final amount = Decimal.tryParse(_amountCtrl.text.trim());
    final valid = amount != null && amount > Decimal.zero && _accountId != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.rule == null ? '新增定时记账' : '编辑定时记账',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),

              // 收支
              SegmentedButton<TransactionKind>(
                segments: const [
                  ButtonSegment(
                      value: TransactionKind.expense, label: Text('支出')),
                  ButtonSegment(
                      value: TransactionKind.income, label: Text('收入')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 12),

              // 金额
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '金额',
                  prefixText: '¥ ',
                ),
              ),
              const SizedBox(height: 12),

              // 分类
              DropdownButtonFormField<int>(
                value:_categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text('${CategorySeed.emojiOf(c.key)} ${c.nameZh}'),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),

              // 账户
              DropdownButtonFormField<int>(
                value:_accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '账户'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 12),

              // 周期
              Align(
                alignment: Alignment.centerLeft,
                child: Text('周期',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ),
              const SizedBox(height: 6),
              SegmentedButton<RecurPeriod>(
                segments: const [
                  ButtonSegment(value: RecurPeriod.daily, label: Text('每天')),
                  ButtonSegment(value: RecurPeriod.weekly, label: Text('每周')),
                  ButtonSegment(value: RecurPeriod.monthly, label: Text('每月')),
                  ButtonSegment(value: RecurPeriod.yearly, label: Text('每年')),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const SizedBox(height: 12),

              // 起始 / 下次日期
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('起始日期'),
                subtitle: Text(_dateStr(_startDate)),
                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _startDate = picked);
                },
              ),
              const SizedBox(height: 4),

              // 备注
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: '备注(可选)'),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  if (widget.rule != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await repo.deleteRecurringRule(widget.rule!.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                              color: scheme.error.withValues(alpha: 0.5)),
                        ),
                        child: const Text('删除'),
                      ),
                    ),
                  if (widget.rule != null) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: valid ? () => _save(repo) : null,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(AppRepository repo) async {
    final amount = Decimal.parse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim();
    if (widget.rule == null) {
      await repo.addRecurringRule(
        kind: _kind,
        amount: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        note: note,
        period: _period,
        startDate: _startDate,
      );
    } else {
      await repo.updateRecurringRule(
        id: widget.rule!.id,
        kind: _kind,
        amount: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        note: note,
        period: _period,
        nextDue: _startDate,
      );
    }
    if (mounted) Navigator.pop(context);
  }
}
