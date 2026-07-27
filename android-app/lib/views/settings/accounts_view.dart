import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../assets/account_detail_page.dart';
import '../assets/account_form_sheet.dart';
import '../assets/asset_add_entry_sheet.dart';
import '../assets/asset_overview_cards.dart';
import '../assets/funds_tab_cards.dart';
import '../assets/net_worth_trend_card.dart';
import '../assets/physical_asset_detail_page.dart';
import '../assets/physical_asset_form_sheet.dart';
import '../assets/physical_asset_grid.dart';
import '../assets/physical_asset_purchase_sheet.dart';
import '../assets/borrow_form_sheet.dart';
import '../assets/lending_view.dart';
import '../assets/loan_wizard_sheet.dart';
import '../assets/receivable_detail_page.dart';
import '../assets/receivable_sheets.dart';
import '../assets/repayment_sheet.dart';
import '../common/app_sheet.dart';
import '../reports/report_views.dart';
import '../../widgets/sliding_segment.dart';

enum _AssetView { overview, funds, items }

enum _AssetListVisibility { active, archived }

enum _ItemKind { all, active, idle, ended }

/// 资产管理固定为全局范围，账本只作为物品和权益的归属信息。
class AccountsView extends StatefulWidget {
  const AccountsView({super.key});

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  _AssetView _view = _AssetView.overview;
  _AssetListVisibility _fundsVisibility = _AssetListVisibility.active;
  bool _zeroBalanceAccountsExpanded = false;
  _AssetListVisibility _itemsVisibility = _AssetListVisibility.active;
  _ItemKind _itemKind = _ItemKind.all;
  AssetType? _itemType;
  final _itemSearchController = TextEditingController();

