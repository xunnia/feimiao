import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/recurring_rule.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';

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
/// 走全局模糊弹层（同类大弹层同一设计）。
Future<void> showRecurringEditSheet(
    BuildContext context, RecurringRule? rule) {
  return showBlurSheet<void>(context, child: _RecurringEditSheet(rule: rule));
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
    final selCat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final selAcc = accounts.where((a) => a.id == _accountId).firstOrNull;
    final screenH = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                Text(widget.rule == null ? '新增定时记账' : '编辑定时记账',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                PressableScale(
                  onPressed: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close,
                        size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 收支
                  Center(
                    child: SizedBox(
                      width: 200,
                      child: SlidingSegment<TransactionKind>(
                        items: const [
                          (TransactionKind.expense, '支出'),
                          (TransactionKind.income, '收入'),
                        ],
                        value: _kind,
                        onChanged: (v) {
                          Haptics.selection();
                          setState(() {
                            _kind = v;
                            _categoryId = null;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 金额
                  Text('金额',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: iosInputDecoration(context,
                        hint: '如 1300', prefix: '¥ '),
                  ),
                  const SizedBox(height: 14),

                  // 分类 + 账户（showIosMenu 选择，同全局设计）
                  Row(
                    children: [
                      Expanded(
                        child: _PickerField(
                          label: '分类',
                          value: selCat == null
                              ? '选择分类'
                              : '${CategorySeed.emojiOf(selCat.key)} ${selCat.nameZh}',
                          placeholder: selCat == null,
                          onTapMenu: (menuCtx) => showIosMenu(menuCtx, [
                            for (final c in cats)
                              IosMenuItem(
                                label:
                                    '${CategorySeed.emojiOf(c.key)} ${c.nameZh}',
                                icon: c.id == _categoryId
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                onTap: () =>
                                    setState(() => _categoryId = c.id),
                              ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PickerField(
                          label: '账户',
                          value: selAcc?.name ?? '选择账户',
                          placeholder: selAcc == null,
                          onTapMenu: (menuCtx) => showIosMenu(menuCtx, [
                            for (final a in accounts)
                              IosMenuItem(
                                label: a.name,
                                icon: a.id == _accountId
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                onTap: () =>
                                    setState(() => _accountId = a.id),
                              ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 周期
                  Text('周期',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  SlidingSegment<RecurPeriod>(
                    items: const [
                      (RecurPeriod.daily, '每天'),
                      (RecurPeriod.weekly, '每周'),
                      (RecurPeriod.monthly, '每月'),
                      (RecurPeriod.yearly, '每年'),
                    ],
                    value: _period,
                    onChanged: (v) {
                      Haptics.selection();
                      setState(() => _period = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  // 起始日期
                  Text('起始日期',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  PressableScale(
                    onPressed: () async {
                      final picked = await showAppDatePicker(
                        context,
                        initial: _startDate,
                        first: DateTime(2015),
                        last: DateTime(2100),
                        title: '开始日期',
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputFill(scheme),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(_dateStr(_startDate),
                              style: TextStyle(
                                  fontSize: 14, color: scheme.onSurface)),
                          const Spacer(),
                          Icon(Icons.calendar_today_outlined,
                              size: 16, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 备注
                  Text('备注（可选）',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteCtrl,
                    decoration:
                        iosInputDecoration(context, hint: '如 房租还贷'),
                  ),
                ],
              ),
            ),
          ),
          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(
              children: [
                if (widget.rule != null) ...[
                  Expanded(
                    child: PressableScale(
                      onPressed: () async {
                        await repo.deleteRecurringRule(widget.rule!.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.card(scheme),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: scheme.error.withValues(alpha: 0.5)),
                        ),
                        child: Text('删除',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: scheme.error)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: PressableScale(
                    onPressed: valid ? () => _save(repo) : null,
                    child: Opacity(
                      opacity: valid ? 1 : 0.4,
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('保存',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: scheme.surface)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

/// 标签 + 值的选择框：点开走 showIosMenu（对齐全局设计，替代原生 Dropdown）。
class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final bool placeholder;
  final void Function(BuildContext menuCtx) onTapMenu;

  const _PickerField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTapMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Builder(
          builder: (menuCtx) => PressableScale(
            onPressed: () => onTapMenu(menuCtx),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.inputFill(scheme),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: placeholder
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
