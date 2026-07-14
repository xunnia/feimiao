import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_period.dart';
import '../../core/budget/budget_plan_v2.dart';
import '../../core/budget/budget_special_tracking.dart';
import '../../core/budget/budget_suggestion.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/budget/fixed_commitment.dart';
import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/book_switch_chip.dart';
import '../../widgets/budget_progress.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';
import 'budget_special_tracking_ui.dart';

/// 预算管理：页面做「看执行」，弹层做「设计划」。
/// 浏览窗口与计划周期分离；本周期、月、周、自定义只改变复盘范围。
///
/// 三层结构：
///   ① 账本和四窗口浏览 + 同一结果驱动的执行卡与分类进度
///   ② 计划管理：已有期间列表，「⋯」= 编辑 / 删除
///   ③ 新建/编辑预算：底部模糊弹层（智能建议仅作辅助）
class BudgetSettingView extends StatefulWidget {
  const BudgetSettingView({super.key});

  @override
  State<BudgetSettingView> createState() => _BudgetSettingViewState();
}

class _BudgetSettingViewState extends State<BudgetSettingView> {
  BudgetViewKind _browseKind = BudgetViewKind.cycle;
  DateTime _referenceDay = DateUtils.dateOnly(DateTime.now());
  DateTimeRange? _browseCustomRange;
  int? _browseBookId;
  bool _scopeInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scopeInitialized) return;
    _browseBookId = context.read<AppRepository>().currentBookId;
    _scopeInitialized = true;
  }

  DateTime _weekStart(DateTime day) {
    final normalized = DateUtils.dateOnly(day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  String _dateLabel(DateTime day, {bool includeYear = false}) {
    if (includeYear) return '${day.year}/${day.month}/${day.day}';
    return '${day.month}/${day.day}';
  }

  String _browseWindowLabel(BudgetWindowResult? result) {
    if (result != null) {
      final start = result.viewWindow.startInclusive;
      final end = result.displayEndInclusive;
      if (_browseKind == BudgetViewKind.calendarMonth) {
        return '${start.year} 年 ${start.month} 月';
      }
      final endNeedsYear = start.year != end.year;
      final range = '${_dateLabel(start, includeYear: true)} - '
          '${_dateLabel(end, includeYear: endNeedsYear)}';
      return _browseKind == BudgetViewKind.cycle ? '本周期 · $range' : range;
    }
    switch (_browseKind) {
      case BudgetViewKind.cycle:
        return '本周期';
      case BudgetViewKind.calendarMonth:
        return '${_referenceDay.year} 年 ${_referenceDay.month} 月';
      case BudgetViewKind.calendarWeek:
        final start = _weekStart(_referenceDay);
        final end = start.add(const Duration(days: 6));
        return '${_dateLabel(start, includeYear: true)} - ${_dateLabel(end)}';
      case BudgetViewKind.custom:
        final range = _browseCustomRange;
        if (range == null) return '选择自定义日期';
        return '${_dateLabel(range.start, includeYear: true)} - '
            '${_dateLabel(range.end, includeYear: true)}';
    }
  }

  BudgetWindowResult? _resolveBudgetWindow(
    AppRepository repo,
    DateTime now,
  ) {
    final bookId = _browseBookId;
    if (bookId == null || bookId <= 0) return null;
    final customRange = _browseCustomRange;
    if (_browseKind == BudgetViewKind.custom && customRange == null) {
      return null;
    }
    final reference = _browseKind == BudgetViewKind.custom
        ? DateUtils.dateOnly(customRange!.start)
        : _referenceDay;
    return repo.budgetWindow(BudgetWindowQuery(
      viewKind: _browseKind,
      bookId: bookId,
      referenceDate: reference,
      customEndExclusive: _browseKind == BudgetViewKind.custom
          ? DateUtils.dateOnly(customRange!.end).add(const Duration(days: 1))
          : null,
      asOf: now,
      knowledgeCutoff: now,
    ));
  }

  Future<void> _pickBrowseWindow() async {
    switch (_browseKind) {
      case BudgetViewKind.cycle:
        final picked = await showAppDatePicker(
          context,
          initial: _referenceDay,
          first: DateTime(2000),
          last: DateTime(DateTime.now().year + 2, 12, 31),
          title: '选择所在周期',
        );
        if (picked != null && mounted) {
          setState(() => _referenceDay = DateUtils.dateOnly(picked));
        }
        break;
      case BudgetViewKind.calendarMonth:
        final picked = await showAppMonthPicker(
          context,
          initial: _referenceDay,
          last: DateTime(DateTime.now().year + 2, 12),
        );
        if (picked != null && mounted) {
          setState(() => _referenceDay = DateTime(picked.year, picked.month));
        }
        break;
      case BudgetViewKind.calendarWeek:
        final picked = await showAppWeekPicker(
          context,
          initialWeekStart: _weekStart(_referenceDay),
          last: DateTime(DateTime.now().year + 2, 12, 31),
        );
        if (picked != null && mounted) {
          setState(() => _referenceDay = DateUtils.dateOnly(picked));
        }
        break;
      case BudgetViewKind.custom:
        final picked = await showAppDateRangePicker(
          context,
          initial: _browseCustomRange,
          first: DateTime(2000),
          last: DateTime(DateTime.now().year + 2, 12, 31),
        );
        if (picked != null && mounted) {
          setState(() {
            _browseCustomRange = picked;
            _referenceDay = DateUtils.dateOnly(picked.start);
          });
        }
        break;
    }
  }

  void _stepBrowseWindow(
    int direction,
    BudgetWindowResult? result,
  ) {
    setState(() {
      switch (_browseKind) {
        case BudgetViewKind.cycle:
          final target = direction < 0
              ? result?.previousCycleWindow
              : result?.nextCycleWindow;
          if (target != null) {
            _referenceDay = DateUtils.dateOnly(target.startInclusive);
          }
          break;
        case BudgetViewKind.calendarMonth:
          _referenceDay = DateTime(
            _referenceDay.year,
            _referenceDay.month + direction,
          );
          break;
        case BudgetViewKind.calendarWeek:
          _referenceDay = _referenceDay.add(Duration(days: 7 * direction));
          break;
        case BudgetViewKind.custom:
          final range = _browseCustomRange;
          if (range == null) break;
          final days = range.end.difference(range.start).inDays + 1;
          final delta = Duration(days: days * direction);
          _browseCustomRange = DateTimeRange(
            start: range.start.add(delta),
            end: range.end.add(delta),
          );
          _referenceDay = _browseCustomRange!.start;
          break;
      }
    });
  }

  void _setBrowseKind(BudgetViewKind value) {
    Haptics.selection();
    setState(() => _browseKind = value);
    if (value == BudgetViewKind.custom && _browseCustomRange == null) {
      _pickBrowseWindow();
    }
  }

  void _showBrowseBookMenu(BuildContext menuContext, AppRepository repo) {
    showIosMenu(menuContext, [
      for (final book in repo.books)
        IosMenuItem(
          label: '${book.icon} ${book.name}',
          icon: book.id == _browseBookId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => _browseBookId = book.id),
        ),
    ]);
  }

  (DateTime, DateTime)? _specialBrowseWindow(BudgetWindowResult? result) {
    if (result != null) {
      return (
        result.viewWindow.startInclusive,
        result.viewWindow.endExclusive,
      );
    }
    return switch (_browseKind) {
      BudgetViewKind.cycle => (
          DateUtils.dateOnly(_referenceDay),
          DateUtils.dateOnly(_referenceDay).add(const Duration(days: 1)),
        ),
      BudgetViewKind.calendarMonth => (
          DateTime(_referenceDay.year, _referenceDay.month),
          DateTime(_referenceDay.year, _referenceDay.month + 1),
        ),
      BudgetViewKind.calendarWeek => (
          _weekStart(_referenceDay),
          _weekStart(_referenceDay).add(const Duration(days: 7)),
        ),
      BudgetViewKind.custom => _browseCustomRange == null
          ? null
          : (
              DateUtils.dateOnly(_browseCustomRange!.start),
              DateUtils.dateOnly(_browseCustomRange!.end)
                  .add(const Duration(days: 1)),
            ),
    };
  }

  List<BudgetSpecialBookOption> _specialBookOptions(AppRepository repo) => [
        for (final book in repo.books)
          BudgetSpecialBookOption(
            id: book.id,
            name: book.name,
            icon: book.icon,
          ),
      ];

  List<BudgetSpecialCategoryOption> _specialCategoryOptions(
    AppRepository repo,
  ) =>
      [
        for (final category
            in repo.categoriesForKindRanked(TransactionKind.expense))
          if (category.parentId == null && !category.hidden)
            BudgetSpecialCategoryOption(
              key: category.key,
              name: category.nameZh,
              icon: CategorySeed.emojiOf(category.key),
            ),
      ];

  List<BudgetSpecialTagOption> _specialTagOptions(AppRepository repo) => [
        for (final tag in repo.tags)
          BudgetSpecialTagOption(
            id: tag.id,
            name: tag.name,
            colorValue: tag.colorValue,
          ),
      ];

  BudgetSpecialTrackingDraft? _specialDraft(
    AppRepository repo,
    BudgetPlanV2 plan,
  ) {
    final revision = repo.budgetPlanRevisionsV2For(plan.id).lastOrNull;
    if (revision == null || plan.endInclusive == null) return null;
    return BudgetSpecialTrackingDraft(
      planId: plan.id,
      name: plan.name,
      startInclusive: plan.anchorStart,
      endInclusive: plan.endInclusive!,
      totalCents: revision.amountCents,
      bookId: plan.bookId,
      categoryKeys: plan.expenseScope.categoryKeys,
      tagIds: plan.expenseScope.tagIds,
    );
  }

  Future<void> _showSpecialTrackingSheet(
    AppRepository repo, {
    BudgetPlanV2? plan,
  }) async {
    final draft = plan == null ? null : _specialDraft(repo, plan);
    if (plan != null && draft == null) {
      showAppToast(context, '这条专项追踪的数据不完整，暂不能编辑');
      return;
    }
    await showBudgetSpecialTrackingSheet(
      context,
      books: _specialBookOptions(repo),
      categories: _specialCategoryOptions(repo),
      tags: _specialTagOptions(repo),
      initialDraft: draft,
      onSave: (command) async {
        await repo.saveBudgetSpecialTrackingV2(
          planId: command.planId,
          bookId: command.bookId,
          name: command.name,
          startInclusive: command.startInclusive,
          endInclusive: command.endInclusive,
          totalCents: command.totalCents,
          expenseScope: command.expenseScope,
        );
        if (mounted) {
          showAppToast(
            context,
            command.isEdit ? '专项追踪已更新' : '专项追踪已创建',
          );
        }
      },
    );
  }

  Future<void> _archiveSpecialTracking(
    AppRepository repo,
    BudgetPlanV2 plan,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '归档专项追踪？',
      message: '执行记录会保留；归档后不再出现在当前专项卡中，也不会影响日常预算。',
      confirmText: '归档',
    );
    if (!confirmed) return;
    await repo.archiveBudgetPlanV2(plan.id);
    if (mounted) showAppToast(context, '专项追踪已归档');
  }

  String _specialScopeSummary(AppRepository repo, BudgetPlanV2 plan) {
    final categoryNames = <String>[
      for (final key in plan.expenseScope.categoryKeys)
        repo.categories.where((item) => item.key == key).firstOrNull?.nameZh ??
            key,
    ];
    final tagNames = <String>[
      for (final id in plan.expenseScope.tagIds) repo.tagName(id) ?? '已删标签',
    ];
    final parts = <String>[
      if (categoryNames.isNotEmpty) '分类：${categoryNames.join('、')}',
      if (tagNames.isNotEmpty) '标签：${tagNames.join('、')}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final selectedBook =
        repo.books.where((book) => book.id == _browseBookId).firstOrNull;
    final now = DateTime.now();
    final result = _resolveBudgetWindow(repo, now);
    final specialWindow = _specialBrowseWindow(result);
    final specialPlans = repo.budgetSpecialPlansV2
        .where((plan) => plan.bookId == _browseBookId)
        .toList();
    final specialResults = specialWindow == null || _browseBookId == null
        ? const <BudgetSpecialTrackingResult>[]
        : repo.budgetSpecialTrackings(
            bookId: _browseBookId!,
            windowStartInclusive: specialWindow.$1,
            windowEndExclusive: specialWindow.$2,
            asOf: now,
            knowledgeCutoff: now,
          );

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('预算管理'),
        actions: [
          Builder(
            builder: (menuContext) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AppCircleButton(
                icon: Icons.add,
                onPressed: () => showIosMenu(menuContext, [
                  IosMenuItem(
                    label: '日常预算',
                    icon: Icons.calendar_view_month_outlined,
                    onTap: () => showBudgetPlanV2Sheet(context),
                  ),
                  IosMenuItem(
                    label: '专项追踪',
                    icon: Icons.flag_outlined,
                    onTap: () => _showSpecialTrackingSheet(repo),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            key: const ValueKey('budget-book-row'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '查看账本',
                      style: AppType.secondary(Theme.of(context).colorScheme),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '预算额度与支出使用同一账本范围',
                      style: AppType.caption(Theme.of(context).colorScheme),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (menuContext) => AppBookSwitchChip(
                  iconText: selectedBook?.icon ?? '📒',
                  label: selectedBook?.name ?? '当前账本',
                  maxLabelWidth: 108,
                  onPressed: () => _showBrowseBookMenu(menuContext, repo),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            key: const ValueKey('budget-window-segment'),
            width: double.infinity,
            child: SlidingSegment<BudgetViewKind>(
              items: const [
                (BudgetViewKind.cycle, '本周期'),
                (BudgetViewKind.calendarMonth, '月'),
                (BudgetViewKind.calendarWeek, '周'),
                (BudgetViewKind.custom, '自定义'),
              ],
              value: _browseKind,
              onChanged: _setBrowseKind,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            key: const ValueKey('budget-window-navigator'),
            children: [
              AppCircleButton(
                icon: Icons.chevron_left,
                size: 34,
                iconSize: 20,
                onPressed: _browseKind == BudgetViewKind.cycle &&
                        result?.previousCycleWindow == null
                    ? null
                    : () => _stepBrowseWindow(-1, result),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressableScale(
                  onPressed: _pickBrowseWindow,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card(Theme.of(context).colorScheme),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.hairline(
                          Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 16,
                          color: AppTextColor.secondary(
                            Theme.of(context).colorScheme,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _browseWindowLabel(result),
                            key: const ValueKey('budget-window-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.secondary(
                              Theme.of(context).colorScheme,
                            ).copyWith(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppCircleButton(
                icon: Icons.chevron_right,
                size: 34,
                iconSize: 20,
                onPressed: _browseKind == BudgetViewKind.cycle &&
                        result?.nextCycleWindow == null
                    ? null
                    : () => _stepBrowseWindow(1, result),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatusCard(
            repo: repo,
            result: result,
            customRangeRequired:
                _browseKind == BudgetViewKind.custom && result == null,
            now: now,
          ),
          if (specialResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '专项追踪',
              style: AppType.sectionLabel(Theme.of(context).colorScheme),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < specialResults.length; index++) ...[
              _BudgetSpecialResultCard(
                result: specialResults[index],
                scopeSummary:
                    _specialScopeSummary(repo, specialResults[index].plan),
                onEdit: specialResults[index].plan.status ==
                        BudgetPlanStatusV2.active
                    ? () => _showSpecialTrackingSheet(
                          repo,
                          plan: specialResults[index].plan,
                        )
                    : null,
                onArchive: specialResults[index].plan.status ==
                        BudgetPlanStatusV2.active
                    ? () => _archiveSpecialTracking(
                          repo,
                          specialResults[index].plan,
                        )
                    : null,
              ),
              if (index != specialResults.length - 1) const SizedBox(height: 8),
            ],
          ],
          if (specialPlans.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BudgetSpecialPlanListCard(
              plans: specialPlans,
              onEdit: (plan) => _showSpecialTrackingSheet(repo, plan: plan),
              onArchive: (plan) => _archiveSpecialTracking(repo, plan),
            ),
          ],
          if (repo.budgetPlansV2.any((plan) => plan.isPrimary)) ...[
            const SizedBox(height: 16),
            _BudgetV2PlanListCard(repo: repo),
          ],
          if (repo.budgetPeriods.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PlanListCard(repo: repo),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ① 预算窗口执行卡（看执行）
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final AppRepository repo;
  final BudgetWindowResult? result;
  final bool customRangeRequired;
  final DateTime now;

  const _StatusCard({
    required this.repo,
    required this.result,
    required this.customRangeRequired,
    required this.now,
  });

  String _cardTitle(BudgetViewKind kind) => switch (kind) {
        BudgetViewKind.cycle => '本周期预算',
        BudgetViewKind.calendarMonth => '自然月预算',
        BudgetViewKind.calendarWeek => '本周参考额度',
        BudgetViewKind.custom => '自定义窗口预算',
      };

  String? _reasonText(MetricReasonCode code) => switch (code) {
        MetricReasonCode.legacyScopeAmbiguous => '旧预算未保存明确账本范围',
        MetricReasonCode.legacyOverrideWithoutPrimary =>
          '这段时间只有旧的一次性期间，没有日常主计划',
        MetricReasonCode.legacyOpenEndedOverride => '旧的一次性期间缺少结束日期',
        MetricReasonCode.unknownBookScope => '部分支出的账本范围无法确认',
        MetricReasonCode.unknownCurrency => '部分支出的币种无法确认',
        MetricReasonCode.unallocatedRefund => '部分退款尚未分配到分类',
        MetricReasonCode.unsupportedCurrencyAggregation => '不同币种暂不合并计算',
        MetricReasonCode.invalidInput => '部分记录的数据格式异常',
        MetricReasonCode.categoryBudgetExceedsPlan => '分类额度合计超过了总预算',
        MetricReasonCode.fixedCommitmentsUnavailable => '固定支出有待匹配、逾期或退款复核',
        MetricReasonCode.noBudgetPlan => null,
        _ => null,
      };

  String? _qualityText(
    BudgetWindowResult value, {
    required bool includeDaily,
  }) {
    final notes = <String>{};
    for (final reason in [
      ...value.planReasons,
      ...value.spendReasons,
      if (includeDaily) ...value.dailyReasons,
      ...value.fixedCommitmentReasons,
    ]) {
      final text = _reasonText(reason.code);
      if (text != null) notes.add(text);
    }
    if (value.excludedForeignTransactionCount > 0) {
      notes.add('已排除 ${value.excludedForeignTransactionCount} 笔非 CNY 支出');
    }
    if (notes.isEmpty &&
        (value.planStatus == MetricStatus.partial ||
            value.spendStatus == MetricStatus.partial ||
            value.fixedCommitmentStatus == MetricStatus.partial ||
            (includeDaily && value.dailyStatus == MetricStatus.partial))) {
      notes.add('部分数据无法确认，金额按当前可确认范围计算');
    }
    return notes.isEmpty ? null : notes.join(' · ');
  }

  Widget _emptyState(
    BuildContext context, {
    required String title,
    required String message,
    Decimal? planned,
    Decimal? spent,
    String? qualityText,
    bool warning = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: AppType.secondary(scheme).copyWith(
              color: warning ? AppColors.warning : null,
            ),
          ),
          if (planned != null || spent != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 5,
              children: [
                if (planned != null)
                  _BudgetAmountLabel(label: '窗口预算', amount: planned),
                if (spent != null)
                  _BudgetAmountLabel(label: '已发生支出', amount: spent),
              ],
            ),
          ],
          if (qualityText != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.income(scheme).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(qualityText, style: AppType.caption(scheme)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = result;
    if (value == null) {
      return _emptyState(
        context,
        title: '预算执行',
        message: customRangeRequired ? '先选择要复盘的起止日期' : '请选择一个有效账本',
      );
    }
    final daily = value.currentCycleDailyStatus;
    final today = DateUtils.dateOnly(now);
    final showDaily = daily != null &&
        value.viewWindow.contains(today) &&
        (value.dailyStatus == MetricStatus.available ||
            value.dailyStatus == MetricStatus.partial);
    final qualityText = _qualityText(value, includeDaily: showDaily);
    final spendUsable = value.spendStatus == MetricStatus.available ||
        value.spendStatus == MetricStatus.partial;
    if (value.planStatus == MetricStatus.conflict) {
      return _emptyState(
        context,
        title: '预算计划有冲突',
        message: '分类额度超过总额或旧计划互相冲突，修正前不展示伪精确剩余。',
        spent: spendUsable ? value.spentAmount : null,
        qualityText: qualityText,
        warning: true,
      );
    }
    final planned = value.plannedAmount;
    final planUsable = value.planStatus == MetricStatus.available ||
        value.planStatus == MetricStatus.partial;
    if (!planUsable || planned == null) {
      return _emptyState(
        context,
        title: _cardTitle(value.query.viewKind),
        message: '这段时间还没有日常预算，可用右上角 + 新建计划。',
        spent: spendUsable ? value.spentAmount : null,
        qualityText: qualityText,
      );
    }

    if (!spendUsable) {
      final conflict = value.spendStatus == MetricStatus.conflict;
      return _emptyState(
        context,
        title: conflict ? '支出数据有冲突' : _cardTitle(value.query.viewKind),
        message: conflict
            ? '修正前不展示剩余、进度和分类执行。'
            : '预算计划已找到，但窗口支出暂不可计算，因此不展示剩余、进度和分类执行。',
        planned: planned,
        qualityText: qualityText,
        warning: conflict,
      );
    }

    final spent = value.spentAmount;
    final remaining = value.remainingAmount;
    final isOver = remaining != null && remaining < Decimal.zero;
    final progress = value.progress;
    final categoryResults = value.categoryResults
        .where((item) => item.plannedCents > 0 || item.spentCents > 0)
        .toList(growable: false);
    final allocatedCents = value.categoryResults.fold<int>(
      0,
      (sum, item) => sum + item.plannedCents,
    );
    final unallocatedCents = value.plannedCents == null
        ? 0
        : (value.plannedCents! - allocatedCents)
            .clamp(0, value.plannedCents!)
            .toInt();

    return _Card(
      title: _cardTitle(value.query.viewKind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            remaining == null
                ? '剩余暂不可计算'
                : '${isOver ? '已超' : '剩余'} ${MoneyFormat.string(remaining.abs())}',
            style: AppType.rowTitle(scheme).copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              fontFamily: 'Nunito',
              color: isOver ? AppColors.warning : AppTextColor.primary(scheme),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 5,
            children: [
              _BudgetAmountLabel(label: '预算', amount: planned),
              if (spent != null) _BudgetAmountLabel(label: '已用', amount: spent),
            ],
          ),
          if (value.discretionaryRemainingAmount != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('可自由安排', style: AppType.caption(scheme)),
                        const SizedBox(height: 2),
                        Text(
                          MoneyFormat.string(
                            value.discretionaryRemainingAmount!,
                          ),
                          style: AppType.rowTitle(scheme).copyWith(
                            fontFamily: 'Nunito',
                            color: value.discretionaryRemainingCents! < 0
                                ? AppColors.warning
                                : scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '固定预留 ${MoneyFormat.string(value.fixedReserveAmount ?? Decimal.zero)}',
                    style: AppType.caption(scheme),
                  ),
                ],
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            BudgetProgressBar(
              value: progress,
              activeColor: isOver ? AppColors.warning : null,
            ),
            const SizedBox(height: 5),
            Text(
              '预算进度 ${(progress * 100).round()}% · '
              '时间进度 ${(value.timeProgress * 100).round()}%',
              style: AppType.caption(scheme),
            ),
          ],
          if (showDaily) ...[
            const SizedBox(height: 10),
            Text(
              '还剩 ${daily.remainingDaysIncludingToday} 天 · '
              '剩余预算日均参考 '
              '${MoneyFormat.string(daily.plainBudgetDailyReferenceAmount)}',
              style: AppType.secondary(scheme).copyWith(
                fontWeight: FontWeight.w500,
                color: isOver ? AppColors.warning : scheme.primary,
              ),
            ),
          ],
          if (qualityText != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.income(scheme).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(qualityText, style: AppType.caption(scheme)),
            ),
          ],
          if (categoryResults.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('分类执行', style: AppType.rowTitle(scheme)),
            const SizedBox(height: 8),
            for (final item in categoryResults.take(5))
              _CategoryProgressRow(repo: repo, result: item),
            if (categoryResults.length > 5)
              Text(
                '另有 ${categoryResults.length - 5} 个分类',
                style: AppType.caption(scheme),
              ),
          ],
          if (unallocatedCents > 0) ...[
            const SizedBox(height: 4),
            Text(
              '未分配额度 '
              '${MoneyFormat.string(budgetDecimalFromCents(unallocatedCents)!)}',
              style: AppType.caption(scheme),
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetAmountLabel extends StatelessWidget {
  final String label;
  final Decimal amount;

  const _BudgetAmountLabel({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: AppType.secondary(scheme),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: MoneyFormat.string(amount),
            style: AppType.secondary(scheme).copyWith(
              color: AppTextColor.primary(scheme),
              fontWeight: FontWeight.w500,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个分类的预算进度行：图标 + 名称 + 已用/预算 + 进度条（预警变色）。
class _CategoryProgressRow extends StatelessWidget {
  final AppRepository repo;
  final BudgetCategoryResult result;

  const _CategoryProgressRow({
    required this.repo,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = repo.categories
        .where((category) => category.key == result.categoryKey)
        .firstOrNull;
    final name = cat?.nameZh ??
        (result.categoryKey.isEmpty || result.categoryKey == '__other__'
            ? '其他'
            : result.categoryKey);
    final r = result.progress ?? 0.0;
    // 预警色：超支橙、快超（≥80%）金、正常预算绿。
    final barColor = r > 1.0
        ? AppColors.warning
        : (r >= 0.8
            ? AppColors.income(scheme)
            : AppColors.budgetHealthy(scheme));

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CatIcon(
                categoryKey: result.categoryKey,
                emoji: CategorySeed.emojiOf(result.categoryKey),
                size: 20,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(name, style: AppType.secondary(scheme)),
              ),
              Text(
                result.plannedCents > 0
                    ? '${MoneyFormat.string(result.spentAmount)} / '
                        '${MoneyFormat.string(result.plannedAmount)}'
                    : '已用 ${MoneyFormat.string(result.spentAmount)} · 未设额度',
                style: AppType.caption(scheme).copyWith(
                  color: r > 1.0
                      ? AppColors.warning
                      : AppTextColor.secondary(scheme),
                  fontFamily: 'Nunito',
                ),
              ),
            ],
          ),
          if (result.plannedCents > 0) ...[
            const SizedBox(height: 4),
            BudgetProgressBar(
              value: r,
              height: 4,
              activeColor: barColor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ② 预算计划列表（管理）
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetSpecialResultCard extends StatelessWidget {
  final BudgetSpecialTrackingResult result;
  final String scopeSummary;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  const _BudgetSpecialResultCard({
    required this.result,
    required this.scopeSummary,
    this.onEdit,
    this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    if (result.status == BudgetSpecialResultStatus.conflict ||
        result.totalCents == null ||
        result.spentCents == null) {
      return _Card(
        title: result.plan.name,
        child: Text(
          '专项追踪数据需要复核，暂不展示伪精确金额。${result.reason == null ? '' : ' ${result.reason}'}',
          style: AppType.secondary(Theme.of(context).colorScheme).copyWith(
            color: AppColors.warning,
          ),
        ),
      );
    }
    return BudgetSpecialTrackingCard(
      name: result.plan.name,
      startInclusive: result.startInclusive,
      endInclusive: result.endInclusive,
      totalCents: result.totalCents!,
      spentCents: result.spentCents!,
      scopeSummary: scopeSummary,
      lifecycleStatus: result.lifecycleStatus,
      onEdit: onEdit,
      onArchive: onArchive,
    );
  }
}

class _BudgetSpecialPlanListCard extends StatelessWidget {
  final List<BudgetPlanV2> plans;
  final ValueChanged<BudgetPlanV2> onEdit;
  final ValueChanged<BudgetPlanV2> onArchive;

  const _BudgetSpecialPlanListCard({
    required this.plans,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      title: '专项管理',
      child: Column(
        children: [
          for (final plan in plans)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: AppType.rowTitle(scheme)),
                        const SizedBox(height: 2),
                        Text(
                          '${plan.anchorStart.year}/${plan.anchorStart.month}/${plan.anchorStart.day} - '
                          '${plan.endInclusive?.year}/${plan.endInclusive?.month}/${plan.endInclusive?.day}'
                          '${plan.status == BudgetPlanStatusV2.archived ? ' · 已归档' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption(scheme),
                        ),
                      ],
                    ),
                  ),
                  if (plan.status == BudgetPlanStatusV2.active)
                    Builder(
                      builder: (menuContext) => PressableScale(
                        onPressed: () => showIosMenu(menuContext, [
                          IosMenuItem(
                            label: '编辑专项',
                            icon: Icons.edit_outlined,
                            onTap: () => onEdit(plan),
                          ),
                          IosMenuItem(
                            label: '归档',
                            icon: Icons.archive_outlined,
                            onTap: () => onArchive(plan),
                          ),
                        ]),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: AppTextColor.secondary(scheme),
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
}

class _BudgetV2PlanListCard extends StatelessWidget {
  final AppRepository repo;

  const _BudgetV2PlanListCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      title: '预算计划',
      child: Column(
        children: [
          for (final plan
              in repo.budgetPlansV2.where((plan) => plan.isPrimary)) ...[
            Builder(builder: (rowContext) {
              final revisions = repo.budgetPlanRevisionsV2For(plan.id);
              final latest = revisions.lastOrNull;
              final book = repo.books
                  .where((candidate) => candidate.id == plan.bookId)
                  .firstOrNull;
              final currentCycle = plan.cycleFor(DateTime.now());
              final occurrences = repo.budgetFixedOccurrencesV2For(
                plan.id,
                cycleStart: currentCycle.start,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latest == null
                                ? plan.name
                                : '${MoneyFormat.string(budgetDecimalFromCents(latest.amountCents)!)}'
                                    '${plan.cadence == BudgetPlanCadenceV2.monthly ? ' / 月' : ' / 周'}',
                            style: AppType.rowTitle(scheme).copyWith(
                              fontFamily: 'Nunito',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${book?.name ?? '已删账本'} · '
                            '${plan.cadence == BudgetPlanCadenceV2.monthly ? '每月 ${plan.monthStartDay} 日起' : '每周${_weekdayLabel(plan.weekStart!)}起'}'
                            '${occurrences.isEmpty ? '' : ' · ${occurrences.length} 项固定支出'}'
                            '${plan.status == BudgetPlanStatusV2.archived ? ' · 已归档' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption(scheme),
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (menuContext) => PressableScale(
                        onPressed: () => showIosMenu(menuContext, [
                          if (plan.status == BudgetPlanStatusV2.active) ...[
                            IosMenuItem(
                              label: '下周期修改',
                              icon: Icons.edit_calendar_outlined,
                              onTap: () => showBudgetPlanV2Sheet(
                                context,
                                plan: plan,
                              ),
                            ),
                            IosMenuItem(
                              label: '调整本周期',
                              icon: Icons.tune_outlined,
                              onTap: () => showBudgetPlanV2Sheet(
                                context,
                                plan: plan,
                                overrideCurrent: true,
                              ),
                            ),
                            IosMenuItem(
                              label: '固定支出',
                              icon: Icons.event_repeat_outlined,
                              onTap: () => showBudgetFixedOccurrencesSheet(
                                context,
                                plan,
                              ),
                            ),
                            IosMenuItem(
                              label: '归档',
                              icon: Icons.archive_outlined,
                              onTap: () async {
                                final confirmed = await showConfirmDialog(
                                  context,
                                  title: '归档预算计划？',
                                  message: '当前周期和历史记录会保留，归档后不再生成未来周期。',
                                  confirmText: '归档',
                                );
                                if (confirmed) {
                                  await repo.archiveBudgetPlanV2(plan.id);
                                }
                              },
                            ),
                          ] else
                            IosMenuItem(
                              label: '查看固定支出',
                              icon: Icons.history_outlined,
                              onTap: () => showBudgetFixedOccurrencesSheet(
                                context,
                                plan,
                              ),
                            ),
                        ]),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: AppTextColor.secondary(scheme),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

String _weekdayLabel(int weekday) => switch (weekday) {
      DateTime.monday => '一',
      DateTime.tuesday => '二',
      DateTime.wednesday => '三',
      DateTime.thursday => '四',
      DateTime.friday => '五',
      DateTime.saturday => '六',
      _ => '日',
    };

class _PlanListCard extends StatelessWidget {
  final AppRepository repo;

  const _PlanListCard({required this.repo});

  String _desc(BudgetPeriod p) {
    String d(DateTime t) => '${t.year}/${t.month}/${t.day}';
    if (p.recurringMonthly) {
      if (p.end != null) return '${d(p.start)} – ${d(p.end!)} · 每月额度';
      final since = p.start.year <= 2000 ? '一直有效' : '${d(p.start)} 起';
      return '每月循环 · $since';
    }
    return '${d(p.start)} – ${p.end == null ? '不限' : d(p.end!)} · 整段总额';
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
      title: '旧预算（只读）',
      child: Column(
        children: [
          for (final p in repo.budgetPeriods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
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
                            fontSize: 13.5,
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
                  Text(
                    '兼容保留',
                    style: AppType.caption(scheme),
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

Future<void> showBudgetPlanV2Sheet(
  BuildContext context, {
  BudgetPlanV2? plan,
  bool overrideCurrent = false,
}) =>
    showBlurSheet<void>(
      context,
      child: _BudgetPlanV2Sheet(
        plan: plan,
        overrideCurrent: overrideCurrent,
      ),
    );

class _FixedTemplateDraft {
  final String id;
  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController due;

  _FixedTemplateDraft({
    required this.id,
    String name = '',
    String amount = '',
    String due = '1',
  })  : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount),
        due = TextEditingController(text: due);

  void dispose() {
    name.dispose();
    amount.dispose();
    due.dispose();
  }
}

class _BudgetPlanV2Sheet extends StatefulWidget {
  final BudgetPlanV2? plan;
  final bool overrideCurrent;

  const _BudgetPlanV2Sheet({this.plan, this.overrideCurrent = false});

  @override
  State<_BudgetPlanV2Sheet> createState() => _BudgetPlanV2SheetState();
}

class _BudgetPlanV2SheetState extends State<_BudgetPlanV2Sheet> {
  final _nameController = TextEditingController();
  final _totalController = TextEditingController();
  final _incomeController = TextEditingController();
  final _monthStartController = TextEditingController(text: '1');
  final Map<String, TextEditingController> _categoryControllers = {};
  final List<_FixedTemplateDraft> _fixedDrafts = [];
  BudgetPlanCadenceV2 _cadence = BudgetPlanCadenceV2.monthly;
  int _weekStart = DateTime.monday;
  int? _bookId;
  bool _startNextCycle = true;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.plan != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final repo = context.read<AppRepository>();
    final plan = widget.plan;
    _bookId = plan?.bookId ?? repo.currentBookId;
    if (plan == null) return;
    _nameController.text = plan.name;
    _cadence = plan.cadence;
    _monthStartController.text = (plan.monthStartDay ?? 1).toString();
    _weekStart = plan.weekStart ?? DateTime.monday;
    final revisions = repo.budgetPlanRevisionsV2For(plan.id);
    final cycle = plan.cycleFor(DateTime.now());
    final revision = widget.overrideCurrent
        ? revisions.where((item) => item.appliesTo(cycle)).lastOrNull
        : revisions.lastOrNull;
    if (revision == null) return;
    _totalController.text =
        budgetDecimalFromCents(revision.amountCents)!.toString();
    _incomeController.text = revision.monthlyIncomeCents == null
        ? ''
        : budgetDecimalFromCents(revision.monthlyIncomeCents!)!.toString();
    for (final entry in revision.categoryBudgetsCents.entries) {
      _categoryController(entry.key).text =
          budgetDecimalFromCents(entry.value)!.toString();
    }
    if (!widget.overrideCurrent) {
      for (final template in revision.fixedTemplates) {
        _fixedDrafts.add(_FixedTemplateDraft(
          id: template.id,
          name: template.name,
          amount: budgetDecimalFromCents(template.plannedCents)!.toString(),
          due: template.dueValue.toString(),
        ));
      }
    }
  }

  TextEditingController _categoryController(String key) =>
      _categoryControllers.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    _incomeController.dispose();
    _monthStartController.dispose();
    for (final controller in _categoryControllers.values) {
      controller.dispose();
    }
    for (final draft in _fixedDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _showBookMenu(BuildContext menuContext) async {
    final repo = context.read<AppRepository>();
    await showIosMenu(menuContext, [
      for (final book in repo.books)
        IosMenuItem(
          label: '${book.icon} ${book.name}',
          icon: book.id == _bookId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => _bookId = book.id),
        ),
    ]);
  }

  int? _cents(TextEditingController controller) {
    final amount = Decimal.tryParse(controller.text.trim());
    return amount == null ? null : decimalToBudgetCents(amount);
  }

  Future<void> _save() async {
    if (_saving) return;
    final total = _cents(_totalController);
    final bookId = _bookId;
    if (bookId == null || total == null || total <= 0) {
      setState(() => _error = '请选择账本，并填写大于 0 的预算金额');
      return;
    }
    final categories = <String, int>{};
    for (final entry in _categoryControllers.entries) {
      final value = _cents(entry.value);
      if (value != null && value > 0) categories[entry.key] = value;
    }
    if (categories.values.fold<int>(0, (a, b) => a + b) > total) {
      setState(() => _error = '分类额度合计不能超过预算总额');
      return;
    }
    final templates = <BudgetFixedTemplateV2>[];
    if (!widget.overrideCurrent) {
      for (final draft in _fixedDrafts) {
        final amount = _cents(draft.amount);
        final due = int.tryParse(draft.due.text.trim());
        final maxDue = _cadence == BudgetPlanCadenceV2.monthly ? 28 : 7;
        if (draft.name.text.trim().isEmpty ||
            amount == null ||
            amount <= 0 ||
            due == null ||
            due < 1 ||
            due > maxDue) {
          setState(() => _error = _cadence == BudgetPlanCadenceV2.monthly
              ? '固定支出要填写名称、金额和 1-28 的到期日'
              : '固定支出要填写名称、金额和 1-7 的到期星期');
          return;
        }
        templates.add(BudgetFixedTemplateV2(
          id: draft.id,
          name: draft.name.text.trim(),
          plannedCents: amount,
          dueValue: due,
        ));
      }
    }
    if (templates.fold<int>(0, (sum, item) => sum + item.plannedCents) >
        total) {
      setState(() => _error = '固定支出合计不能超过预算总额');
      return;
    }
    final monthStart = int.tryParse(_monthStartController.text.trim()) ?? 0;
    if (_cadence == BudgetPlanCadenceV2.monthly &&
        (monthStart < 1 || monthStart > 28)) {
      setState(() => _error = '月预算起始日请填写 1-28');
      return;
    }
    final income = _incomeController.text.trim().isEmpty
        ? null
        : _cents(_incomeController);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<AppRepository>();
      if (widget.plan == null) {
        await repo.addBudgetPlanV2(
          bookId: bookId,
          name: _nameController.text.trim().isEmpty
              ? (_cadence == BudgetPlanCadenceV2.monthly ? '每月预算' : '每周预算')
              : _nameController.text.trim(),
          cadence: _cadence,
          totalCents: total,
          categoryBudgetsCents: categories,
          monthlyIncomeCents: income,
          fixedTemplates: templates,
          monthStartDay: monthStart == 0 ? 1 : monthStart,
          weekStart: _weekStart,
          startNextCycle: _startNextCycle,
        );
      } else if (widget.overrideCurrent) {
        final cycle = widget.plan!.cycleFor(DateTime.now());
        await repo.upsertBudgetCycleOverrideV2(
          planId: widget.plan!.id,
          cycleStart: cycle.start,
          targetAmountCents: total,
          categoryBudgetsCents: null,
          inputIntent: BudgetOverrideIntent.replaceTotal,
        );
      } else {
        await repo.addBudgetPlanRevisionV2(
          planId: widget.plan!.id,
          totalCents: total,
          categoryBudgetsCents: categories,
          monthlyIncomeCents: income,
          fixedTemplates: templates,
        );
      }
      if (!mounted) return;
      showAppToast(
        context,
        widget.overrideCurrent
            ? '本周期预算已调整'
            : _editing
                ? '修改将从下周期生效'
                : '预算计划已创建',
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final selectedBook =
        repo.books.where((book) => book.id == _bookId).firstOrNull;
    final topCategories = repo
        .categoriesForKindRanked(TransactionKind.expense)
        .where((category) => category.parentId == null)
        .toList();
    final currentResult = widget.plan == null
        ? null
        : repo.budgetWindow(BudgetWindowQuery(
            viewKind: BudgetViewKind.cycle,
            bookId: widget.plan!.bookId,
            referenceDate: DateTime.now(),
            asOf: DateTime.now(),
            knowledgeCutoff: DateTime.now(),
          ));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: widget.overrideCurrent
                ? '调整本周期'
                : _editing
                    ? '修改下周期预算'
                    : '新建预算',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: _saving ? null : _save,
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                _BudgetInputBlock(
                  label: '计划名称',
                  child: TextField(
                    controller: _nameController,
                    readOnly: _editing,
                    decoration: iosInputDecoration(context, hint: '例如：日常预算'),
                  ),
                ),
                const SizedBox(height: 12),
                Text('账本', style: AppType.caption(scheme)),
                const SizedBox(height: 6),
                Builder(
                  builder: (menuContext) => Align(
                    alignment: Alignment.centerLeft,
                    child: AppBookSwitchChip(
                      iconText: selectedBook?.icon ?? '📒',
                      label: selectedBook?.name ?? '选择账本',
                      onPressed:
                          _editing ? () {} : () => _showBookMenu(menuContext),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (!_editing) ...[
                  SlidingSegment<BudgetPlanCadenceV2>(
                    items: const [
                      (BudgetPlanCadenceV2.monthly, '每月'),
                      (BudgetPlanCadenceV2.weekly, '每周'),
                    ],
                    value: _cadence,
                    onChanged: (value) => setState(() => _cadence = value),
                  ),
                  const SizedBox(height: 10),
                  SlidingSegment<bool>(
                    items: const [(true, '下周期生效'), (false, '本周期生效')],
                    value: _startNextCycle,
                    onChanged: (value) =>
                        setState(() => _startNextCycle = value),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_editing && _cadence == BudgetPlanCadenceV2.monthly)
                  _BudgetInputBlock(
                    label: '每月起始日（1-28）',
                    child: TextField(
                      controller: _monthStartController,
                      keyboardType: TextInputType.number,
                      decoration: iosInputDecoration(context, hint: '1'),
                    ),
                  )
                else if (!_editing)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('每周起始日', style: AppType.caption(scheme)),
                      const SizedBox(height: 6),
                      SlidingSegment<int>(
                        items: const [
                          (DateTime.monday, '周一'),
                          (DateTime.sunday, '周日'),
                        ],
                        value: _weekStart,
                        onChanged: (value) =>
                            setState(() => _weekStart = value),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                _BudgetInputBlock(
                  label: widget.overrideCurrent ? '本周期预算总额' : '预算总额',
                  child: TextField(
                    controller: _totalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: iosInputDecoration(context, hint: '0.00'),
                  ),
                ),
                if (widget.overrideCurrent && currentResult != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前已用 ${MoneyFormat.string(currentResult.spentAmount ?? Decimal.zero)} · '
                    '保存后剩余 ${MoneyFormat.string((budgetDecimalFromCents(_cents(_totalController) ?? 0) ?? Decimal.zero) - (currentResult.spentAmount ?? Decimal.zero))}',
                    style: AppType.caption(scheme),
                  ),
                ],
                if (!widget.overrideCurrent) ...[
                  const SizedBox(height: 12),
                  _BudgetInputBlock(
                    label: '参考收入（可选）',
                    child: TextField(
                      controller: _incomeController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: iosInputDecoration(context, hint: '用于回显和建议'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('分类预算（可选）', style: AppType.rowTitle(scheme)),
                    children: [
                      for (final category in topCategories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(category.nameZh)),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _categoryController(category.key),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration:
                                      iosInputDecoration(context, hint: '0.00'),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: Text('固定支出', style: AppType.rowTitle(scheme))),
                      AppPillButton(
                        label: '添加',
                        onPressed: () => setState(() => _fixedDrafts.add(
                              _FixedTemplateDraft(
                                id: 'fixed-${DateTime.now().microsecondsSinceEpoch}',
                              ),
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cadence == BudgetPlanCadenceV2.monthly
                        ? '固定支出包含在总预算内，到期日限制为 1-28。'
                        : '固定支出包含在总预算内，到期星期用 1-7 表示周一到周日。',
                    style: AppType.caption(scheme),
                  ),
                  for (var index = 0; index < _fixedDrafts.length; index++)
                    _FixedTemplateEditor(
                      draft: _fixedDrafts[index],
                      monthly: _cadence == BudgetPlanCadenceV2.monthly,
                      onRemove: () => setState(() {
                        final removed = _fixedDrafts.removeAt(index);
                        removed.dispose();
                      }),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: AppType.caption(scheme)
                          .copyWith(color: AppColors.warning)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetInputBlock extends StatelessWidget {
  final String label;
  final Widget child;

  const _BudgetInputBlock({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.caption(Theme.of(context).colorScheme)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class _FixedTemplateEditor extends StatelessWidget {
  final _FixedTemplateDraft draft;
  final bool monthly;
  final VoidCallback onRemove;

  const _FixedTemplateEditor({
    required this.draft,
    required this.monthly,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: draft.name,
                    decoration: iosInputDecoration(context, hint: '名称'),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: draft.amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: iosInputDecoration(context, hint: '金额'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 92,
                        child: TextField(
                          controller: draft.due,
                          keyboardType: TextInputType.number,
                          decoration: iosInputDecoration(
                            context,
                            hint: monthly ? '到期日' : '星期 1-7',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            AppCircleButton(
              icon: Icons.close,
              size: 34,
              iconSize: 17,
              onPressed: onRemove,
            ),
          ],
        ),
      );
}

Future<void> showBudgetFixedOccurrencesSheet(
  BuildContext context,
  BudgetPlanV2 plan,
) =>
    showBlurSheet<void>(
      context,
      child: _BudgetFixedOccurrencesSheet(plan: plan),
    );

class _BudgetFixedOccurrencesSheet extends StatelessWidget {
  final BudgetPlanV2 plan;

  const _BudgetFixedOccurrencesSheet({required this.plan});

  String _status(FixedCommitmentEvaluation evaluation) =>
      switch (evaluation.displayStatus) {
        FixedCommitmentDisplayStatus.planned => '待匹配',
        FixedCommitmentDisplayStatus.matched => '已匹配',
        FixedCommitmentDisplayStatus.matchedFuture => '已匹配 · 待发生',
        FixedCommitmentDisplayStatus.overdue => '已逾期 · 仍预留',
        FixedCommitmentDisplayStatus.skipped => '本周期已跳过',
        FixedCommitmentDisplayStatus.requiresReview => '需要复核',
      };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final currentCycle = plan.cycleFor(DateTime.now());
    var occurrences = repo.budgetFixedOccurrencesV2For(
      plan.id,
      cycleStart: currentCycle.start,
    );
    final evaluationCycle =
        occurrences.firstOrNull?.occurrence.cycleStart ?? currentCycle.start;
    final evaluations = {
      for (final evaluation in repo.budgetFixedEvaluationsForCycle(
        plan.id,
        evaluationCycle,
      ))
        evaluation.occurrence.id: evaluation,
    };
    final templateNames = <String, String>{
      for (final revision in repo.budgetPlanRevisionsV2For(plan.id))
        for (final template in revision.fixedTemplates)
          template.id: template.name,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '固定支出',
            subtitle: plan.name,
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: occurrences.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                    child: Text(
                      '这个周期没有固定支出模板，可在“下周期修改”中添加。',
                      style: AppType.secondary(scheme),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Text(
                        '${occurrences.first.occurrence.cycleStart.month}/${occurrences.first.occurrence.cycleStart.day}'
                        ' - ${occurrences.first.occurrence.cycleEnd.month}/${occurrences.first.occurrence.cycleEnd.day}',
                        style: AppType.caption(scheme),
                      ),
                      const SizedBox(height: 8),
                      SettingsGroup(
                        margin: EdgeInsets.zero,
                        children: [
                          for (final entity in occurrences)
                            Builder(builder: (menuContext) {
                              final evaluation = evaluations[entity.id];
                              return SettingsRow(
                                leading:
                                    const Icon(Icons.event_repeat_outlined),
                                title:
                                    templateNames[entity.templateId] ?? '固定支出',
                                subtitle: evaluation == null
                                    ? '状态待刷新'
                                    : '${_status(evaluation)} · '
                                        '计划 ${MoneyFormat.string(budgetDecimalFromCents(entity.plannedCents)!)} · '
                                        '${entity.dueDate.month}/${entity.dueDate.day}',
                                trailing:
                                    const Icon(Icons.more_horiz, size: 18),
                                onTap: () => _showOccurrenceMenu(
                                  context,
                                  menuContext,
                                  repo,
                                  entity,
                                ),
                              );
                            }),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOccurrenceMenu(
    BuildContext context,
    BuildContext menuContext,
    AppRepository repo,
    BudgetFixedOccurrenceEntity entity,
  ) async {
    await showIosMenu(menuContext, [
      if (entity.resolutionStatus != FixedCommitmentResolutionStatus.skipped)
        IosMenuItem(
          label: entity.matchedTransactionFamilyId == null ? '匹配账单' : '更换账单',
          icon: Icons.link_outlined,
          onTap: () => _showMatchMenu(context, repo, entity),
        ),
      if (entity.occurrence.reviewReason ==
          FixedCommitmentReviewReason.refundAfterMatch)
        IosMenuItem(
          label: '接受退款后金额',
          icon: Icons.check_circle_outline,
          onTap: () => repo.acceptBudgetFixedRefundReview(entity.id),
        ),
      if (entity.resolutionStatus != FixedCommitmentResolutionStatus.skipped)
        IosMenuItem(
          label: '本周期跳过',
          icon: Icons.skip_next_outlined,
          onTap: () => repo.skipBudgetFixedOccurrence(entity.id),
        ),
      if (entity.resolutionStatus != FixedCommitmentResolutionStatus.planned ||
          entity.matchedTransactionFamilyId != null)
        IosMenuItem(
          label: '重置为待匹配',
          icon: Icons.restart_alt,
          onTap: () => repo.resetBudgetFixedOccurrence(entity.id),
        ),
    ]);
  }

  Future<void> _showMatchMenu(
    BuildContext context,
    AppRepository repo,
    BudgetFixedOccurrenceEntity entity,
  ) async {
    final candidates = repo.budgetFixedMatchCandidates(entity);
    if (candidates.isEmpty) {
      if (context.mounted) showAppToast(context, '本周期没有可匹配的支出账单');
      return;
    }
    await showIosMenu(context, [
      for (final transaction in candidates.take(20))
        IosMenuItem(
          label:
              '${transaction.note.isEmpty ? transaction.categoryNameZh : transaction.note} · '
              '${MoneyFormat.string(repo.netAmountAcrossBooks(transaction))}',
          icon: Icons.receipt_long_outlined,
          onTap: () => repo.matchBudgetFixedOccurrence(
            entity.id,
            transaction.uuid.isEmpty
                ? transaction.id.toString()
                : transaction.uuid,
          ),
        ),
    ]);
  }
}

/// 打开旧预算兼容弹层；只保留给历史测试和迁移后的查看流程。
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
  late final TextEditingController _incomeCtrl =
      TextEditingController(text: widget.edit?.monthlyIncome?.toString() ?? '');
  final Map<String, TextEditingController> _catCtrls = {};

  /// 「每月」= 无终点循环；「一次性期间（旧模式）」= 有起止日期。
  late bool _recurring = widget.edit == null ||
      (widget.edit!.recurringMonthly && widget.edit!.end == null);

  /// 自定义时间段的额度口径：true = 期间内每月额度，false = 整段总额。
  /// （模型层早就支持 recurringMonthly + end，这里补上 UI。）
  late bool _customMonthly = widget.edit != null &&
      widget.edit!.recurringMonthly &&
      widget.edit!.end != null;
  late DateTimeRange? _customRange =
      widget.edit != null && widget.edit!.end != null
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
    }
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _incomeCtrl.dispose();
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

  // ── 智能建议（辅助功能，收在折叠区）──────────────────────────────────────
  // 口径：总预算含固定支出。填了收入 = 收入 × 80%（留 20% 储蓄）；
  // 不填收入 = 近 3 个月平均月支出（记过账就能给建议）。
  void _suggest(AppRepository repo) {
    final income = Decimal.tryParse(_incomeCtrl.text.trim());
    final total = income != null && income > Decimal.zero
        ? BudgetSuggestion.suggestFromIncome(income)
        : BudgetSuggestion.averageMonthlySpend(repo.allRecords,
            now: DateTime.now());
    if (total == null) {
      setState(() => _formError = '最近还没什么支出记录，填一下月收入喵就能按 80% 帮你算');
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
      setState(() => _formError = '一次性期间要先选起止日期');
      return;
    }

    final catBudgets = <String, Decimal>{};
    _catCtrls.forEach((key, ctrl) {
      final v = Decimal.tryParse(ctrl.text.trim());
      if (v != null && v > Decimal.zero) catBudgets[key] = v;
    });
    // 分类合计不能超过总预算，超了禁存（这是逻辑矛盾，不只是提醒）。
    final catSum = catBudgets.values.fold(Decimal.zero, (a, b) => a + b);
    if (catSum > total) {
      setState(() => _formError =
          '分类合计 ${MoneyFormat.string(catSum)} 超过了总预算 ${MoneyFormat.string(total)}，先调一下');
      return;
    }

    // 编辑无终点的循环计划会重写它覆盖的所有历史月份，先跟用户说清楚。
    if (_isEdit && widget.edit!.recurringMonthly && widget.edit!.end == null) {
      final s = widget.edit!.start;
      final ok = await showConfirmDialog(
        context,
        title: '修改这条循环预算？',
        message: s.year <= 2000
            ? '它覆盖所有历史月份，改完后过去每个月显示的预算都会跟着变。'
            : '它从 ${s.year} 年 ${s.month} 月起生效，改完后那之后每个月显示的预算都会跟着变。',
        confirmText: '仍要修改',
      );
      if (!ok || !mounted) return;
    }

    final now = DateTime.now();
    // 首条循环预算从 2000 年起覆盖全部历史月份（老账单也有预算可看）；
    // 之后再新建的才从本月生效，历史月仍显示当时那条。
    final hasRecurring =
        repo.budgetPeriods.any((p) => p.recurringMonthly && p.end == null);
    final start = _recurring
        ? (_isEdit
            ? widget.edit!.start // 编辑循环计划保留原生效起点
            : (hasRecurring
                ? DateTime(now.year, now.month, 1)
                : DateTime(2000, 1, 1)))
        : _customRange!.start;
    final end = _recurring ? null : _customRange!.end;
    // 自定义时间段支持两种口径：每月额度（recurring + end）/ 整段总额。
    final recurringMonthly = _recurring || _customMonthly;
    final income = Decimal.tryParse(_incomeCtrl.text.trim());

    if (_isEdit) {
      await repo.updateBudgetPeriod(
        widget.edit!.id,
        bookId: _bookId,
        start: start,
        end: end,
        recurringMonthly: recurringMonthly,
        total: total,
        categoryBudgets: catBudgets,
        monthlyIncome: income,
      );
    } else {
      await repo.addBudgetPeriod(
        bookId: _bookId,
        start: start,
        end: end,
        recurringMonthly: recurringMonthly,
        total: total,
        categoryBudgets: catBudgets,
        monthlyIncome: income,
      );
    }
    Haptics.of(Haptic.success);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showAppDateRangePicker(
      context,
      initial: _customRange,
      first: DateTime(2000),
      last: DateTime(now.year + 2, 12, 31),
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
          SheetHeader(
            title: _isEdit ? '编辑预算' : '新建预算',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: () => _save(repo),
          ),
          Flexible(
            child: SingleChildScrollView(
              // 底部多留一截，最后一行分类不被保存按钮/手势条挡住。
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 范围 + 周期 ──
                  SizedBox(
                    width: double.infinity,
                    child: SlidingSegment<bool>(
                      items: const [
                        (true, '每月'),
                        (false, '一次性期间（旧模式）'),
                      ],
                      value: _recurring,
                      onChanged: (v) {
                        Haptics.selection();
                        setState(() => _recurring = v);
                        if (!v && _customRange == null) _pickCustomRange();
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Builder(
                      builder: (chipCtx) {
                        final selectedBook = repo.books
                            .where((b) => b.id == _bookId)
                            .firstOrNull;
                        final bookLabel = _bookId == null
                            ? '全部账本'
                            : selectedBook?.name ?? '账本';
                        return AppBookSwitchChip(
                          iconText: _bookId == null
                              ? '📚'
                              : (selectedBook?.icon ?? '📒'),
                          label: bookLabel,
                          maxLabelWidth: 120,
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
                        );
                      },
                    ),
                  ),
                  if (!_recurring) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        PressableScale(
                          onPressed: _pickCustomRange,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.card(scheme),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: AppColors.hairline(scheme)),
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 额度口径二选一：期间内每个月各给一份，还是整段共用一笔。
                    SizedBox(
                      width: 196,
                      child: SlidingSegment<bool>(
                        items: const [(true, '每月额度'), (false, '整段总额')],
                        value: _customMonthly,
                        onChanged: (v) {
                          Haptics.selection();
                          setState(() => _customMonthly = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _customMonthly
                          ? '期间内每个月都是这个额度（如 1–7 月每月 4000）'
                          : '整段期间共用这一笔总额（如一次旅行）',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── 本月预算（含房租等固定支出）+ 智能建议按钮 ──
                  Text(
                    !_recurring && !_customMonthly ? '期间预算总额' : '本月预算',
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _totalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: iosInputDecoration(context,
                              hint: '如 4000', prefix: '¥ '),
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
                                color: scheme.primary.withValues(alpha: 0.35)),
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

                  // ── 智能建议折叠区（收入选填 + 生成）──
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
                          Text('月收入（选填）',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _incomeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: iosInputDecoration(context,
                                hint: '不填就按近 3 个月平均支出算', prefix: '¥ '),
                          ),
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
                            '建议含房租等固定支出：填收入按 80% 算（留 20% 储蓄），'
                            '不填按你近 3 个月平均支出算；再按消费结构分到各分类',
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
                  Builder(builder: (_) {
                    // 「已分配 ¥x / 总预算」实时提示，超了标橙（保存时也会拦）。
                    var catSum = Decimal.zero;
                    for (final c in _catCtrls.values) {
                      final v = Decimal.tryParse(c.text.trim());
                      if (v != null && v > Decimal.zero) catSum += v;
                    }
                    final total = Decimal.tryParse(_totalCtrl.text.trim());
                    final over =
                        total != null && total > Decimal.zero && catSum > total;
                    return Row(
                      children: [
                        Text('分类预算（可选）',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        if (catSum > Decimal.zero)
                          Text(
                            '已分配 ${MoneyFormat.string(catSum)}'
                            '${total == null || total <= Decimal.zero ? '' : ' / ${MoneyFormat.string(total)}'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'Nunito',
                              color: over
                                  ? AppColors.warning
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    );
                  }),
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
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.end,
                            onChanged: (_) => setState(() {}),
                            decoration: iosInputDecoration(context,
                                hint: '0', prefix: '¥ '),
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
