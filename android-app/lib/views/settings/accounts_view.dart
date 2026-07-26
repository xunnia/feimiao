import 'dart:async';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../assets/account_activity_list.dart';
import '../assets/asset_add_entry_sheet.dart';
import '../assets/asset_form_kit.dart';
import '../assets/net_worth_trend_card.dart';
import '../assets/physical_asset_detail_page.dart';
import '../assets/physical_asset_form_sheet.dart';
import '../assets/physical_asset_grid.dart';
import '../assets/physical_asset_purchase_sheet.dart';
import '../assets/receivable_detail_page.dart';
import '../assets/receivable_sheets.dart';
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
          final balances = <_AccountBalance>[];
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
            balances.add(_AccountBalance(
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
    final pending = <_AssetPendingItem>[
      if (warrantyReminderCount > 0)
        _AssetPendingItem(
          icon: Icons.verified_user_outlined,
          text: '$warrantyReminderCount 件物品保修即将到期或已过期',
          onTap: () => setState(() {
            _view = _AssetView.items;
            _itemsVisibility = _AssetListVisibility.active;
            _itemKind = _ItemKind.all;
          }),
        ),
      if (receivableDueReminderCount > 0)
        _AssetPendingItem(
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // hero 数字 + 迷你趋势合成一张卡（数字上、趋势下）。
        Container(
          decoration: appCardDecoration(scheme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AssetSummaryCard(
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
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AssetPendingCard(items: pending),
        ],
        if (hasVerifiedCheckpoint) ...[
          const SizedBox(height: 12),
          _VerifiedNetWorthCard(
            checkpoints: repo.verifiedNetWorthCheckpoints,
            comparison: repo.latestVerifiedNetWorthComparison,
          ),
        ],
        const SizedBox(height: 12),
        _AssetAnalysisCard(breakdown: breakdown),
      ],
    );
  }

  /// 数据口径类待完善条目（非任务型）：账户到账待确认 / 历史物品、权益待确认 /
  /// 外币未含 / 缺购买日期。从右上 ⋯ 菜单的「数据待完善」弹层进入。
  List<_AssetPendingItem> _dataCompletionItems(AppRepository repo) {
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
    final unsupportedCurrencies =
        repo.unsupportedNetWorthCurrencyCodes.toList()..sort();
    return <_AssetPendingItem>[
      if (accountQualityIssueCount > 0)
        _AssetPendingItem(
          icon: Icons.account_balance_wallet_outlined,
          text: '$accountQualityIssueCount 个账户的到账信息待确认',
          onTap: () => setState(() => _view = _AssetView.funds),
        ),
      if (physicalReviewCount > 0)
        _AssetPendingItem(
          icon: Icons.fact_check_outlined,
          text: '$physicalReviewCount 件历史物品待确认',
          onTap: () => setState(() {
            _view = _AssetView.items;
            _itemsVisibility = _AssetListVisibility.archived;
            _itemKind = _ItemKind.all;
          }),
        ),
      if (receivableReviewCount > 0)
        _AssetPendingItem(
          icon: Icons.assignment_late_outlined,
          text: '$receivableReviewCount 项历史权益待确认',
          onTap: () => setState(() {
            _view = _AssetView.funds;
            _fundsVisibility = _AssetListVisibility.archived;
          }),
        ),
      if (unsupportedCurrencies.isNotEmpty)
        _AssetPendingItem(
          icon: Icons.currency_exchange_outlined,
          text: '未含 ${unsupportedCurrencies.join('、')} 外币资产或负债',
          onTap: () => setState(() => _view = _AssetView.funds),
        ),
      if (missingPurchaseDateCount > 0)
        _AssetPendingItem(
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
    List<_AssetPendingItem> items,
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
    required List<_AccountBalance> balances,
    required List<ReceivableAssetEntity> receivableAssets,
    required List<ReceivableAssetEntity> archivedReceivables,
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
        ? const <_AccountBalance>[]
        : [
            for (final group in _groupBalances(currentBalances
                .where((item) => item.balance == Decimal.zero)
                .toList()))
              ...group.items,
          ];
    final nonZeroBalances = showArchived
        ? currentBalances
        : currentBalances.where((item) => item.balance != Decimal.zero).toList();
    final groups = _groupBalances(nonZeroBalances);
    final hasArchiveLink = !showArchived && archivedCount > 0;
    final isEmpty = groups.isEmpty &&
        currentReceivables.isEmpty &&
        zeroItems.isEmpty &&
        !hasArchiveLink;

    return Column(
      key: const Key('asset-funds'),
      children: [
        Expanded(
          child: isEmpty
              ? const _AssetEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (showArchived) ...[
                      _FundsArchiveBackRow(
                        onTap: () => setState(() =>
                            _fundsVisibility = _AssetListVisibility.active),
                      ),
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
                      _AccountGroupCard(
                        group: group,
                        onTap: (account) =>
                            _showAccountDetail(context, account),
                      ),
                    ],
                    if (zeroItems.isNotEmpty) ...[
                      if (groups.isNotEmpty || currentReceivables.isNotEmpty)
                        const SizedBox(height: 12),
                      _ZeroBalanceAccountsCard(
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
                      _FundsArchiveEntryRow(
                        count: archivedCount,
                        onTap: () => setState(() => _fundsVisibility =
                            _AssetListVisibility.archived),
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

  List<_AccountGroup> _groupBalances(List<_AccountBalance> balances) {
    final groups = <_AccountGroup>[];
    for (final type in AccountType.values) {
      final items =
          balances.where((item) => item.account.type == type).toList();
      if (items.isEmpty) continue;
      items.sort((a, b) {
        final sort = a.account.sortOrder.compareTo(b.account.sortOrder);
        if (sort != 0) return sort;
        return a.account.name.compareTo(b.account.name);
      });
      groups.add(_AccountGroup(type: type, items: items));
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
      child: const _AccountFormSheet(),
    );
  }

  void _showAddReceivableSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: const ReceivableAssetFormSheet(),
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
        builder: (_) => _AccountDetailPage(account: account),
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

class _AssetEmptyState extends StatelessWidget {
  const _AssetEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Mascot(mood: MascotMood.empty, size: 96));
  }
}

class _AssetPendingItem {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _AssetPendingItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });
}

class _AssetPendingCard extends StatelessWidget {
  final List<_AssetPendingItem> items;

  const _AssetPendingCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Text('待处理', style: AppType.sectionLabel(scheme)),
        ),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final item in items)
              SettingsRow(
                leading: Icon(item.icon),
                title: item.text,
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTextColor.secondary(scheme),
                ),
                onTap: item.onTap,
              ),
          ],
        ),
      ],
    );
  }
}

