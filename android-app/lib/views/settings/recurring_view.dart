import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/money_format.dart';
import '../../widgets/app_buttons.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/recurring_rule.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/transaction_day_list.dart';
import '../common/category_picker_sheet.dart';
import '../common/app_sheet.dart';

String _d2(int n) => n.toString().padLeft(2, '0');
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String _dateStr(DateTime d) => '${d.year}-${_d2(d.month)}-${_d2(d.day)}';

enum _RecurringEndMode { none, date, count }

/// 定时记账(周期记账)管理页:列出规则,可启停、编辑、删除、新增。
class RecurringView extends StatelessWidget {
  const RecurringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('定时记账'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppCircleButton(
                icon: Icons.add,
                onPressed: () => showRecurringEditSheet(context, null)),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final rules = repo.recurringRules;
          if (rules.isEmpty) {
            return const AppEmptyState(
              mood: MascotMood.idle,
              title: '还没有定时记账',
              message: '房租、订阅、工资这类固定收支，设一次自动记',
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
    final book = repo.books.where((b) => b.id == rule.bookId).firstOrNull;
    final catKey = cat?.key ?? '';
    final title = rule.note.isNotEmpty
        ? rule.note
        : (cat?.nameZh ??
            switch (rule.txKind) {
              TransactionKind.income => '收入',
              TransactionKind.transfer => '转账',
              _ => '支出',
            });
    final amtColor = rule.txKind == TransactionKind.income
        ? AppColors.income(scheme)
        : scheme.onSurface;
    // 转账不带正负号：账户间划转不是收也不是支。
    final sign = switch (rule.txKind) {
      TransactionKind.income => '+',
      TransactionKind.transfer => '',
      _ => '-',
    };
    final amtText = '$sign${MoneyFormat.string(rule.amount)}';

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
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [
                        rule.recurPeriod.label,
                        if (book != null) book.name,
                        '下次 ${_dateStr(rule.nextDue)}',
                      ].join(' · '),
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
              AppSwitch(
                value: rule.enabled,
                semanticLabel: '启用$title定时记账',
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
Future<void> showRecurringEditSheet(BuildContext context, RecurringRule? rule) {
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
  late final TextEditingController _countCtrl;
  int? _categoryId;
  int? _accountId;

  /// 仅转账规则用（A3 房贷向导创建的自动还款）。表单里转账不提供
  /// 收/支切换——kind 保持 transfer，改的是转出/转入账户。
  int? _toAccountId;
  int? _bookId;
  late RecurPeriod _period;
  late DateTime _startDate;
  late _RecurringEndMode _endMode;
  DateTime? _endDate;

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
    _toAccountId = r?.toAccountId;
    _bookId = r?.bookId;
    _period = r?.recurPeriod ?? RecurPeriod.monthly;
    _startDate = _dateOnly(r?.startDate ?? DateTime.now());
    _endDate = r?.endDate == null ? null : _dateOnly(r!.endDate!);
    _countCtrl = TextEditingController(text: r?.totalCount?.toString() ?? '');
    _endMode = r?.totalCount != null
        ? _RecurringEndMode.count
        : (r?.endDate != null
            ? _RecurringEndMode.date
            : _RecurringEndMode.none);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  int? get _countLimit => int.tryParse(_countCtrl.text.trim());

  bool get _isTransfer => _kind == TransactionKind.transfer;

  bool get _endConfigValid {
    return switch (_endMode) {
      _RecurringEndMode.none => true,
      _RecurringEndMode.date => _endDate != null &&
          !_endDate!.isBefore(DateTime(
            _startDate.year,
            _startDate.month,
            _startDate.day,
          )),
      _RecurringEndMode.count => (_countLimit ?? 0) > 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.read<AppRepository>();
    // 转账规则没有分类语义，别去查分类树。
    final cats = _isTransfer
        ? const <CategoryEntity>[]
        : repo.categoriesForKind(_kind).where((c) => !c.hidden).toList();
    final accounts = repo.transactionAccounts;
    final books = repo.books;
    if (_bookId == null || !books.any((b) => b.id == _bookId)) {
      _bookId = repo.currentBookId;
    }
    // 账户:为空或指向已删除账户时,回落到第一个(否则 Dropdown 会断言崩)。
    if (_accountId == null || !accounts.any((a) => a.id == _accountId)) {
      _accountId = accounts.firstOrNull?.id;
    }
    // 转入账户失效时清空，如实呈现「没选」，不悄悄换成别的账户。
    if (_toAccountId != null && !accounts.any((a) => a.id == _toAccountId)) {
      _toAccountId = null;
    }
    // 若当前选中分类不在本类型下,清空。这里必须包含二级分类:
    // 用户常选「房租」这类子分类,只校验一级分类会在返回后立刻被清空。
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    final amount = Decimal.tryParse(_amountCtrl.text.trim());
    final valid = amount != null &&
        amount > Decimal.zero &&
        _accountId != null &&
        _bookId != null &&
        (!_isTransfer ||
            (_toAccountId != null && _toAccountId != _accountId)) &&
        _endConfigValid;
    final selCat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final selAcc = accounts.where((a) => a.id == _accountId).firstOrNull;
    final selToAcc = accounts.where((a) => a.id == _toAccountId).firstOrNull;
    final selBook = books.where((b) => b.id == _bookId).firstOrNull;
    final screenH = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: widget.rule == null ? '新增定时记账' : '编辑定时记账',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? () => _save(repo) : null,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 收支（转账规则不给切收/支：kind 保持 transfer，
                  // 表单改成转出/转入账户两个字段）
                  if (_isTransfer)
                    const AppLabeledField(
                      label: '类型',
                      child: AppReadOnlyField(
                        text: '转账（账户间划转）',
                        icon: Icons.swap_horiz_rounded,
                      ),
                    )
                  else
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    onChanged: (_) => setState(() {}),
                    decoration: iosInputDecoration(context,
                        hint: '如 1300', prefix: '¥ '),
                  ),
                  const SizedBox(height: 14),

                  // 分类 + 账户（showIosMenu 选择，同全局设计）；
                  // 转账规则改成 转出账户 + 转入账户。
                  if (_isTransfer)
                    Row(
                      children: [
                        Expanded(
                          child: AppLabeledField(
                            label: '转出账户',
                            child: AppPickerField(
                              text: selAcc?.name,
                              hint: '选择账户',
                              onTap: (menuCtx) => showPickerMenu(menuCtx, [
                                for (final a in accounts)
                                  IosMenuItem(
                                    label: a.name,
                                    icon:
                                        Icons.account_balance_wallet_outlined,
                                    selected: a.id == _accountId,
                                    onTap: () =>
                                        setState(() => _accountId = a.id),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppLabeledField(
                            label: '转入账户',
                            child: AppPickerField(
                              text: selToAcc?.name,
                              hint: '选择账户',
                              onTap: (menuCtx) => showPickerMenu(menuCtx, [
                                for (final a in accounts)
                                  if (a.id != _accountId)
                                    IosMenuItem(
                                      label: a.name,
                                      icon: Icons
                                          .account_balance_wallet_outlined,
                                      selected: a.id == _toAccountId,
                                      onTap: () =>
                                          setState(() => _toAccountId = a.id),
                                    ),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                  Row(
                    children: [
                      Expanded(
                        child: AppLabeledField(
                          label: '分类',
                          child: AppPickerField(
                            text: selCat?.nameZh,
                            hint: '选择分类',
                            leading: selCat == null
                                ? null
                                : CatIcon(
                                    categoryKey: selCat.key,
                                    emoji: CategorySeed.emojiOf(selCat.key),
                                    size: 20,
                                  ),
                            onTap: (menuCtx) async {
                              final picked = await showCategoryPickerSheet(
                                context,
                                kind: _kind,
                                selectedId: _categoryId,
                                title: _kind == TransactionKind.income
                                    ? '选择收入分类'
                                    : '选择支出分类',
                              );
                              if (picked != null && mounted) {
                                setState(() => _categoryId = picked.id);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppLabeledField(
                          label: '账户',
                          child: AppPickerField(
                            text: selAcc?.name,
                            hint: '选择账户',
                            onTap: (menuCtx) => showPickerMenu(menuCtx, [
                              for (final a in accounts)
                                IosMenuItem(
                                  label: a.name,
                                  icon: Icons.account_balance_wallet_outlined,
                                  selected: a.id == _accountId,
                                  onTap: () =>
                                      setState(() => _accountId = a.id),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '账本',
                    child: AppPickerField(
                      text: selBook?.name,
                      hint: '选择账本',
                      onTap: (menuCtx) => showPickerMenu(menuCtx, [
                        for (final b in books)
                          IosMenuItem(
                            label: b.name,
                            icon: Icons.menu_book_outlined,
                            selected: b.id == _bookId,
                            onTap: () => setState(() => _bookId = b.id),
                          ),
                      ]),
                    ),
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
                  AppLabeledField(
                    label: '起始日期',
                    child: AppPickerField(
                      text: _dateStr(_startDate),
                      hint: '选择日期',
                      trailingIcon: Icons.calendar_today_outlined,
                      onTap: (_) async {
                        final picked = await showAppDatePicker(
                          context,
                          initial: _startDate,
                          first: DateTime(2015),
                          last: DateTime(2100),
                          title: '开始日期',
                        );
                        if (picked != null) {
                          setState(() => _startDate = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text('结束方式',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  SlidingSegment<_RecurringEndMode>(
                    items: const [
                      (_RecurringEndMode.none, '不限'),
                      (_RecurringEndMode.date, '结束日期'),
                      (_RecurringEndMode.count, '记录次数'),
                    ],
                    value: _endMode,
                    onChanged: (v) {
                      Haptics.selection();
                      setState(() {
                        _endMode = v;
                        if (v == _RecurringEndMode.date) {
                          _endDate ??= _startDate;
                        }
                      });
                    },
                  ),
                  if (_endMode == _RecurringEndMode.date) ...[
                    const SizedBox(height: 8),
                    PressableScale(
                      onPressed: () async {
                        final picked = await showAppDatePicker(
                          context,
                          initial: _endDate ?? _startDate,
                          first: _startDate,
                          last: DateTime(2100),
                          title: '结束日期',
                        );
                        if (picked != null) setState(() => _endDate = picked);
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
                            Text(
                              _endDate == null ? '选择结束日期' : _dateStr(_endDate!),
                              style: TextStyle(
                                fontSize: 14,
                                color: _endDate == null
                                    ? scheme.onSurfaceVariant
                                    : scheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.calendar_today_outlined,
                                size: 16, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_endMode == _RecurringEndMode.count) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: iosInputDecoration(context, hint: '如 12')
                          .copyWith(suffixText: '次'),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 备注
                  Text('备注（可选）',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteCtrl,
                    decoration: iosInputDecoration(context, hint: '如 房租还贷'),
                  ),
                  if (widget.rule != null) ...[
                    const SizedBox(height: 14),
                    _RecurringRecordedStatus(
                      rule: widget.rule!,
                      records:
                          repo.transactionsForRecurringRule(widget.rule!.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.rule != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
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
                        color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    '删除',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(AppRepository repo) async {
    final amount = Decimal.parse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim();
    final startDate = _dateOnly(_startDate);
    final endDate = _endMode == _RecurringEndMode.date && _endDate != null
        ? _dateOnly(_endDate!)
        : null;
    final totalCount = _endMode == _RecurringEndMode.count ? _countLimit : null;
    final nextDue = widget.rule == null || widget.rule!.generatedCount == 0
        ? startDate
        : widget.rule!.nextDue;
    if (widget.rule == null) {
      await repo.addRecurringRule(
        kind: _kind,
        amount: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        toAccountId: _isTransfer ? _toAccountId : null,
        bookId: _bookId,
        note: note,
        period: _period,
        startDate: startDate,
        endDate: endDate,
        totalCount: totalCount,
      );
    } else {
      await repo.updateRecurringRule(
        id: widget.rule!.id,
        kind: _kind,
        amount: amount,
        categoryId: _categoryId,
        accountId: _accountId,
        toAccountId: _isTransfer ? _toAccountId : null,
        bookId: _bookId,
        note: note,
        period: _period,
        startDate: startDate,
        nextDue: nextDue,
        endDate: endDate,
        totalCount: totalCount,
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class _RecurringRecordedStatus extends StatelessWidget {
  final RecurringRule rule;
  final List<TransactionEntity> records;

  const _RecurringRecordedStatus({
    required this.rule,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = records.reversed.take(3).toList();
    final countText = rule.totalCount == null
        ? '${rule.generatedCount} 次'
        : '${rule.generatedCount}/${rule.totalCount} 次';
    final statusText =
        rule.isCompleted ? '已完成' : (rule.enabled ? '进行中' : '已停用');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.34),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '已记录情况',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '开始 ${_dateStr(rule.startDate)} · 已记录 $countText',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'Nunito',
                  ),
                ),
              ],
            ),
          ),
          if (latest.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '还没有生成账单',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            )
          else
            for (var i = 0; i < latest.length; i++) ...[
              if (i > 0)
                Container(
                  margin: const EdgeInsets.only(left: 58, right: 14),
                  height: 0.5,
                  color: scheme.outlineVariant.withValues(alpha: 0.42),
                ),
              TxRow(transaction: latest[i], dateGrouped: false),
            ],
        ],
      ),
    );
  }
}
