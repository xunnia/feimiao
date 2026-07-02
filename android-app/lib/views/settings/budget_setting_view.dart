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
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';

/// 预算管理（预算期间模型）：
/// 预算是阶段性的——每条「期间」有生效起止（或每月循环），改预算=新建期间，
/// 历史月份仍显示当时生效的那条，不会被覆盖。
/// 设置流程一页搞定：收入 → 固定支出 → 一键建议 → 微调 → 选期间/账本 → 保存。
class BudgetSettingView extends StatefulWidget {
  const BudgetSettingView({super.key});

  @override
  State<BudgetSettingView> createState() => _BudgetSettingViewState();
}

class _BudgetSettingViewState extends State<BudgetSettingView> {
  final _incomeCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final List<({TextEditingController name, TextEditingController amount})>
      _fixed = [];
  final Map<String, TextEditingController> _catCtrls = {};
  bool _recurring = true;
  DateTimeRange? _customRange;
  int? _bookId; // null = 不区分账本
  bool _detailExpanded = false;
  String? _formError;

  @override
  void dispose() {
    _incomeCtrl.dispose();
    _totalCtrl.dispose();
    for (final f in _fixed) {
      f.name.dispose();
      f.amount.dispose();
    }
    for (final c in _catCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 工具 ─────────────────────────────────────────────────────────────────

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

  TextEditingController _catCtrl(String key) =>
      _catCtrls.putIfAbsent(key, TextEditingController.new);

  // ── 一键建议 ─────────────────────────────────────────────────────────────

  void _suggest(AppRepository repo) {
    final income = Decimal.tryParse(_incomeCtrl.text.trim());
    if (income == null || income <= Decimal.zero) {
      setState(() => _formError = '先填一下月收入，喵才能帮你算建议');
      return;
    }
    final fixed = _fixedTotal();
    final total = BudgetSuggestion.suggestTotal(
      income: income,
      fixedTotal: fixed,
    );
    if (total == null) {
      setState(() =>
          _formError = '收入减去固定支出和 20% 储蓄后没有剩余额度了，检查一下数字');
      return;
    }
    // 按你自己近 3 个月的消费结构分配到大类。
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
      // 先清空旧值再填建议，避免残留。
      for (final c in _catCtrls.values) {
        c.clear();
      }
      alloc.forEach((key, v) => _catCtrl(key).text = v.toString());
      _detailExpanded = true;
    });
  }

  // ── 保存 ─────────────────────────────────────────────────────────────────