class _VerifiedNetWorthCard extends StatelessWidget {
  final List<NetWorthVerifiedCheckpoint> checkpoints;
  final NetWorthVerifiedCheckpointComparison? comparison;

  const _VerifiedNetWorthCard({
    required this.checkpoints,
    required this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ordered = checkpoints
        .where((checkpoint) =>
            checkpoint.header.status == NetWorthVerifiedCheckpointStatus.active)
        .toList()
      ..sort((left, right) => right.header.asOf.compareTo(left.header.asOf));
    final latest = ordered.firstOrNull;
    // 核对入口在右上 ⋯ 菜单；没有任何核对记录时整卡不渲染。
    if (latest == null) return const SizedBox.shrink();
    final change = comparison?.later.header.id == latest.header.id
        ? comparison?.change
        : null;
    final latestDate = latest.header.asOf.toLocal();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('净资产核对', style: AppType.rowTitle(scheme)),
          const SizedBox(height: 4),
          ...[
            Text(
              '${latest.header.completeness == NetWorthVerifiedCheckpointCompleteness.complete ? '完整核对' : '部分核对'}'
              ' · ${latestDate.year}/${latestDate.month}/${latestDate.day} '
              '${latestDate.hour.toString().padLeft(2, '0')}:'
              '${latestDate.minute.toString().padLeft(2, '0')}',
              style: AppType.secondary(scheme),
            ),
            const SizedBox(height: 8),
            Text(
              MoneyFormat.string(
                budgetDecimalFromCents(
                  latest.header.totals.netWorthMinor,
                )!,
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (change != null) ...[
              const SizedBox(height: 4),
              Text(
                '较上次完整核对 '
                '${change.netWorthDeltaMinor >= 0 ? '+' : '-'}'
                '${MoneyFormat.string(budgetDecimalFromCents(change.netWorthDeltaMinor.abs())!)}',
                style: AppType.secondary(scheme).copyWith(fontFamily: 'Nunito'),
              ),
            ] else if (latest.header.completeness ==
                NetWorthVerifiedCheckpointCompleteness.partial) ...[
              const SizedBox(height: 4),
              Text(
                latest.header.incompletenessReasons.first.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption(scheme),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text('再完成一次完整核对后显示变化。', style: AppType.caption(scheme)),
            ],
          ],
        ],
      ),
    );
  }
}

class _AccountBalance {
  final AccountEntity account;
  final Decimal balance;
  final String? qualityText;

  const _AccountBalance({
    required this.account,
    required this.balance,
    this.qualityText,
  });
}

class _AccountGroup {
  final AccountType type;
  final List<_AccountBalance> items;

  const _AccountGroup({
    required this.type,
    required this.items,
  });
}

class _AssetSummaryCard extends StatelessWidget {
  final Decimal netWorth;
  final Decimal fundsAssets;
  final Decimal physicalAssets;
  final Decimal fundsNetWorth;
  final Decimal liabilityTotal;
  final Decimal totalAssets;
  final int includedCount;
  final int accountCount;
  final bool partial;

  /// true = 嵌入外层合并卡（不画自己的卡片装饰）。
  final bool embedded;