  @override
  void dispose() {
    _itemSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('资产管理'),
        actions: [
          if (_view == _AssetView.overview)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(
                builder: (buttonContext) => AppCircleButton(
                  icon: Icons.more_horiz,
                  onPressed: () => _showOverviewMenu(buttonContext),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppCircleButton(
              icon: Icons.add,
              onPressed: () => _showAddForCurrentView(context),
            ),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final accounts = repo.accounts.where((a) => !a.isDeleted).toList();
          final physicalAssets = repo.globalActivePhysicalAssets;
          final archivedAssets = repo.globalArchivedPhysicalAssets;
          final receivableAssets = repo.globalActiveReceivables;
          final archivedReceivables = repo.globalArchivedReceivables;
          final balances = <FundsAccountBalance>[];
          for (final account in accounts) {
            final result = repo.accountBalanceResultOf(account);
            final movement = result.value!.movement;
            final qualityText = movement.unknownSettlementAccountCount > 0
                ? '${movement.unknownSettlementAccountCount} 笔到账账户待确认'
                : movement.unknownSettlementDateCount > 0
                    ? '${movement.unknownSettlementDateCount} 笔到账日期待确认'
                    : movement.assumedAccountCount > 0 ||
                            movement.assumedSettlementDateCount > 0
                        ? '含估算数据'
                        : null;
            balances.add(FundsAccountBalance(
              account: account,
              balance: result.value!.balance,
              qualityText: qualityText,
            ));
          }
          final includedBalances = balances
              .where((item) =>
                  item.account.includeInNetWorth &&
                  item.account.currencyCode == 'CNY')
              .toList();
          final countedPhysicalCount =
              repo.physicalAssetsCountedInNetWorth.length;
          final countedReceivableCount =
              repo.receivableAssetsCountedInNetWorth.length;
          final netWorthResult = repo.currentNetWorthResult();
          final breakdown = netWorthResult.value!;
          final totalCount = accounts.length +
              physicalAssets.length +
              archivedAssets.length +
              receivableAssets.length +
              archivedReceivables.length;
          final includedCount = includedBalances.length +
              countedPhysicalCount +
              countedReceivableCount;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: SlidingSegment<_AssetView>(
                  key: const Key('asset-view-segment'),
                  items: const [
                    (_AssetView.overview, '总览'),
                    (_AssetView.funds, '资金'),
                    (_AssetView.items, '物品'),
                  ],
                  value: _view,
                  onChanged: (value) => setState(() => _view = value),
                ),
              ),
              Expanded(
                child: switch (_view) {
                  _AssetView.overview => _buildOverview(
                      context,
                      repo,
                      breakdown: breakdown,
                      physicalAssets: physicalAssets,
                      receivableAssets: receivableAssets,
                      netWorthPartial:
                          netWorthResult.status != MetricStatus.available,
                      includedCount: includedCount,
                      totalCount: totalCount,
                    ),
                  _AssetView.funds => _buildFunds(
                      context,
                      balances: balances,
                      receivableAssets: receivableAssets,
                      archivedReceivables: archivedReceivables,
                      upcomingRepayments: repo.upcomingRepayments(),
                      // 借贷往来入口：有借出权益或个人借入档案才显示。
                      hasLendingData: [
                            ...receivableAssets,
                            ...archivedReceivables,
                          ].any((a) => a.type == ReceivableAssetType.loanOut) ||
                          repo.liabilityProfiles.any((p) =>
                              p.type == LiabilityProfileType.personalBorrow),
                    ),
                  _AssetView.items => _buildItems(
                      context,
                      physicalAssets: physicalAssets,
                      archivedAssets: archivedAssets,
                    ),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverview(
    BuildContext context,
    AppRepository repo, {
    required NetWorthBreakdown breakdown,
    required List<PhysicalAssetEntity> physicalAssets,
    required List<ReceivableAssetEntity> receivableAssets,
    required bool netWorthPartial,
    required int includedCount,
    required int totalCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 待处理卡只留「用户要去做事」的任务型条目；
    // 数据口径类条目收进右上 ⋯ 菜单的「数据待完善」弹层。
    final warrantyReminderCount = physicalAssets
        .where((asset) => repo.warrantyReminderForAsset(asset).needsAttention)
        .length;
    final receivableDueReminderCount = receivableAssets
        .where((asset) => repo.dueReminderForReceivable(asset).needsAttention)
        .length;
    final pending = <AssetPendingItem>[
      if (warrantyReminderCount > 0)
        AssetPendingItem(
          icon: Icons.verified_user_outlined,
          text: '$warrantyReminderCount 件物品保修即将到期或已过期',
          onTap: () => setState(() {
            _view = _AssetView.items;
            _itemsVisibility = _AssetListVisibility.active;
            _itemKind = _ItemKind.all;
          }),
        ),
      if (receivableDueReminderCount > 0)
        AssetPendingItem(
          icon: Icons.event_busy_outlined,
          text: '$receivableDueReminderCount 项权益即将到期或已逾期',
          onTap: () => setState(() {
            _view = _AssetView.funds;
            _fundsVisibility = _AssetListVisibility.active;
          }),
        ),
    ];
    final fundsAssets = breakdown.cashAssets +
        breakdown.investmentAssets +
        breakdown.receivableAssets;
    final fundsNetWorth = fundsAssets - breakdown.totalLiabilities;
    final hasVerifiedCheckpoint = repo.verifiedNetWorthCheckpoints.any(
      (checkpoint) =>
          checkpoint.header.status == NetWorthVerifiedCheckpointStatus.active,
    );

    return ListView(
      key: const Key('asset-overview'),
      // 顶部留 12：探头猫探出卡顶 8dp，ListView 默认 Clip.hardEdge 会裁，
      // padding 不够猫头就没了。
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // hero 数字 + 迷你趋势合成一张卡（数字上、趋势下），
        // 右上角照主页手法挂探头猫（home_summary_card.dart 同款）。
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: appCardDecoration(scheme),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AssetSummaryCard(
                    netWorth: breakdown.netWorth,
                    fundsAssets: fundsAssets,
                    physicalAssets: breakdown.physicalAssets,
                    fundsNetWorth: fundsNetWorth,
                    liabilityTotal: breakdown.totalLiabilities,
                    totalAssets: breakdown.totalAssets,
                    includedCount: includedCount,
                    accountCount: totalCount,
                    partial: netWorthPartial,
                    embedded: true,
                  ),
                  appCardDivider(scheme),
                  NetWorthEstimatedTrendCard(
                    trend: repo.netWorthEstimatedTrend,
                    embedded: true,
                  ),
                ],
              ),
            ),
            Positioned(
              top: -8,
              right: -4,
              child: IgnorePointer(
                child: MascotBreath(
                  bob: 2.0,
                  sway: 0,
                  alignment: Alignment.centerRight,
                  child: Image.asset(
                    'assets/mascot/idle.webp',
                    // 比主页的 96 小一号，避免和 hero 大数字抢空间。
                    height: 80,
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          AssetPendingCard(items: pending),
        ],
        if (hasVerifiedCheckpoint) ...[
          const SizedBox(height: 12),
          VerifiedNetWorthCard(
            checkpoints: repo.verifiedNetWorthCheckpoints,
            comparison: repo.latestVerifiedNetWorthComparison,
          ),
        ],
        const SizedBox(height: 12),
        AssetAnalysisCard(breakdown: breakdown),
      ],
    );
  }

  /// 数据口径类待完善条目（非任务型）：账户到账待确认 / 历史物品、权益待确认 /
  /// 外币未含 / 缺购买日期。从右上 ⋯ 菜单的「数据待完善」弹层进入。
  List<AssetPendingItem> _dataCompletionItems(AppRepository repo) {
    final accounts = repo.accounts.where((a) => !a.isDeleted).toList();
    var accountQualityIssueCount = 0;
    for (final account in accounts) {
      if (!account.includeInNetWorth || account.currencyCode != 'CNY') {
        continue;
      }
      final movement = repo.accountBalanceResultOf(account).value!.movement;
      final hasIssue = movement.unknownSettlementAccountCount > 0 ||
          movement.unknownSettlementDateCount > 0 ||
          movement.assumedAccountCount > 0 ||
          movement.assumedSettlementDateCount > 0;
      if (hasIssue) accountQualityIssueCount++;
    }
    final allPhysical = [
      ...repo.globalActivePhysicalAssets,
      ...repo.globalArchivedPhysicalAssets,
    ];
    final allReceivables = [
      ...repo.globalActiveReceivables,
      ...repo.globalArchivedReceivables,
    ];
    final physicalReviewCount = allPhysical
        .where((a) => a.inclusionQuality == AssetInclusionQuality.needsReview)
        .length;
    final receivableReviewCount = allReceivables
        .where((a) => a.inclusionQuality == AssetInclusionQuality.needsReview)
        .length;
    final missingPurchaseDateCount = repo.globalActivePhysicalAssets
        .where((a) =>
            a.economicStatus == PhysicalAssetEconomicStatus.owned &&
            a.purchaseDate == null)
        .length;
    final unsupportedCurrencies = repo.unsupportedNetWorthCurrencyCodes.toList()
      ..sort();
    return <AssetPendingItem>[
      if (accountQualityIssueCount > 0)
        AssetPendingItem(
          icon: Icons.account_balance_wallet_outlined,
          text: '$accountQualityIssueCount 个账户的到账信息待确认',
          onTap: () => setState(() => _view = _AssetView.funds),
        ),
      if (physicalReviewCount > 0)
        AssetPendingItem(
          icon: Icons.fact_check_outlined,
          text: '$physicalReviewCount 件历史物品待确认',
          onTap: () => setState(() {
            _view = _AssetView.items;
            _itemsVisibility = _AssetListVisibility.archived;
            _itemKind = _ItemKind.all;
          }),
        ),
      if (receivableReviewCount > 0)
        AssetPendingItem(
          icon: Icons.assignment_late_outlined,
          text: '$receivableReviewCount 项历史权益待确认',
          onTap: () => setState(() {
            _view = _AssetView.funds;
            _fundsVisibility = _AssetListVisibility.archived;
          }),
        ),
      if (unsupportedCurrencies.isNotEmpty)
        AssetPendingItem(
          icon: Icons.currency_exchange_outlined,
          text: '未含 ${unsupportedCurrencies.join('、')} 外币资产或负债',
          onTap: () => setState(() => _view = _AssetView.funds),
        ),
      if (missingPurchaseDateCount > 0)
        AssetPendingItem(
          icon: Icons.event_busy_outlined,
          text: '$missingPurchaseDateCount 件物品缺少购买日期，日均暂不可计算',
          onTap: () => setState(() => _view = _AssetView.items),
        ),
    ];
  }

  void _showOverviewMenu(BuildContext anchorContext) {
    final repo = context.read<AppRepository>();
    final dataItems = _dataCompletionItems(repo);
    showIosMenu(anchorContext, [
      IosMenuItem(
        label: '净资产核对',
        icon: Icons.fact_check_outlined,
        onTap: () => _verifyNetWorth(context, repo),
      ),
      IosMenuItem(
        label: '生成报告',
        icon: Icons.description_outlined,
        onTap: () => _generateAssetReport(context, repo),
      ),
      if (dataItems.isNotEmpty)
        IosMenuItem(
          label: '数据待完善 (${dataItems.length})',
          icon: Icons.rule_outlined,
          onTap: () => _showDataCompletionSheet(context, dataItems),
        ),
    ]);
  }

  Future<void> _verifyNetWorth(BuildContext context, AppRepository repo) async {
    final staleCount = repo.stalePhysicalValuationCount();
    final confirmed = await showConfirmDialog(
      context,
      title: '核对当前净资产',
      message: staleCount > 0
          ? '有 $staleCount 件物品使用超过 90 天的最近估值。继续表示你接受这些估值日期；数据仍有缺口时会保存为“部分核对”。'
          : '会保存当前所有金额作为核对记录。数据仍有缺口时会保存为“部分核对”，不会冒充完整确认。',
      confirmText: staleCount > 0 ? '接受并核对' : '开始核对',
    );
    if (!confirmed) return;
    final checkpoint = await repo.createVerifiedNetWorthCheckpoint(
      acceptStaleValuations: staleCount > 0,
    );
    if (!context.mounted) return;
    showAppToast(
      context,
      checkpoint.header.completeness ==
              NetWorthVerifiedCheckpointCompleteness.complete
          ? '已完成净资产核对'
          : '已保存部分核对，待确认项仍会保留',
      mascot: MascotMood.success,
    );
  }

  Future<void> _generateAssetReport(
    BuildContext context,
    AppRepository repo,
  ) async {
    final id = await repo.createAssetReport();
    final report = await repo.getReport(id);
    if (!context.mounted) return;
    if (report == null) {
      showAppToast(context, '报告生成失败，请重试', icon: Icons.error_outline);
      return;
    }
    openReportReader(context, report);
  }

  void _showDataCompletionSheet(
    BuildContext context,
    List<AssetPendingItem> items,
  ) {
    showBlurSheet<void>(
      context,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: '数据待完善',
              onClose: () => Navigator.pop(context),
            ),
            SettingsGroup(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              children: [
                for (final item in items)
                  SettingsRow(
                    leading: Icon(item.icon),
                    title: item.text,
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      item.onTap();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunds(
    BuildContext context, {
    required List<FundsAccountBalance> balances,
    required List<ReceivableAssetEntity> receivableAssets,
    required List<ReceivableAssetEntity> archivedReceivables,
    required List<UpcomingRepaymentItem> upcomingRepayments,
    required bool hasLendingData,
  }) {
    // 种类筛选已删除：列表本就按账户类型分组，够用；只留「当前项目/已归档」一维切换。
    final showArchived = _fundsVisibility == _AssetListVisibility.archived;
    final activeBalances =
        balances.where((item) => !item.account.isArchived).toList();
    final archivedBalances =
        balances.where((item) => item.account.isArchived).toList();
    final archivedCount = archivedBalances.length + archivedReceivables.length;
    final currentBalances = showArchived ? archivedBalances : activeBalances;
    final currentReceivables =
        showArchived ? archivedReceivables : receivableAssets;
    // ¥0 账户只在「当前项目」视图折叠进底部卡；归档视图原样平铺，不折叠。
    final zeroItems = showArchived
        ? const <FundsAccountBalance>[]
        : [
            for (final group in _groupBalances(currentBalances
                .where((item) => item.balance == Decimal.zero)
                .toList()))
              ...group.items,
          ];
    final nonZeroBalances = showArchived
        ? currentBalances
        : currentBalances
            .where((item) => item.balance != Decimal.zero)
            .toList();
    final groups = _groupBalances(nonZeroBalances);
    final hasArchiveLink = !showArchived && archivedCount > 0;
    final showLendingEntry = !showArchived && hasLendingData;
    final isEmpty = groups.isEmpty &&
        currentReceivables.isEmpty &&
        zeroItems.isEmpty &&
        !hasArchiveLink &&
        !showLendingEntry;

    return Column(
      key: const Key('asset-funds'),
      children: [
        Expanded(
          child: isEmpty
              ? const AssetEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (showArchived) ...[
                      FundsArchiveBackRow(
                        onTap: () => setState(() =>
                            _fundsVisibility = _AssetListVisibility.active),
                      ),
                      const SizedBox(height: 6),
                    ],
                    // 「最近要还」置顶：10 天内到期的还款比静态列表更紧急。
                    if (!showArchived && upcomingRepayments.isNotEmpty) ...[
                      UpcomingRepaymentsCard(
                        items: upcomingRepayments,
                        onRepay: (item) => _showRepaymentSheet(context, item),
                      ),
                      if (currentReceivables.isNotEmpty ||
                          groups.isNotEmpty ||
                          zeroItems.isNotEmpty)
                        const SizedBox(height: 12),
                    ],
                    // 借贷往来入口：紧跟「最近要还」，与已归档入口同款轻量行。
                    if (showLendingEntry) ...[
                      LendingEntryRow(onTap: () => _openLending(context)),
                      const SizedBox(height: 6),
                    ],
                    if (currentReceivables.isNotEmpty)
                      ReceivableAssetGroupCard(
                        assets: currentReceivables,
                        onTap: (asset) => _showReceivableDetail(context, asset),
                      ),
                    for (final group in groups) ...[
                      if (currentReceivables.isNotEmpty ||
                          group != groups.first)
                        const SizedBox(height: 12),
                      FundsAccountGroupCard(
                        group: group,
                        onTap: (account) =>
                            _showAccountDetail(context, account),
                      ),
                    ],
                    if (zeroItems.isNotEmpty) ...[
                      if (groups.isNotEmpty || currentReceivables.isNotEmpty)
                        const SizedBox(height: 12),
                      ZeroBalanceAccountsCard(
                        items: zeroItems,
                        expanded: _zeroBalanceAccountsExpanded,
                        onToggleExpanded: () => setState(() =>
                            _zeroBalanceAccountsExpanded =
                                !_zeroBalanceAccountsExpanded),
                        onTap: (account) =>
                            _showAccountDetail(context, account),
                      ),
                    ],
                    if (hasArchiveLink) ...[
                      const SizedBox(height: 12),
                      FundsArchiveEntryRow(
                        count: archivedCount,
                        onTap: () => setState(() =>
                            _fundsVisibility = _AssetListVisibility.archived),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildItems(
    BuildContext context, {
    required List<PhysicalAssetEntity> physicalAssets,
    required List<PhysicalAssetEntity> archivedAssets,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final source = _itemsVisibility == _AssetListVisibility.archived
        ? archivedAssets
        : physicalAssets;
    final query = _itemSearchController.text.trim().toLowerCase();
    final filtered = source.where((asset) {
      final owned = asset.economicStatus == PhysicalAssetEconomicStatus.owned;
      final kindMatched = switch (_itemKind) {
        _ItemKind.all => true,
        _ItemKind.active =>
          owned && asset.usageStatus == PhysicalAssetUsageStatus.active,
        _ItemKind.idle =>
          owned && asset.usageStatus == PhysicalAssetUsageStatus.idle,
        _ItemKind.ended => !owned,
      };
      if (!kindMatched) return false;
      if (_itemType != null && asset.assetType != _itemType) return false;
      if (query.isEmpty) return true;
      return [
        asset.name,
        asset.brand,
        asset.model,
        asset.note,
        asset.location,
      ].any((value) => value.toLowerCase().contains(query));
    }).toList(growable: false);
    final allEmpty = physicalAssets.isEmpty && archivedAssets.isEmpty;
    // 直接压在渐变背景上的输入框用半透明卡底+发丝边，不透明 inputFill 会突兀。
    final hairlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.hairline(scheme)),
    );

    return Column(
      key: const Key('asset-items'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: TextField(
            key: const Key('asset-grid-search'),
            controller: _itemSearchController,
            textInputAction: TextInputAction.search,
            decoration: iosInputDecoration(
              context,
              hint: '搜索物品',
            ).copyWith(
              prefixIcon: const Icon(Icons.search, size: 19),
              fillColor: AppColors.card(scheme),
              border: hairlineBorder,
              enabledBorder: hairlineBorder,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                _LightFilterDropdown(
                  label: _itemKindLabel(_itemKind),
                  active: _itemKind != _ItemKind.all,
                  itemsBuilder: () => [
                    for (final kind in _ItemKind.values)
                      IosMenuItem(
                        label: _itemKindLabel(kind),
                        icon: _itemKindIcon(kind),
                        selected: kind == _itemKind,
                        onTap: () => setState(() => _itemKind = kind),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                _LightFilterDropdown(
                  label: _itemType?.label ?? '全部分类',
                  active: _itemType != null,
                  itemsBuilder: () => [
                    IosMenuItem(
                      label: '全部分类',
                      icon: Icons.inventory_2_outlined,
                      selected: _itemType == null,
                      onTap: () => setState(() => _itemType = null),
                    ),
                    for (final type in AssetType.values)
                      IosMenuItem(
                        label: type.label,
                        icon: assetTypeIcon(type),
                        selected: type == _itemType,
                        onTap: () => setState(() => _itemType = type),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                _LightFilterDropdown(
                  label: _visibilityLabel(_itemsVisibility),
                  active: _itemsVisibility != _AssetListVisibility.active,
                  itemsBuilder: () => [
                    for (final visibility in _AssetListVisibility.values)
                      IosMenuItem(
                        label: _visibilityLabel(visibility),
                        icon: visibility == _AssetListVisibility.active
                            ? Icons.visibility_outlined
                            : Icons.archive_outlined,
                        selected: visibility == _itemsVisibility,
                        onTap: () =>
                            setState(() => _itemsVisibility = visibility),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? AppEmptyState(
                  mood: MascotMood.empty,
                  title: allEmpty ? '还没有物品' : '没有匹配的物品',
                  message: allEmpty ? '记一笔购买账单，就能追踪它的使用成本啦' : null,
                )
              : PhysicalAssetGrid(
                  assets: filtered,
                  onTap: (asset) => _showAssetDetail(context, asset),
                ),
        ),
      ],
    );
  }

  List<FundsAccountGroup> _groupBalances(List<FundsAccountBalance> balances) {
    final groups = <FundsAccountGroup>[];
    for (final type in AccountType.values) {
      final items =
          balances.where((item) => item.account.type == type).toList();
      if (items.isEmpty) continue;
      items.sort((a, b) {
        final sort = a.account.sortOrder.compareTo(b.account.sortOrder);
        if (sort != 0) return sort;
        return a.account.name.compareTo(b.account.name);
      });
      groups.add(FundsAccountGroup(type: type, items: items));
    }
    return groups;
  }

  /// 右上 ＋ 在三个 tab 行为一致：一律打开同一张统一「添加」弹层。
  void _showAddForCurrentView(BuildContext context) => _showAddSheet(context);

  void _showAddSheet(BuildContext context) {
    final repo = context.read<AppRepository>();
    // 「从最近账单加入」一步直达：预取最近几笔可加入的支出账单内嵌进弹层。
    final recentCandidates = repo
        .eligiblePhysicalAssetPurchaseTransactions()
        .take(3)
        .toList(growable: false);
    showBlurSheet<void>(
      context,
      child: AssetAddEntrySheet(
        recentCandidates: recentCandidates,
        onAccount: () {
          Navigator.pop(context);
          _showAddAccountSheet(context);
        },
        onReceivableAsset: () {
          Navigator.pop(context);
          _showAddReceivableSheet(context);
        },
        onBorrow: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showBlurSheet<void>(
              context,
              child: const BorrowFormSheet(),
            );
          });
        },
        onLoanWizard: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showLoanWizardSheet(context);
          });
        },
        onNewPurchase: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showBlurSheet<void>(
              context,
              child: const PhysicalAssetFormSheet(
                sourceType: PhysicalAssetSourceType.newPurchaseWithAccount,
              ),
            );
          });
        },
        onFromTransaction: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showPhysicalAssetPurchaseSheet(context, repository: repo);
          });
        },
        onRecentCandidate: (candidate) {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showPhysicalAssetPurchaseSheet(
              context,
              repository: repo,
              initialCandidate: candidate,
            );
          });
        },
        onManual: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showBlurSheet<void>(
              context,
              child: const PhysicalAssetFormSheet(),
            );
          });
        },
      ),
    );
  }

  void _showAddAccountSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: const AccountFormSheet(),
    );
  }

  void _showAddReceivableSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: const ReceivableAssetFormSheet(),
    );
  }

  void _showRepaymentSheet(BuildContext context, UpcomingRepaymentItem item) {
    showBlurSheet<void>(
      context,
      child: RepaymentSheet(profile: item.profile),
    );
  }

  void _openLending(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const LendingView(),
      ),
    );
  }

  void _showReceivableDetail(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ReceivableAssetDetailPage(asset: asset),
      ),
    );
  }

  void _showAssetDetail(BuildContext context, PhysicalAssetEntity asset) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => PhysicalAssetDetailPage(
          assetId: asset.id,
          fallbackAsset: asset,
        ),
      ),
    );
  }

  void _showAccountDetail(BuildContext context, AccountEntity account) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => AccountDetailPage(account: account),
      ),
    );
  }
}