  Future<void> _save(AppRepository repo) async {
    final total = Decimal.tryParse(_totalCtrl.text.trim());
    if (total == null || total <= Decimal.zero) {
      setState(() => _formError = '总预算要填一个大于 0 的数');
      return;
    }
    if (!_recurring && _customRange == null) {
      setState(() => _formError = '自定义期间要先选起止日期');
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
    await repo.addBudgetPeriod(
      bookId: _bookId,
      start: _recurring
          ? DateTime(now.year, now.month, 1) // 循环预算从本月起生效
          : _customRange!.start,
      end: _recurring ? null : _customRange!.end,
      recurringMonthly: _recurring,
      total: total,
      categoryBudgets: catBudgets,
      monthlyIncome: Decimal.tryParse(_incomeCtrl.text.trim()),
      fixedExpenses: fixed,
    );
    Haptics.of(Haptic.success);
    if (!mounted) return;
    setState(() => _formError = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_recurring ? '预算已生效（本月起）' : '期间预算已保存'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
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
    final repo = context.watch<AppRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('预算管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EffectiveCard(repo: repo),
          if (repo.budgetPeriods.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PeriodListCard(repo: repo),
          ],
          const SizedBox(height: 16),
          _buildNewPeriodCard(repo),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNewPeriodCard(AppRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    final cats = repo.categoriesForKindRanked(TransactionKind.expense);

    return _Card(
      title: '新建预算',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. 月收入 ──
          Text('月收入（可选，用于算建议）',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _incomeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: iosInputDecoration(hint: '如 8000', prefix: '¥ '),
          ),
          const SizedBox(height: 14),

          // ── 2. 固定支出 ──
          Row(
            children: [
              Text('每月固定支出（房租、话费等）',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const Spacer(),
              PressableScale(
                onPressed: () => setState(() => _fixed.add((
                      name: TextEditingController(),
                      amount: TextEditingController(),
                    ))),
                child: Icon(Icons.add_circle_outline,
                    size: 20, color: scheme.primary),
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
                    decoration: iosInputDecoration(hint: '如 房租'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _fixed[i].amount,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: iosInputDecoration(hint: '金额', prefix: '¥ '),
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
                        size: 19, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // ── 3. 一键建议 ──
          PressableScale(
            onPressed: () => _suggest(repo),
            child: Container(
              width: double.infinity,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '按我的消费习惯生成建议',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '建议 = 收入 − 固定支出 − 20% 储蓄，再按你近 3 个月的消费结构分到各分类',
            style: TextStyle(
                fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 14),

          // ── 4. 总预算 ──
          Text('总预算（不含固定支出的可花额度）',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _totalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: iosInputDecoration(hint: '如 4000', prefix: '¥ '),
          ),
          const SizedBox(height: 10),

          // ── 5. 分类明细（可折叠）──
          InkWell(
            onTap: () => setState(() => _detailExpanded = !_detailExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('分类预算明细',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  Icon(
                    _detailExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_detailExpanded)
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
                    child:
                        Text(c.nameZh, style: const TextStyle(fontSize: 14)),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _catCtrl(c.key),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.end,
                      decoration: iosInputDecoration(hint: '0', prefix: '¥ '),
                    ),
                  ),
                ],
              ),
            ],
          const SizedBox(height: 14),

          // ── 6. 期间 + 账本 ──
          Row(
            children: [
              SizedBox(
                width: 190,
                child: SlidingSegment<bool>(
                  items: const [(true, '每月循环'), (false, '自定义期间')],
                  value: _recurring,
                  onChanged: (v) {
                    Haptics.selection();
                    setState(() => _recurring = v);
                    if (!v && _customRange == null) _pickCustomRange();
                  },
                ),
              ),
              const Spacer(),
              // 账本选择
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_outlined,
                              size: 14, color: scheme.onSurfaceVariant),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card(scheme),
                  borderRadius: BorderRadius.circular(10),
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
              '自定义期间的总预算是整段期间的总额（如一次旅行）',
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
          const SizedBox(height: 14),

          // ── 7. 保存 ──
          PressableScale(
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
                '保存预算',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.surface,
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
// 当前生效预算卡
// ─────────────────────────────────────────────────────────────────────────────

class _EffectiveCard extends StatelessWidget {
  final AppRepository repo;

  const _EffectiveCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final total = repo.budgetTotalFor(now.year, now.month);

    if (total == null) {
      return _Card(
        title: '当前生效',
        child: Text(
          '还没有生效中的预算，用下面的表单建一条吧',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }

    final status =
        BudgetEngine.status(monthlyBudget: total, records: repo.allRecords);
    final ratio = (MoneyFormat.toDouble(status.spentThisMonth) /
            MoneyFormat.toDouble(total).clamp(0.01, double.infinity))
        .clamp(0.0, 1.0);
    final isOver = status.isOverBudget;

    return _Card(
      title: '当前生效',
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
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                ),
              ),
              const SizedBox(width: 6),
              Text('/ 月',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
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
          Text(
            '本月已花 ${MoneyFormat.string(status.spentThisMonth)} · '
            '${isOver ? '已超 ${MoneyFormat.string(status.spentThisMonth - total)}' : '还剩 ${MoneyFormat.string(status.remaining)}'}',
            style: TextStyle(
              fontSize: 12,
              color: isOver ? AppColors.warning : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 预算期间列表（可删）
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodListCard extends StatelessWidget {
  final AppRepository repo;

  const _PeriodListCard({required this.repo});

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
      title: '全部预算期间',
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
                          '${p.categoryBudgets.isEmpty ? '' : ' · ${p.categoryBudgets.length} 个分类明细'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PressableScale(
                    onPressed: () async {
                      final ok = await showConfirmDialog(
                        context,
                        title: '删除这条预算？',
                        message: '删除后它覆盖的月份将不再显示预算。',
                        confirmText: '删除',
                        destructive: true,
                      );
                      if (ok) await repo.deleteBudgetPeriod(p.id);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline,
                          size: 19, color: scheme.onSurfaceVariant),
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