  const _AssetSummaryCard({
    required this.netWorth,
    required this.fundsAssets,
    required this.physicalAssets,
    required this.fundsNetWorth,
    required this.liabilityTotal,
    required this.totalAssets,
    required this.includedCount,
    required this.accountCount,
    required this.partial,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = netWorth < Decimal.zero;
    final heroText = MoneyFormat.string(netWorth);
    final heroStyle = TextStyle(
      fontFamily: 'Nunito',
      fontSize: 34,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: negative ? AppColors.warning : scheme.onSurface,
    );
    final excludedCount = accountCount - includedCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: embedded ? null : appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '净资产',
            style: AppType.secondary(scheme),
          ),
          const SizedBox(height: 6),
          Text(
            // ¥ 符号与数字同色（用户 2026-07-26 拍板：铜金 ¥ 突兀）；负数整体超支橙。
            heroText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: heroStyle,
          ),
          if (partial) ...[
            const SizedBox(height: 4),
            Text('部分金额待确认', style: AppType.caption(scheme)),
          ],
          if (excludedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$excludedCount 项未计入净资产',
              style: AppType.caption(scheme),
            ),
          ],
          const SizedBox(height: 13),
          _AssetMetricPair(
            left: _AssetMetric(
              label: '资金资产',
              value: fundsAssets,
              color: scheme.onSurface,
            ),
            right: _AssetMetric(
              label: '计入物品',
              value: physicalAssets,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _AssetMetricPair(
            left: _AssetMetric(
              label: '资金净值',
              value: fundsNetWorth,
              color: fundsNetWorth < Decimal.zero
                  ? AppColors.warning
                  : scheme.onSurface,
            ),
            right: _AssetMetric(
              label: '总负债',
              value: liabilityTotal,
              color: liabilityTotal > Decimal.zero
                  ? AppColors.warning
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _AssetMetricPair(
            left: _AssetMetric(
              label: '总资产',
              value: totalAssets,
              color: scheme.onSurface,
            ),
            right: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AssetMetricPair extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _AssetMetricPair({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _AssetMetric extends StatelessWidget {
  final String label;
  final Decimal value;
  final Color color;

  const _AssetMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 次级指标降两级：13px 最弱灰标签 + 15px Nunito 数值（紧凑两列网格）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppTextColor.hint(scheme),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          MoneyFormat.string(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _AssetAnalysisCard extends StatelessWidget {
  final NetWorthBreakdown breakdown;

  const _AssetAnalysisCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liabilityRate = breakdown.totalAssets <= Decimal.zero
        ? null
        : breakdown.totalLiabilities.toDouble() /
            breakdown.totalAssets.toDouble();
    final items = [
      ('流动资金', breakdown.cashAssets, Icons.account_balance_wallet_outlined),
      ('投资余额', breakdown.investmentAssets, Icons.trending_up),
      ('权益资产', breakdown.receivableAssets, Icons.assignment_return_outlined),
      ('计入的物品', breakdown.physicalAssets, Icons.inventory_2_outlined),
    ].where((item) => item.$2 > Decimal.zero).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 「生成报告」入口在右上 ⋯ 菜单。
          Text(
            '资产结构',
            style: AppType.rowTitle(scheme),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              '暂无可分析的资产数据',
              style: AppType.secondary(scheme),
            )
          else
            for (final item in items) ...[
              _AssetStructureRow(
                label: item.$1,
                value: item.$2,
                total: breakdown.totalAssets,
                icon: item.$3,
              ),
              const SizedBox(height: 8),
            ],
          Text(
            liabilityRate == null
                ? '负债率：暂无资产数据'
                : '负债率：${(liabilityRate * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTextColor.secondary(scheme),
                  fontWeight: FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}

class _AssetStructureRow extends StatelessWidget {
  final String label;
  final Decimal value;
  final Decimal total;
  final IconData icon;

  const _AssetStructureRow({
    required this.label,
    required this.value,
    required this.total,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = total <= Decimal.zero
        ? 0.0
        : (value.toDouble() / total.toDouble()).clamp(0.0, 1.0);
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTextColor.secondary(scheme)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppType.secondary(scheme),
                    ),
                  ),
                  Text(
                    MoneyFormat.string(value),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: AppColors.iconCircleFill(scheme),
                  color: scheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountGroupCard extends StatelessWidget {
  final _AccountGroup group;
  final ValueChanged<AccountEntity> onTap;

  const _AccountGroupCard({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 组内币种不一致时不硬加，避免算出一个混币种的假小计（数据诚实性优先）。
    final currencies =
        group.items.map((item) => item.account.currencyCode).toSet();
    final showSubtotal = currencies.length == 1;
    final subtotal = group.items
        .fold<Decimal>(Decimal.zero, (sum, item) => sum + item.balance);
    final subtotalStyle = AppType.secondary(scheme).copyWith(
      color: subtotal < Decimal.zero ? AppColors.warning : null,
    );
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  group.type.label,
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(width: 6),
                Text(
                  '${group.items.length} 个账户',
                  style: AppType.caption(scheme),
                ),
                if (showSubtotal) ...[
                  const Spacer(),
                  Text.rich(
                    digitAwareAmountSpan(
                      MoneyFormat.string(
                        subtotal,
                        currencyCode: currencies.single,
                      ),
                      subtotalStyle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          for (int i = 0; i < group.items.length; i++) ...[
            if (i > 0) appCardDivider(scheme),
            _AccountBalanceTile(
              item: group.items[i],
              onTap: () => onTap(group.items[i].account),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountBalanceTile extends StatelessWidget {
  final _AccountBalance item;
  final VoidCallback onTap;

  const _AccountBalanceTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = context
        .watch<AppRepository>()
        .liabilityProfileForAccount(item.account.id);
    final negative = item.balance < Decimal.zero;
    final muted = !item.account.includeInNetWorth;
    // 副标题减负：最多「类型 + 1 个附加段」，
    // 优先级 = 每月N日还款 > 机构 > 「待确认」 > 「不计入」。
    final extra = profile?.repaymentDay != null
        ? '每月${profile!.repaymentDay}日还款'
        : item.account.institution.isNotEmpty
            ? item.account.institution
            : item.qualityText != null
                ? '待确认'
                : !item.account.includeInNetWorth
                    ? '不计入'
                    : null;
    final subtitleText = [
      item.account.type.label,
      if (extra != null) extra,
    ].join(' · ');
    final subtitleStyle =
        (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: muted ? AppTextColor.hint(scheme) : AppTextColor.secondary(scheme),
      fontWeight: FontWeight.w400,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.iconCircleFill(scheme),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _accountIcon(item.account.type),
                size: 18,
                color: muted
                    ? AppTextColor.hint(scheme)
                    : AppTextColor.secondary(scheme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: muted
                              ? scheme.onSurface.withValues(alpha: 0.55)
                              : scheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    // Nunito 只套在数字子串上（中文混排拆 TextSpan）。
                    digitAwareAmountSpan(subtitleText, subtitleStyle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Text(
                MoneyFormat.string(
                  item.balance,
                  currencyCode: item.account.currencyCode,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w500,
                      color: muted
                          ? AppTextColor.hint(scheme)
                          : (negative ? AppColors.warning : scheme.onSurface),
                    ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppTextColor.secondary(scheme),
            ),
          ],
        ),
      ),
    );
  }

  IconData _accountIcon(AccountType type) => switch (type) {
        AccountType.cash => Icons.payments_outlined,
        AccountType.debit => Icons.credit_card,
        AccountType.credit => Icons.credit_score_outlined,
        AccountType.savings => Icons.savings_outlined,
        AccountType.investment => Icons.trending_up,
        AccountType.loan => Icons.request_quote_outlined,
        AccountType.other => Icons.account_balance_wallet_outlined,
      };
}

/// ¥0 账户折叠卡：余额为 0 的账户不再散在各分组里，统一收进这里（默认收起）。
class _ZeroBalanceAccountsCard extends StatelessWidget {
  final List<_AccountBalance> items;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<AccountEntity> onTap;

  const _ZeroBalanceAccountsCard({
    required this.items,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('zero-balance-accounts-toggle'),
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Row(
                children: [
                  Text(
                    '已清零账户 (${items.length})',
                    style: AppType.rowTitle(scheme),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppTextColor.secondary(scheme),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (int i = 0; i < items.length; i++) ...[
              appCardDivider(scheme),
              _AccountBalanceTile(
                item: items[i],
                onTap: () => onTap(items[i].account),
              ),
            ],
        ],
      ),
    );
  }
}

/// 资金页底部入口：当前项目视图下有归档账户/权益时显示，点开切到归档视图。
class _FundsArchiveEntryRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FundsArchiveEntryRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text('已归档 $count 项 ›', style: AppType.secondary(scheme)),
        ),
      ),
    );
  }
}

/// 归档视图顶部返回条，点回切回当前项目视图。
class _FundsArchiveBackRow extends StatelessWidget {
  final VoidCallback onTap;

  const _FundsArchiveBackRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('‹ 返回当前项目', style: AppType.secondary(scheme)),
      ),
    );
  }
}

class _AccountDetailPage extends StatefulWidget {
  final AccountEntity account;

  const _AccountDetailPage({required this.account});

  @override
  State<_AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<_AccountDetailPage> {
  int _trendDays = 90;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final current = repo.accounts
            .where((item) => item.id == widget.account.id && !item.isDeleted)
            .firstOrNull ??
        widget.account;
    final balanceResult = repo.accountBalanceResultOf(current);
    final balance = balanceResult.value!.balance;
    final movement = balanceResult.value!.movement;
    final activities = repo.accountActivitiesFor(current.id);
    final checkpoints = repo
        .accountBalanceCheckpointsFor(current.id)
        .where((checkpoint) => checkpoint.isAnchor)
        .take(3)
        .toList();
    final trend = repo.accountBalanceTrend(current, days: _trendDays);
    final recurringRuleCount = repo.recurringRules
        .where((rule) => rule.accountId == current.id)
        .length;
    final qualityText = movement.unknownSettlementAccountCount > 0
        ? '${movement.unknownSettlementAccountCount} 笔到账账户待确认，当前余额只能部分核对'
        : movement.unknownSettlementDateCount > 0
            ? '${movement.unknownSettlementDateCount} 笔到账日期待确认，已计入当前余额但无法精确归入历史趋势'
            : movement.assumedAccountCount > 0 ||
                    movement.assumedSettlementDateCount > 0
                ? '余额含估算的到账日期或账户'
                : balanceResult.status != MetricStatus.available
                    ? '余额仍有待确认信息，当前只能部分核对'
                    : balanceResult.value!.checkpoint != null
                        ? '已核对于 ${assetShortDateTime(balanceResult.value!.checkpoint!.effectiveMs)}'
                        : current.openingBalanceQuality ==
                                AccountOpeningBalanceQuality.exact
                            ? '从账户建立时点起可信'
                            : null;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(current.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Builder(
              builder: (menuContext) => AppCircleButton(
                icon: Icons.more_horiz,
                onPressed: () => _showMoreMenu(
                  menuContext,
                  repo,
                  current,
                  recurringRuleCount: recurringRuleCount,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: appCardDecoration(scheme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前余额', style: AppType.secondary(scheme)),
                const SizedBox(height: 6),
                Text(
                  MoneyFormat.string(
                    balance,
                    currencyCode: current.currencyCode,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        color: balance < Decimal.zero
                            ? AppColors.warning
                            : scheme.onSurface,
                      ),
                ),
                if (qualityText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    qualityText,
                    style: AppType.caption(scheme),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                leading: const Icon(Icons.fact_check_outlined),
                title: '校准余额',
                subtitle: '按现在的实际余额修正，不计入收支',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _showCalibration(context, current),
              ),
              if (!current.isArchived && recurringRuleCount > 0)
                SettingsRow(
                  leading: const Icon(Icons.schedule_outlined),
                  title: '定时记账',
                  subtitle:
                      '$recurringRuleCount 个定时记账仍使用此账户，先修改或删除相关规则',
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AccountBalanceTrendCard(
            trend: trend,
            days: _trendDays,
            onDaysChanged: (days) => setState(() => _trendDays = days),
          ),
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 12),
            AssetDetailSection(
              title: '余额核对记录',
              children: [
                for (final checkpoint in checkpoints)
                  _CheckpointRow(
                    checkpoint: checkpoint,
                    reversed: repo.isAccountBalanceCheckpointReversed(
                      checkpoint.id,
                    ),
                    onReverse: () =>
                        _reverseCheckpoint(context, repo, checkpoint),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AssetDetailSection(
            title: '账户资料',
            children: [
              AssetDetailRow(label: '类型', value: current.type.label),
              if (current.institution.isNotEmpty)
                AssetDetailRow(
                  label: '机构',
                  value: current.institution,
                ),
              AssetDetailRow(
                label: '币种',
                value: current.currencyCode == 'CNY'
                    ? '人民币'
                    : current.currencyCode,
              ),
              AssetDetailRow(
                label: '净资产',
                value: current.includeInNetWorth ? '计入净资产' : '不计入净资产',
              ),
            ],
          ),
          const SizedBox(height: 12),
          AccountActivityList(items: activities),
        ],
      ),
    );
  }

  /// 右上角 ⋯ 菜单：编辑资料、归档/恢复等动作类操作都收在这里，正文只留信息区。
  void _showMoreMenu(
    BuildContext menuContext,
    AppRepository repo,
    AccountEntity current, {
    required int recurringRuleCount,
  }) {
    showIosMenu(
      menuContext,
      [
        IosMenuItem(
          label: '编辑资料',
          icon: Icons.edit_outlined,
          onTap: () => showBlurSheet<void>(
            context,
            child: _AccountFormSheet(account: current),
          ),
        ),
        IosMenuItem(
          key: ValueKey('account-archive-action-${current.id}'),
          label: current.isArchived ? '恢复到账户列表' : '归档账户',
          icon: current.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          onTap: () => _toggleArchive(
            context,
            repo,
            current,
            recurringRuleCount: recurringRuleCount,
          ),
        ),
      ],
    );
  }

  Future<void> _showCalibration(
    BuildContext context,
    AccountEntity account,
  ) async {
    await showBlurSheet<void>(
      context,
      child: _AccountBalanceCalibrationSheet(account: account),
    );
  }

  Future<void> _toggleArchive(
      BuildContext context, AppRepository repo, AccountEntity account,
      {required int recurringRuleCount}) async {
    if (account.isArchived) {
      await repo.restoreArchivedAccount(account.id);
      if (!context.mounted) return;
      showAppToast(context, '已恢复「${account.name}」');
      Navigator.pop(context);
      return;
    }
    if (recurringRuleCount > 0) {
      showAppToast(context, '请先修改或删除使用此账户的定时记账');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '归档账户',
      message: '归档只会把「${account.name}」移出默认列表，余额、历史记录和净资产合计都不会改变。',
      confirmText: '归档',
    );
    if (!confirmed) return;
    try {
      await repo.archiveAccount(account.id);
    } on StateError {
      if (context.mounted) {
        showAppToast(context, '账户状态刚刚变化，请先检查相关定时记账');
      }
      return;
    }
    if (!context.mounted) return;
    showAppToast(context, '已归档「${account.name}」');
    Navigator.pop(context);
  }

  Future<void> _reverseCheckpoint(
    BuildContext context,
    AppRepository repo,
    AccountBalanceCheckpointEntity checkpoint,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销这次余额校准？',
      message: '撤销后会回到上一条有效校准并重新计算，不会写一笔反向收支。',
      confirmText: '撤销',
    );
    if (!confirmed) return;
    await repo.reverseAccountBalanceCheckpoint(checkpoint.id);
    if (context.mounted) showAppToast(context, '已撤销余额校准');
  }
}

class _CheckpointRow extends StatelessWidget {
  final AccountBalanceCheckpointEntity checkpoint;
  final bool reversed;
  final VoidCallback onReverse;

  const _CheckpointRow({
    required this.checkpoint,
    required this.reversed,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyFormat.string(checkpoint.targetBalance),
                  style:
                      AppType.rowTitle(scheme).copyWith(fontFamily: 'Nunito'),
                ),
                const SizedBox(height: 2),
                Text(
                  '${assetShortDateTime(checkpoint.effectiveMs)} · '
                  '保存时差额 ${MoneyFormat.string(checkpoint.deltaAtCreation)}',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
          reversed
              ? Text('已撤销', style: AppType.caption(scheme))
              : AppPillButton(label: '撤销', onPressed: onReverse),
        ],
      ),
    );
  }
}

class _AccountBalanceCalibrationSheet extends StatefulWidget {
  final AccountEntity account;

  const _AccountBalanceCalibrationSheet({required this.account});

  @override
  State<_AccountBalanceCalibrationSheet> createState() =>
      _AccountBalanceCalibrationSheetState();
}

class _AccountBalanceCalibrationSheetState
    extends State<_AccountBalanceCalibrationSheet> {
  late final TextEditingController _targetController;
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _targetController = TextEditingController(
      text: repo.accountBalanceOf(widget.account).toString(),
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Decimal? get _target => Decimal.tryParse(_targetController.text.trim());

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final calculated = repo.accountBalanceOf(widget.account);
    final target = _target;
    final difference = target == null ? null : target - calculated;
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '校准余额',
            subtitle: widget.account.name,
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: target == null || _saving ? null : _save,
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                AssetDetailSection(
                  title: '本次核对',
                  children: [
                    AssetDetailRow(
                      label: '系统计算余额',
                      value: MoneyFormat.string(calculated),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: AppLabeledField(
                        label: '实际余额',
                        child: TextField(
                          controller: _targetController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          inputFormatters:
                              moneyInputFormatters(allowNegative: true),
                          decoration:
                              iosInputDecoration(context, hint: '例如 1234.56'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    AssetDetailRow(
                      label: '差额',
                      value: difference == null
                          ? '待输入'
                          : MoneyFormat.string(difference),
                    ),
                    AssetDetailRow(
                      label: '核对时点',
                      value: '现在 · ${now.year}/${now.month}/${now.day} '
                          '${now.hour.toString().padLeft(2, '0')}:'
                          '${now.minute.toString().padLeft(2, '0')}',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: AppLabeledField(
                        label: '说明（可选）',
                        child: TextField(
                          controller: _noteController,
                          minLines: 2,
                          maxLines: 3,
                          decoration:
                              iosInputDecoration(context, hint: '例如 微信实际余额'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '以本次填写的实际余额为准，之前的差额会自动修正，不会生成收入、支出或现金流。',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final target = _target;
    if (target == null || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().createAccountBalanceCheckpoint(
            accountId: widget.account.id,
            targetBalance: target,
            note: _noteController.text,
          );
      if (!mounted) return;
      showAppToast(context, '余额已核对');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AccountBalanceTrendCard extends StatelessWidget {
  final AccountBalanceTrendValue? trend;
  final int days;
  final ValueChanged<int> onDaysChanged;

  const _AccountBalanceTrendCard({
    required this.trend,
    required this.days,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final segment = SizedBox(
                width: compact ? constraints.maxWidth : 180,
                child: SlidingSegment<int>(
                  items: const [(30, '1月'), (90, '3月'), (365, '1年')],
                  value: days,
                  onChanged: onDaysChanged,
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('余额趋势', style: AppType.rowTitle(scheme)),
                    const SizedBox(height: 8),
                    segment,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text('余额趋势', style: AppType.rowTitle(scheme)),
                  ),
                  segment,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (trend == null)
            Text('历史起点待确认，完成一次余额校准后显示趋势。',
                style: AppType.secondary(scheme))
          else if (!trend!.hasTrend)
            Text('已建立可信起点，积累更多结算活动后显示趋势。', style: AppType.secondary(scheme))
          else ...[
            SizedBox(
              height: 112,
              width: double.infinity,
              child: CustomPaint(
                painter: _AccountBalanceTrendPainter(
                  points: trend!.points,
                  color: scheme.primary,
                  gridColor: AppColors.hairline(scheme),
                ),
              ),
            ),
            if (trend!.points.any((point) => !point.trusted)) ...[
              const SizedBox(height: 6),
              Text('待确认到账信息所在区间不会连成可信趋势。', style: AppType.caption(scheme)),
            ],
          ],
        ],
      ),
    );
  }
}

class _AccountBalanceTrendPainter extends CustomPainter {
  final List<AccountBalanceTrendPoint> points;
  final Color color;
  final Color gridColor;

  const _AccountBalanceTrendPainter({
    required this.points,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final values = points.map((point) => point.balance.toDouble()).toList();
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    if (minimum == maximum) {
      minimum -= 1;
      maximum += 1;
    }
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var row = 1; row <= 2; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    Offset offset(int index) {
      final x = size.width * index / (points.length - 1);
      final ratio = (values[index] - minimum) / (maximum - minimum);
      return Offset(x, size.height - ratio * size.height);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    Path? path;
    for (var index = 0; index < points.length; index++) {
      if (!points[index].trusted) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      final current = offset(index);
      if (path == null) {
        path = Path()..moveTo(current.dx, current.dy);
      } else {
        path.lineTo(current.dx, current.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AccountBalanceTrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}

class _AccountFormSheet extends StatefulWidget {
  final AccountEntity? account;

  const _AccountFormSheet({this.account});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _institutionCtrl;
  late final TextEditingController _liabilityOriginalCtrl;
  late final TextEditingController _liabilityPrincipalCtrl;
  late final TextEditingController _liabilityRateCtrl;
  late final TextEditingController _repaymentDayCtrl;
  late final TextEditingController _liabilityNoteCtrl;
  late AccountType _type;
  late bool _includeInNetWorth;
  bool _saving = false;
  late LiabilityProfileType _liabilityType;
  late LiabilityProfileStatus _liabilityStatus;
  int? _repaymentAccountId;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameCtrl = TextEditingController(text: account?.name ?? '');
    _currencyCtrl = TextEditingController(text: account?.currencyCode ?? 'CNY');
    _openingCtrl =
        TextEditingController(text: account?.openingBalance.toString() ?? '');
    _institutionCtrl = TextEditingController(text: account?.institution ?? '');
    _type = account?.type ?? AccountType.cash;
    _includeInNetWorth = account?.includeInNetWorth ?? true;
    final profile = account == null
        ? null
        : context.read<AppRepository>().liabilityProfileForAccount(account.id);
    _liabilityOriginalCtrl =
        TextEditingController(text: profile?.originalAmount.toString() ?? '');
    _liabilityPrincipalCtrl =
        TextEditingController(text: profile?.currentPrincipal.toString() ?? '');
    _liabilityRateCtrl =
        TextEditingController(text: profile?.interestRate.toString() ?? '');
    _repaymentDayCtrl =
        TextEditingController(text: profile?.repaymentDay?.toString() ?? '');
    _liabilityNoteCtrl = TextEditingController(text: profile?.note ?? '');
    _liabilityType = profile?.type ??
        (_type == AccountType.credit
            ? LiabilityProfileType.creditCard
            : LiabilityProfileType.other);
    _liabilityStatus = profile?.status ?? LiabilityProfileStatus.active;
    _repaymentAccountId = profile?.repaymentAccountId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    _openingCtrl.dispose();
    _institutionCtrl.dispose();
    _liabilityOriginalCtrl.dispose();
    _liabilityPrincipalCtrl.dispose();
    _liabilityRateCtrl.dispose();
    _repaymentDayCtrl.dispose();
    _liabilityNoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final valid = _nameCtrl.text.trim().isNotEmpty &&
        _openingBalanceInputValid &&
        _liabilityInputValid;
    final screenH = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: _editing ? '编辑账户' : '新增账户',
              onClose: () => Navigator.pop(context),
              actionLabel: '保存',
              onAction: valid ? _save : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppLabeledField(
                      label: '账户名称',
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            iosInputDecoration(context, hint: '例如 招行储蓄卡'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '账户类型',
                      child: _AccountTypePicker(
                        value: _type,
                        onChanged: (next) => setState(() {
                          _type = next;
                          if (next == AccountType.credit) {
                            _liabilityType = LiabilityProfileType.creditCard;
                          } else if (next == AccountType.loan &&
                              _liabilityType ==
                                  LiabilityProfileType.creditCard) {
                            _liabilityType = LiabilityProfileType.other;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '币种',
                      child: AppReadOnlyField(
                        text: _currencyCtrl.text == 'CNY'
                            ? '人民币'
                            : '${_currencyCtrl.text}（仅保留，不计入净资产）',
                        icon: Icons.currency_yuan,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: _type.liability ? '当前欠款' : '期初余额',
                      helperText: _editing
                          ? '期初余额用于建立账户起点，修改当前余额请在账户详情选择“校准余额”。'
                          : null,
                      child: TextField(
                        controller: _openingCtrl,
                        readOnly: _editing,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters:
                            moneyInputFormatters(allowNegative: true),
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: _type.liability ? '例如 -3000（可填负数）' : '例如 1000',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '机构/银行（可选）',
                      child: TextField(
                        controller: _institutionCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            iosInputDecoration(context, hint: '例如 招商银行'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          title: '计入净资产',
                          subtitle: '关闭后仍显示账户，但不计入顶部合计',
                          trailing: AppSwitch(
                            value: _includeInNetWorth,
                            onChanged: (value) =>
                                setState(() => _includeInNetWorth = value),
                          ),
                        ),
                      ],
                    ),
                    if (_type.liability) ...[
                      const SizedBox(height: 14),
                      AssetDetailSection(
                        title: '负债详情',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppLabeledField(
                                  label: '负债类型',
                                  child: AssetEnumDropdown<LiabilityProfileType>(
                                    value: _liabilityType,
                                    values: LiabilityProfileType.values,
                                    labelOf: (value) => value.label,
                                    hint: '选择类型',
                                    onChanged: (value) =>
                                        setState(() => _liabilityType = value),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '原始金额（可选）',
                                  child: TextField(
                                    controller: _liabilityOriginalCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: moneyInputFormatters(),
                                    decoration: iosInputDecoration(
                                      context,
                                      prefix: '¥ ',
                                      hint: '例如 12000',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '剩余本金/当前欠款（可选）',
                                  child: TextField(
                                    controller: _liabilityPrincipalCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: moneyInputFormatters(
                                        allowNegative: true),
                                    decoration: iosInputDecoration(
                                      context,
                                      prefix: '¥ ',
                                      hint: '例如 8000',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '年化利率 %（可选）',
                                  child: TextField(
                                    controller: _liabilityRateCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: iosInputDecoration(
                                      context,
                                      hint: '例如 3.5',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '每月还款日（可选）',
                                  child: TextField(
                                    controller: _repaymentDayCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: iosInputDecoration(
                                      context,
                                      hint: '1-31，例如 9',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '默认还款账户（可选）',
                                  child: AssetAccountDropdown(
                                    value: _repaymentAccountId,
                                    accounts: repo.accounts
                                        .where(
                                            (a) => a.id != widget.account?.id)
                                        .toList(),
                                    hint: '选择账户',
                                    onChanged: (value) => setState(
                                        () => _repaymentAccountId = value),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '负债状态',
                                  child: AssetEnumDropdown<LiabilityProfileStatus>(
                                    value: _liabilityStatus,
                                    values: LiabilityProfileStatus.values,
                                    labelOf: (value) => value.label,
                                    hint: '选择状态',
                                    onChanged: (value) => setState(
                                        () => _liabilityStatus = value),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '负债备注（可选）',
                                  child: TextField(
                                    controller: _liabilityNoteCtrl,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: iosInputDecoration(context,
                                        hint: '例如 房贷、分期说明'),
                                  ),
                                ),
                                if (!_liabilityInputValid) ...[
                                  const SizedBox(height: 10),
                                  const AssetHintBox(
                                    text: '负债金额和利率不能为负；还款日必须在 1 到 31 之间。',
                                  ),
                                ],
                              ],
                            ),
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
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final opening = _parseDecimal(_openingCtrl.text);
      final currency = _currencyCtrl.text.trim().toUpperCase();
      final repo = context.read<AppRepository>();
      late int accountId;
      if (_editing) {
        accountId = widget.account!.id;
        await repo.updateAccount(
          id: accountId,
          name: _nameCtrl.text.trim(),
          currencyCode: currency.isEmpty ? 'CNY' : currency,
          type: _type,
          openingBalance: opening,
          includeInNetWorth: _includeInNetWorth,
          institution: _institutionCtrl.text.trim(),
        );
      } else {
        accountId = await repo.addAccount(
          name: _nameCtrl.text.trim(),
          currencyCode: currency.isEmpty ? 'CNY' : currency,
          type: _type,
          openingBalance: opening,
          includeInNetWorth: _includeInNetWorth,
          institution: _institutionCtrl.text.trim(),
        );
      }
      await _saveLiabilityProfile(repo, accountId);
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveLiabilityProfile(AppRepository repo, int accountId) async {
    if (!_type.liability) {
      await repo.deleteLiabilityProfileForAccount(accountId);
      return;
    }
    final hasAny = [
      _liabilityOriginalCtrl.text,
      _liabilityPrincipalCtrl.text,
      _liabilityRateCtrl.text,
      _repaymentDayCtrl.text,
      _liabilityNoteCtrl.text,
    ].any((text) => text.trim().isNotEmpty);
    if (!hasAny) return;
    await repo.upsertLiabilityProfile(
      accountId: accountId,
      type: _liabilityType,
      originalAmount: _parseDecimal(_liabilityOriginalCtrl.text),
      currentPrincipal: _parseDecimal(_liabilityPrincipalCtrl.text),
      interestRate: _parseDecimal(_liabilityRateCtrl.text),
      repaymentDay: int.tryParse(_repaymentDayCtrl.text.trim()),
      repaymentAccountId: _repaymentAccountId,
      status: _liabilityStatus,
      note: _liabilityNoteCtrl.text,
    );
  }

  Decimal _parseDecimal(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    if (normalized.isEmpty) return Decimal.zero;
    return Decimal.tryParse(normalized) ?? Decimal.zero;
  }

  bool get _openingBalanceInputValid {
    final normalized = _openingCtrl.text.trim().replaceAll(',', '');
    return normalized.isEmpty || Decimal.tryParse(normalized) != null;
  }

  bool get _liabilityInputValid {
    if (!_type.liability) return true;
    final fields = [
      _liabilityOriginalCtrl.text,
      _liabilityPrincipalCtrl.text,
      _liabilityRateCtrl.text,
    ];
    for (final field in fields) {
      final normalized = field.trim().replaceAll(',', '');
      if (normalized.isEmpty) continue;
      final value = Decimal.tryParse(normalized);
      if (value == null || value < Decimal.zero) return false;
    }
    final dayText = _repaymentDayCtrl.text.trim();
    if (dayText.isEmpty) return true;
    final day = int.tryParse(dayText);
    return day != null && day >= 1 && day <= 31;
  }
}

class _AccountTypePicker extends StatelessWidget {
  final AccountType value;
  final ValueChanged<AccountType> onChanged;

  const _AccountTypePicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in AccountType.values)
          _TypeChip(
            type: type,
            selected: value == type,
            onTap: () => onChanged(type),
          ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 选中态走主色（UI 标准：强调/选中 = scheme.primary）+ 按压反馈。
    return PressableScale(
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : AppColors.hairline(scheme),
          ),
        ),
        child: Text(
          type.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: selected
                    ? scheme.primary
                    : AppTextColor.secondary(scheme),
              ),
        ),
      ),
    );
  }
}

