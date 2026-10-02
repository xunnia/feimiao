import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_clock.dart';
import '../../core/budget/budget_rule_calendar.dart';
import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rule_status.dart';
import '../../core/budget/budget_rules.dart';
import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';
import 'budget_calendar_card.dart' show BudgetMonthArrow;
import 'budget_rule_colors.dart';

/// 新增 / 编辑预算规则（docs/08 §6.9）。
/// [suggestionYuan]：第一次新建时预填的近 3 月平均建议。
Future<void> showBudgetRuleSheet(
  BuildContext context, {
  required int bookId,
  BudgetRule? rule,
  int? suggestionYuan,
}) =>
    showBlurSheet<void>(
      context,
      child: BudgetRuleSheet(
        bookId: bookId,
        rule: rule,
        suggestionYuan: suggestionYuan,
      ),
    );

class BudgetRuleSheet extends StatefulWidget {
  final int bookId;
  final BudgetRule? rule;
  final int? suggestionYuan;

  const BudgetRuleSheet({
    super.key,
    required this.bookId,
    this.rule,
    this.suggestionYuan,
  });

  @override
  State<BudgetRuleSheet> createState() => _BudgetRuleSheetState();
}

class _BudgetRuleSheetState extends State<BudgetRuleSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late BudgetRuleUnit _unit;
  late bool _dated;
  DateTime? _start;
  DateTime? _end;
  late BudgetFunding _funding;
  late final int _draftCreatedMs;
  late DateTime _pickerMonth;
  bool _saving = false;
  bool _confirming = false;
  String? _error;

  BudgetRule? get _rule => widget.rule;
  bool get _isEdit => _rule != null;

  @override
  void initState() {
    super.initState();
    final rule = _rule;
    final today = AppClock.now;
    _name = TextEditingController(text: rule?.name ?? '');
    _amount = TextEditingController(
      text: rule != null
          ? '${rule.amountYuan}'
          : widget.suggestionYuan != null
              ? '${widget.suggestionYuan}'
              : '',
    );
    _unit = rule?.unit ?? BudgetRuleUnit.month;
    _dated = rule != null && !rule.isBase;
    _start = rule?.isBase == false ? rule!.startDate : null;
    _end = rule?.isBase == false ? rule!.endDate : null;
    _funding = rule?.funding ?? BudgetFunding.carve;
    _draftCreatedMs = rule?.createdMs ?? DateTime.now().millisecondsSinceEpoch;
    final anchor = _start ?? today;
    _pickerMonth = DateTime(anchor.year, anchor.month);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  int? get _amountYuan {
    final value = int.tryParse(_amount.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  DateTime? get _rangeEnd => _end ?? _start;

  List<BudgetRule> _others(AppRepository repo) => [
        for (final rule in repo.budgetRulesForBook(widget.bookId))
          if (rule.id != _rule?.id) rule,
      ];

  /// 选的日子里有没有日常预算管着；一天都没有时只能「额外多给」（§6.5）。
  bool _hasBaseInRange(List<BudgetRule> others) {
    final start = _start;
    final end = _rangeEnd;
    if (start == null || end == null) return true;
    final calendar = BudgetRuleCalendar(others);
    for (var d = start; !d.isAfter(end); d = budgetAddDays(d, 1)) {
      if (calendar.baseOwner(d) != null) return true;
    }
    return false;
  }

  BudgetFunding _effectiveFunding(List<BudgetRule> others) =>
      _hasBaseInRange(others) ? _funding : BudgetFunding.extra;

  BudgetRule? _candidate(List<BudgetRule> others) {
    final yuan = _amountYuan;
    if (yuan == null) return null;
    final today = AppClock.now;
    if (!_dated) {
      return BudgetRule(
        id: _rule?.id ?? 0,
        uuid: _rule?.uuid ?? '',
        bookId: widget.bookId,
        kind: BudgetRuleKind.base,
        name: _name.text.trim(),
        amountCents: yuan * 100,
        unit: _unit,
        startDate: _rule?.isBase == true
            ? _rule!.startDate
            : DateTime(today.year, today.month, 1),
        createdMs: _draftCreatedMs,
      );
    }
    final start = _start;
    final end = _rangeEnd;
    if (start == null || end == null) return null;
    return BudgetRule(
      id: _rule?.id ?? 0,
      uuid: _rule?.uuid ?? '',
      bookId: widget.bookId,
      kind: BudgetRuleKind.special,
      name: _name.text.trim(),
      amountCents: yuan * 100,
      unit: _unit,
      startDate: start,
      endDate: end,
      funding: _effectiveFunding(others),
      colorIndex: _rule?.colorIndex ?? 0,
      createdMs: _draftCreatedMs,
    );
  }

  Future<void> _save(AppRepository repo, {BudgetFunding? forceFunding}) async {
    if (_saving || _confirming) return;
    final yuan = _amountYuan;
    if (yuan == null) {
      setState(() => _error = '填一个大于 0 的整数金额');
      return;
    }
    if (_dated && _start == null) {
      setState(() => _error = '在日历上点一下开始和结束的日子');
      return;
    }
    final others = _others(repo);
    final warning = _dated
        ? null
        : budgetBaseEditWarning(
            original: _rule,
            existing: repo.budgetRulesForBook(widget.bookId),
            amountCents: yuan * 100,
            unit: _unit,
            today: AppClock.now,
          );
    final today = AppClock.now;
    final startsBeforeThisMonth = _rule != null &&
        _rule!.startDate.isBefore(DateTime(today.year, today.month));
    if (warning != null && startsBeforeThisMonth) {
      setState(() => _confirming = true);
      bool ok;
      try {
        ok = await showConfirmDialog(
          context,
          title: '改日常预算',
          message: warning,
          confirmText: '改',
        );
      } finally {
        if (mounted) setState(() => _confirming = false);
      }
      if (!ok || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.saveBudgetRule(
        id: _rule?.id,
        bookId: widget.bookId,
        kind: _dated ? BudgetRuleKind.special : BudgetRuleKind.base,
        name: _name.text.trim(),
        amountYuan: yuan,
        unit: _unit,
        startDate: _dated ? _start : null,
        endDate: _dated ? _rangeEnd : null,
        funding: forceFunding ?? _effectiveFunding(others),
      );
      if (!mounted) return;
      Haptics.of(Haptic.success);
      showAppToast(context, _isEdit ? '已保存' : '已添加');
      Navigator.of(context).pop();
    } on BudgetRuleValidationException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final ok = await showConfirmDialog(
        context,
        title: '改成额外多给吗？',
        message: e.toString(),
        confirmText: '改成额外多给',
      );
      if (!ok || !mounted) return;
      setState(() => _funding = BudgetFunding.extra);
      await _save(repo, forceFunding: BudgetFunding.extra);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ArgumentError ? '${e.message}' : '没保存成功，再试一次';
      });
    }
  }

  Future<void> _delete(AppRepository repo) async {
    final rule = _rule;
    if (rule == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除「${budgetRuleName(rule)}」？',
      message: rule.isBase ? '它管的日子会交还给它之前的那条日常预算；前面没有就没有预算。' : '这几天会回到日常预算。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await repo.deleteBudgetRule(rule.id);
    if (!mounted) return;
    showAppToast(context, '已删除');
    Navigator.of(context).pop();
  }

  void _tapDay(DateTime day) {
    Haptics.selection();
    setState(() {
      _error = null;
      final start = _start;
      if (start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(start)) {
        _start = day;
        _end = start;
      } else {
        _end = day;
      }
    });
  }

  bool get _rangeComplete => _start != null && _end != null;

  String _rangeText() {
    final start = _start;
    final end = _rangeEnd;
    if (start == null || end == null) return '点一下开始的日子，再点结束的日子';
    final days = budgetDaysBetween(start, end) + 1;
    final head = '${start.month}月${start.day}日';
    if (days == 1) return '$head · 1 天${_end == null ? '（再点一下选结束）' : ''}';
    final tail = start.month == end.month && start.year == end.year
        ? '${end.day}日'
        : '${end.month}月${end.day}日';
    return '$head–$tail · $days 天';
  }

  String _fundingSourceLabel() {
    final start = _start;
    final end = _rangeEnd;
    if (start != null &&
        end != null &&
        start.year == end.year &&
        start.month == end.month) {
      return '从${start.month}月预算里匀';
    }
    return '从月预算里匀';
  }

  static const _units = [
    (BudgetRuleUnit.day, '每天'),
    (BudgetRuleUnit.week, '每周'),
    (BudgetRuleUnit.month, '每月'),
    (BudgetRuleUnit.year, '每年'),
  ];

  String _baseCaption(AppRepository repo) {
    final today = AppClock.now;
    final rule = _rule;
    if (rule != null && rule.isBase) {
      final span =
          budgetRuleSpan(rule, repo.budgetRulesForBook(widget.bookId), today);
      return span.text == '没有生效过' ? span.text : '${span.text}有效';
    }
    final hasBase = _others(repo).any((r) => r.isBase);
    return hasBase
        ? '从${today.month}月 1 号起按这个算，之前的月份不变'
        : '从${today.month}月 1 号起一直有效';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final others = _others(repo);
    final candidate = _candidate(others);
    final preview = candidate == null
        ? const <BudgetRulePreviewLine>[]
        : budgetRulePreview(
            existing: repo.budgetRulesForBook(widget.bookId),
            candidate: candidate,
            today: AppClock.now,
          );
    final baseWarning = !_dated && candidate != null
        ? budgetBaseEditWarning(
            original: _rule,
            existing: repo.budgetRulesForBook(widget.bookId),
            amountCents: candidate.amountCents,
            unit: _unit,
            today: AppClock.now,
          )
        : null;
    final hasBase = _hasBaseInRange(others);
    final prefilled = !_isEdit &&
        widget.suggestionYuan != null &&
        _amount.text.trim() == '${widget.suggestionYuan}';
    final screenH = MediaQuery.sizeOf(context).height;
    // 这条规则（保存后）会用的颜色：日常预算用主色，特别安排用它在色板里的颜色。
    final accent = !_dated
        ? scheme.primary
        : budgetRulePalette[(_rule != null && !_rule!.isBase
                ? _rule!.colorIndex
                : others.where((r) => !r.isBase).length) %
            budgetRulePalette.length];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: _isEdit ? '编辑规则' : '新增规则',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            actionKey: const ValueKey('budget-rule-save'),
            onAction: _saving || _confirming ? null : () => _save(repo),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 示意图顺序：名称 → 预算 → 单位 → 时间（一直有效/选日期）→ 日历 → 预览。
                  // 名称一直在，切「选日期」时上面的东西不会跳。
                  AppLabeledField(
                    label: '名称',
                    child: TextField(
                      key: const ValueKey('budget-rule-name'),
                      controller: _name,
                      maxLength: 20,
                      onChanged: (_) => setState(() {}),
                      decoration: iosInputDecoration(
                        context,
                        hint: _dated ? '如 国庆出游（可以不填）' : '日常（可以不填）',
                      ).copyWith(counterText: ''),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '预算',
                    helperText: prefilled ? '按近 3 个月平均支出预填的，可以改' : null,
                    child: TextField(
                      key: const ValueKey('budget-rule-amount'),
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      onChanged: (_) => setState(() => _error = null),
                      decoration: iosInputDecoration(
                        context,
                        hint: '整数，如 4000',
                        prefix: '¥ ',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SlidingSegment<BudgetRuleUnit>(
                      key: const ValueKey('budget-rule-unit'),
                      items: _units,
                      value: _unit,
                      onChanged: (v) {
                        Haptics.selection();
                        setState(() => _unit = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('时间',
                      style: AppType.secondary(scheme).copyWith(height: 1)),
                  const SizedBox(height: 7),
                  if (!_isEdit)
                    SizedBox(
                      width: double.infinity,
                      child: SlidingSegment<bool>(
                        key: const ValueKey('budget-rule-dated'),
                        items: const [(false, '一直有效'), (true, '选日期')],
                        value: _dated,
                        onChanged: (v) {
                          Haptics.selection();
                          setState(() {
                            _dated = v;
                            _error = null;
                          });
                        },
                      ),
                    ),
                  if (!_dated) ...[
                    const SizedBox(height: 6),
                    Text(_baseCaption(repo), style: AppType.caption(scheme)),
                  ],
                  if (_dated) ...[
                    const SizedBox(height: 10),
                    _RangeCalendar(
                      accent: accent,
                      month: _pickerMonth,
                      start: _start,
                      end: _rangeEnd,
                      today: budgetDay(AppClock.now),
                      onPrev: () => setState(() => _pickerMonth =
                          DateTime(_pickerMonth.year, _pickerMonth.month - 1)),
                      onNext: () => setState(() => _pickerMonth =
                          DateTime(_pickerMonth.year, _pickerMonth.month + 1)),
                      onTapDay: _tapDay,
                    ),
                    // 选完起止后，日期写进下面的预览第一行；没选完才在这提示怎么点。
                    if (!_rangeComplete) ...[
                      const SizedBox(height: 6),
                      Text(
                        _rangeText(),
                        key: const ValueKey('budget-rule-range-text'),
                        style: AppType.caption(scheme),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('钱从哪来', style: AppType.secondary(scheme)),
                    const SizedBox(height: 7),
                    if (hasBase)
                      SizedBox(
                        width: double.infinity,
                        child: SlidingSegment<BudgetFunding>(
                          key: const ValueKey('budget-rule-funding'),
                          items: [
                            (BudgetFunding.carve, _fundingSourceLabel()),
                            (BudgetFunding.extra, '额外多给'),
                          ],
                          value: _funding,
                          onChanged: (v) {
                            Haptics.selection();
                            setState(() => _funding = v);
                          },
                        ),
                      )
                    else
                      Text(
                        '这几天还没有日常预算，只能额外多给',
                        key: const ValueKey('budget-rule-extra-only'),
                        style: AppType.body(scheme),
                      ),
                  ],
                  if (preview.isNotEmpty || baseWarning != null) ...[
                    const SizedBox(height: 18),
                    _PreviewCard(accent: accent, lines: [
                      if (_dated && _rangeComplete)
                        BudgetRulePreviewLine(_rangeText()),
                      ...preview,
                      if (baseWarning != null)
                        BudgetRulePreviewLine(baseWarning, warning: true),
                    ]),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('budget-rule-error'),
                      style: AppType.secondary(scheme)
                          .copyWith(color: AppColors.warning),
                    ),
                  ],
                  if (_isEdit) ...[
                    const SizedBox(height: 20),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          key: const ValueKey('budget-rule-delete'),
                          title: '删除这条预算',
                          titleColor: AppColors.warning,
                          onTap: () => _delete(repo),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 保存前的预览：规则颜色的淡底小框（示意图同款），不再带「预览」小标题和描边。
class _PreviewCard extends StatelessWidget {
  final List<BudgetRulePreviewLine> lines;
  final Color accent;

  const _PreviewCard({required this.lines, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('budget-rule-preview'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: line.warning ? AppColors.warning : scheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}

/// 弹层里的小日历：点一下开始、再点一下结束（§6.9「内嵌小日历点起止」）。
class _RangeCalendar extends StatelessWidget {
  final Color accent;
  final DateTime month;
  final DateTime? start;
  final DateTime? end;
  final DateTime today;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onTapDay;

  const _RangeCalendar({
    required this.accent,
    required this.month,
    required this.start,
    required this.end,
    required this.today,
    required this.onPrev,
    required this.onNext,
    required this.onTapDay,
  });

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = DateTime(month.year, month.month).weekday - 1;
    final count = budgetDaysInMonth(month.year, month.month);
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(lead, null),
      for (var d = 1; d <= count; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(
      key: const ValueKey('budget-rule-range-calendar'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${month.year}年${month.month}月',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            BudgetMonthArrow(
              key: const ValueKey('budget-range-prev'),
              icon: CupertinoIcons.chevron_back,
              semanticLabel: '上个月',
              onPressed: onPrev,
            ),
            BudgetMonthArrow(
              key: const ValueKey('budget-range-next'),
              icon: CupertinoIcons.chevron_forward,
              semanticLabel: '下个月',
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTextColor.hint(scheme),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < cells.length; i += 7)
          Row(
            children: [
              for (final day in cells.sublist(i, i + 7))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 36)
                      : _rangeCell(day, scheme),
                ),
            ],
          ),
      ],
    );
  }

  /// 选中的日子：规则颜色的淡色圆角方块 + 同色粗字（示意图同款）。
  Widget _rangeCell(DateTime day, ColorScheme scheme) {
    final s = start;
    final e = end;
    final selected = s != null &&
        (day == s || (e != null && !day.isBefore(s) && !day.isAfter(e)));
    final isToday = day == today;
    final weekend = day.weekday >= 6;
    return PressableScale(
      key: ValueKey('budget-range-day-${budgetDayKey(day)}'),
      onPressed: () => onTapDay(day),
      child: SizedBox(
        height: 36,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected
                  ? accent.withValues(alpha: 0.20)
                  : Colors.transparent,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                height: 1,
                fontWeight:
                    selected || isToday ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? Color.lerp(accent, Colors.black, 0.18)
                    : weekend
                        ? AppTextColor.hint(scheme)
                        : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
