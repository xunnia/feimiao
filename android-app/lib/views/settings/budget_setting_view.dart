import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/budget/budget_period.dart';
import '../../core/budget/budget_suggestion.dart';
import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';

/// 预算管理：首页做「看预算」，弹层做「设预算」（2026-07-03 按用户/GPT 复盘重构）。
/// 回答三个问题：这个月还能花多少？哪些分类快超了？要不要调整预算？
///
/// 三层结构：
///   ① 本月预算卡：总额/已用/剩余 + 还剩 N 天·日均可花 + 分类进度（预警变色）
///   ② 预算计划：已有期间列表，「⋯」= 编辑 / 删除（不裸露垃圾桶）
///   ③ 新建/编辑预算：底部模糊弹层（智能建议收进去做辅助）
class BudgetSettingView extends StatelessWidget {
  const BudgetSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('预算管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(repo: repo),
          if (repo.budgetPeriods.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PlanListCard(repo: repo),
          ],
          const SizedBox(height: 20),
          // 底部主按钮：设预算走弹层
          PressableScale(
            onPressed: () => showBudgetSheet(context),
            child: Container(
              width: double.infinity,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '新建预算',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ① 本月预算卡（看预算）
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final AppRepository repo;

  const _StatusCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final total = repo.budgetTotalFor(now.year, now.month);

    if (total == null) {
      return _Card(
        title: '本月预算',
        child: Text(
          '还没设置预算。设一个之后，这里会告诉你每天还能花多少。',
          style: TextStyle(
              fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5),
        ),
      );
    }

    final status =
        BudgetEngine.status(monthlyBudget: total, records: repo.allRecords);
    final ratio = (MoneyFormat.toDouble(status.spentThisMonth) /
            MoneyFormat.toDouble(total).clamp(0.01, double.infinity))
        .clamp(0.0, 1.0);
    final isOver = status.isOverBudget;

    // 还剩 N 天 · 日均可花（剩余额度 ÷ 含今天的剩余天数）。
    final daysTotal = StatisticsEngine.daysInMonth(
        year: now.year, month: now.month);
    final daysLeft = daysTotal - now.day + 1;
    final perDay = isOver
        ? null
        : Decimal.parse(
            (status.remaining.toDouble() / daysLeft).toStringAsFixed(0));

    // 分类预算进度（当前生效计划的分类明细，取前 5 个）。
    final effective = BudgetResolver.effectiveOn(
        repo.budgetPeriods, now, bookId: repo.currentBookId);
    final catBudgets = effective?.categoryBudgets ?? const {};

    return _Card(
      title: '本月预算',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                MoneyFormat.string(total),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                ),
              ),
              const Spacer(),
              Text(
                '已用 ${MoneyFormat.string(status.spentThisMonth)} · '
                '${isOver ? '已超 ${MoneyFormat.string(status.spentThisMonth - total)}' : '剩余 ${MoneyFormat.string(status.remaining)}'}',
                style: TextStyle(
                  fontSize: 12,
                  color: isOver ? AppColors.warning : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: isOver ? AppColors.warning : scheme.primary,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 6),
          // 从「看数字」变成「指导消费」：日均可花。
          Text(
            isOver
                ? '本月已超支，接下来 $daysLeft 天缓一缓喵'
                : '本月还剩 $daysLeft 天 · 日均可花 ${MoneyFormat.string(perDay!)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isOver ? AppColors.warning : scheme.primary,
            ),
          ),
          // ── 分类预算进度（核心信息前置，最多 5 个）──
          if (catBudgets.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final e in _rankedEntries(catBudgets).take(5))
              _CategoryProgressRow(repo: repo, catKey: e.key, budget: e.value),
          ],
        ],
      ),
    );
  }

  /// 分类预算按金额降序展示。
  static List<MapEntry<String, Decimal>> _rankedEntries(
      Map<String, Decimal> m) {
    final list = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

/// 单个分类的预算进度行：图标 + 名称 + 已用/预算 + 进度条（预警变色）。
class _CategoryProgressRow extends StatelessWidget {
  final AppRepository repo;
  final String catKey;
  final Decimal budget;

  const _CategoryProgressRow({
    required this.repo,
    required this.catKey,
    required this.budget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat =
        repo.categories.where((c) => c.key == catKey).firstOrNull;
    if (cat == null) return const SizedBox.shrink();
    final spent = repo.monthSpentForTopCategory(cat.id);
    final r = budget > Decimal.zero
        ? (spent.toDouble() / budget.toDouble())
        : 0.0;
    // 预警色：超支橙、快超（≥80%）金、正常主色。
    final barColor = r > 1.0
        ? AppColors.warning
        : (r >= 0.8 ? AppColors.income(scheme) : scheme.primary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CatIcon(
                categoryKey: cat.key,
                emoji: CategorySeed.emojiOf(cat.key),
                size: 20,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(cat.nameZh, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '${MoneyFormat.string(spent)} / ${MoneyFormat.string(budget)}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Nunito',
                  color: r > 1.0 ? AppColors.warning : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: r.clamp(0.0, 1.0),
              minHeight: 4,
              color: barColor,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ② 预算计划列表（管理）
// ─────────────────────────────────────────────────────────────────────────────

class _PlanListCard extends StatelessWidget {
  final AppRepository repo;

  const _PlanListCard({required this.repo});

  String _desc(BudgetPeriod p) {
    String d(DateTime t) => '${t.year}/${t.month}/${t.day}';
    if (p.recurringMonthly) {
      final since = p.start.year <= 2000 ? '一直有效' : '${d(p.start)} 起';
      return '每月循环 · $since';
    }
    return '${d(p.start)} – ${p.end == null ? '不限' : d(p.end!)}';
  }

  String _bookName(BudgetPeriod p) {
    if (p.bookId == null) return '全部账本';
    return repo.books.where((b) => b.id == p.bookId).firstOrNull?.name ??
        '已删账本';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      title: '预算计划',
      child: Column(
        children: [
          for (final p in repo.budgetPeriods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${MoneyFormat.string(p.total)}'
                          '${p.recurringMonthly ? ' / 月' : ' 总额'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Nunito',
                          ),
                        ),
                        Text(
                          '${_desc(p)} · ${_bookName(p)}'
                          '${p.categoryBudgets.isEmpty ? '' : ' · ${p.categoryBudgets.length} 个分类'}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // 删除收进「⋯」二级菜单，不裸露垃圾桶。
                  Builder(
                    builder: (iconCtx) => PressableScale(
                      onPressed: () => showIosMenu(iconCtx, [
                        IosMenuItem(
                          label: '编辑',
                          icon: Icons.edit_outlined,
                          onTap: () => showBudgetSheet(context, edit: p),
                        ),
                        IosMenuItem(
                          label: '删除',
                          icon: Icons.delete_outline,
                          destructive: true,
                          onTap: () async {
                            final ok = await showConfirmDialog(
                              context,
                              title: '删除这条预算计划？',
                              message: '删除后它覆盖的月份将不再显示预算。',
                              confirmText: '删除',
                              destructive: true,
                            );
                            if (ok) await repo.deleteBudgetPeriod(p.id);
                          },
                        ),
                      ]),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.more_horiz,
                            size: 20, color: scheme.onSurfaceVariant),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// ③ 新建 / 编辑预算（底部模糊弹层，设预算）
// ─────────────────────────────────────────────────────────────────────────────

/// 打开预算设置弹层；[edit] 传入 = 编辑既有计划。
Future<void> showBudgetSheet(BuildContext context, {BudgetPeriod? edit}) {
  return showBlurSheet<void>(context, child: _BudgetSheet(edit: edit));
}

class _BudgetSheet extends StatefulWidget {
  final BudgetPeriod? edit;

  const _BudgetSheet({this.edit});

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final TextEditingController _totalCtrl = TextEditingController(
      text: widget.edit == null ? '' : widget.edit!.total.toString());
  late final TextEditingController _incomeCtrl = TextEditingController(
      text: widget.edit?.monthlyIncome?.toString() ?? '');
  final List<({TextEditingController name, TextEditingController amount})>
      _fixed = [];
  final Map<String, TextEditingController> _catCtrls = {};
  late bool _recurring = widget.edit?.recurringMonthly ?? true;
  late DateTimeRange? _customRange = widget.edit != null &&
          !widget.edit!.recurringMonthly &&
          widget.edit!.end != null
      ? DateTimeRange(start: widget.edit!.start, end: widget.edit!.end!)
      : null;
  late int? _bookId = widget.edit?.bookId;
  bool _suggestExpanded = false;
  String? _formError;

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      e.categoryBudgets.forEach((k, v) => _catCtrl(k).text = v.toString());
      for (final (name, amount) in e.fixedExpenses) {
        _fixed.add((
          name: TextEditingController(text: name),
          amount: TextEditingController(text: amount.toString()),
        ));
      }
    }
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _incomeCtrl.dispose();
    for (final f in _fixed) {
      f.name.dispose();
      f.amount.dispose();
    }
    for (final c in _catCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _catCtrl(String key) =>
      _catCtrls.putIfAbsent(key, TextEditingController.new);

  /// 分类名 → 顶级分类 key（子类归并到大类；映射不到返回 null）。
  static String? _topKeyOf(String name) {
    for (final s in CategorySeed.all) {
      if (s.nameZh == name) return s.parentKey ?? s.key;
    }
    return null;
  }

  Decimal _fixedTotal() {
    var sum = Decimal.zero;
    for (final f in _fixed) {
      final v = Decimal.tryParse(f.amount.text.trim());
      if (v != null && v > Decimal.zero) sum += v;
    }
    return sum;
  }

  // ── 智能建议（辅助功能，收在折叠区）──────────────────────────────────────
  void _suggest(AppRepository repo) {
    final income = Decimal.tryParse(_incomeCtrl.text.trim());
    if (income == null || income <= Decimal.zero) {
      setState(() => _formError = '先填一下月收入，喵才能帮你算建议');
      return;
    }
    final total = BudgetSuggestion.suggestTotal(
      income: income,
      fixedTotal: _fixedTotal(),
    );
    if (total == null) {
      setState(() =>
          _formError = '收入减去固定支出和 20% 储蓄后没有剩余额度了，检查一下数字');
      return;
    }
    final weights = BudgetSuggestion.historicalWeights(
      repo.allRecords,
      now: DateTime.now(),
      topKeyOfName: _topKeyOf,
    );
    final alloc = BudgetSuggestion.split(total: total, weights: weights);

    Haptics.of(Haptic.success);
    setState(() {
      _formError = null;
      _totalCtrl.text = total.toString();
      for (final c in _catCtrls.values) {
        c.clear();
      }
      alloc.forEach((key, v) => _catCtrl(key).text = v.toString());
    });
  }

  // ── 保存 ─────────────────────────────────────────────────────────────────
  Future<void> _save(AppRepository repo) async {
    final total = Decimal.tryParse(_totalCtrl.text.trim());
    if (total == null || total <= Decimal.zero) {
      setState(() => _formError = '预算金额要填一个大于 0 的数');
      return;
    }
    if (!_recurring && _customRange == null) {
      setState(() => _formError = '自定义周期要先选起止日期');
      return;
    }

    final catBudgets = <String, Decimal>{};
    _catCtrls.forEach((key, ctrl) {
      final v = Decimal.tryParse(ctrl.text.trim());
      if (v != null && v > Decimal.zero) catBudgets[key] = v;
    });
    final fixed = <(String, Decimal)>[];
    for (final f in _fixed) {
      final v = Decimal.tryParse(f.amount.text.trim());
      final name = f.name.text.trim();
      if (v != null && v > Decimal.zero) {
        fixed.add((name.isEmpty ? '固定支出' : name, v));
      }
    }

    final now = DateTime.now();
    final start = _recurring
        ? (_isEdit
            ? widget.edit!.start // 编辑循环计划保留原生效起点
            : DateTime(now.year, now.month, 1))
        : _customRange!.start;
    final end = _recurring ? null : _customRange!.end;
    final income = Decimal.tryParse(_incomeCtrl.text.trim());

    if (_isEdit) {
      await repo.updateBudgetPeriod(
        widget.edit!.id,
        bookId: _bookId,
        start: start,
        end: end,
        recurringMonthly: _recurring,
        total: total,
        categoryBudgets: catBudgets,
        monthlyIncome: income,
        fixedExpenses: fixed,
      );
    } else {
      await repo.addBudgetPeriod(
        bookId: _bookId,
        start: start,
        end: end,
        recurringMonthly: _recurring,
        total: total,
        categoryBudgets: catBudgets,
        monthlyIncome: income,
        fixedExpenses: fixed,
      );
    }
    Haptics.of(Haptic.success);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: _customRange,
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final cats = repo.categoriesForKindRanked(TransactionKind.expense);
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
                Text(
                  _isEdit ? '编辑预算' : '新建预算',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 范围 + 周期 ──
                  Row(
                    children: [
                      SizedBox(
                        width: 172,
                        child: SlidingSegment<bool>(
                          items: const [(true, '每月'), (false, '自定义')],
                          value: _recurring,
                          onChanged: (v) {
                            Haptics.selection();
                            setState(() => _recurring = v);
                            if (!v && _customRange == null) _pickCustomRange();
                          },
                        ),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (chipCtx) {
                          final bookLabel = _bookId == null
                              ? '全部账本'
                              : (repo.books
                                      .where((b) => b.id == _bookId)
                                      .firstOrNull
                                      ?.name ??
                                  '账本');
                          return PressableScale(
                            onPressed: () => showIosMenu(chipCtx, [
                              IosMenuItem(
                                label: '全部账本',
                                icon: _bookId == null
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                onTap: () => setState(() => _bookId = null),
                              ),
                              for (final b in repo.books)
                                IosMenuItem(
                                  label: '${b.icon} ${b.name}',
                                  icon: b.id == _bookId
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  onTap: () => setState(() => _bookId = b.id),
                                ),
                            ]),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.card(scheme),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color:
                                        Colors.black.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 13,
                                      color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 5),
                                  Text(bookLabel,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (!_recurring) ...[
                    const SizedBox(height: 10),
                    PressableScale(
                      onPressed: _pickCustomRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.card(scheme),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.black.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.date_range_outlined,
                                size: 15, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              _customRange == null
                                  ? '选择起止日期'
                                  : '${_customRange!.start.year}/${_customRange!.start.month}/${_customRange!.start.day}'
                                      ' – '
                                      '${_customRange!.end.year}/${_customRange!.end.month}/${_customRange!.end.day}',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '自定义周期的预算是整段期间的总额（如一次旅行）',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── 本月可支配预算 + 智能建议按钮 ──
                  Text('本月可支配预算',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _totalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              iosInputDecoration(hint: '如 4000', prefix: '¥ '),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 智能建议是辅助，不喧宾夺主：一颗小按钮，点开折叠区。
                      PressableScale(
                        onPressed: () => setState(
                            () => _suggestExpanded = !_suggestExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 11),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    scheme.primary.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 14, color: scheme.primary),
                              const SizedBox(width: 4),
                              Text('智能建议',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── 智能建议折叠区（收入 + 固定支出 + 生成）──
                  if (_suggestExpanded) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('月收入（用于生成建议）',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _incomeCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: iosInputDecoration(
                                hint: '如 8000', prefix: '¥ '),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text('每月固定支出（房租、话费等）',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                              const Spacer(),
                              PressableScale(
                                onPressed: () => setState(() => _fixed.add((
                                      name: TextEditingController(),
                                      amount: TextEditingController(),
                                    ))),
                                child: Icon(Icons.add_circle_outline,
                                    size: 19, color: scheme.primary),
                              ),
                            ],
                          ),
                          for (var i = 0; i < _fixed.length; i++) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: _fixed[i].name,
                                    decoration:
                                        iosInputDecoration(hint: '如 房租'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 4,
                                  child: TextField(
                                    controller: _fixed[i].amount,
                                    keyboardType: const TextInputType
                                        .numberWithOptions(decimal: true),
                                    decoration: iosInputDecoration(
                                        hint: '金额', prefix: '¥ '),
                                  ),
                                ),
                                PressableScale(
                                  onPressed: () => setState(() {
                                    final f = _fixed.removeAt(i);
                                    f.name.dispose();
                                    f.amount.dispose();
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(Icons.remove_circle_outline,
                                        size: 18,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          PressableScale(
                            onPressed: () => _suggest(repo),
                            child: Container(
                              width: double.infinity,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '生成建议并填入',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '建议 = 收入 − 固定支出 − 20% 储蓄，按你近 3 个月的消费结构分到各分类',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── 分类预算 ──
                  Text('分类预算（可选）',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  for (final c in cats) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CatIcon(
                          categoryKey: c.key,
                          emoji: CategorySeed.emojiOf(c.key),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.nameZh,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _catCtrl(c.key),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            textAlign: TextAlign.end,
                            decoration:
                                iosInputDecoration(hint: '0', prefix: '¥ '),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_formError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _formError!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── 保存 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: PressableScale(
              onPressed: () => _save(repo),
              child: Container(
                width: double.infinity,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.onSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isEdit ? '保存修改' : '保存预算',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 统一小卡
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