String _visibilityLabel(_AssetListVisibility value) => switch (value) {
      _AssetListVisibility.active => '当前项目',
      _AssetListVisibility.archived => '已归档',
    };

String _itemKindLabel(_ItemKind value) => switch (value) {
      _ItemKind.all => '全部物品',
      _ItemKind.active => '在用',
      _ItemKind.idle => '闲置',
      _ItemKind.ended => '已结束',
    };

IconData _itemKindIcon(_ItemKind value) => switch (value) {
      _ItemKind.all => Icons.inventory_2_outlined,
      _ItemKind.active => Icons.check_circle_outline,
      _ItemKind.idle => Icons.pause_circle_outline,
      _ItemKind.ended => Icons.history_outlined,
    };

/// 轻量文字下拉（用户 2026-07-26 拍板）：无底无边框的「文字+⌄」，
/// 和顶部分段胶囊拉开层级；选中非默认值时整体变主色表示筛选已激活。
class _LightFilterDropdown extends StatelessWidget {
  final String label;
  final bool active;
  final List<IosMenuItem> Function() itemsBuilder;

  const _LightFilterDropdown({
    required this.label,
    required this.active,
    required this.itemsBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : AppTextColor.secondary(scheme);
    return Builder(
      builder: (menuContext) => PressableScale(
        onPressed: () => showIosMenu(menuContext, itemsBuilder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppType.secondary(scheme).copyWith(color: color),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
