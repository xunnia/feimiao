import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_allocation.dart';
import '../../core/assets/asset_enhancements.dart';
import '../../core/assets/asset_media_store.dart';
import '../../core/assets/asset_metrics.dart';
import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/transaction_actions.dart';
import '../assets/account_activity_list.dart';
import '../assets/net_worth_trend_card.dart';
import '../assets/physical_asset_cost_link_sheet.dart';
import '../assets/physical_asset_grid.dart';
import '../assets/physical_asset_purchase_sheet.dart';
import '../assets/physical_asset_refund_allocation_sheet.dart';
import '../common/app_sheet.dart';
import '../../widgets/sliding_segment.dart';

enum _AssetView { overview, funds, items }

enum _FundsKind { all, accounts, investment, receivable, liabilities }

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
  _FundsKind _fundsKind = _FundsKind.all;
  _AssetListVisibility _fundsVisibility = _AssetListVisibility.active;
  _AssetListVisibility _itemsVisibility = _AssetListVisibility.active;
  _ItemKind _itemKind = _ItemKind.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('资产管理'),
        centerTitle: true,
        actions: [
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
                        ? '含历史推定数据'
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
          final unsupportedCurrencies =
              repo.unsupportedNetWorthCurrencyCodes.toList()..sort();
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
                      archivedAssets: archivedAssets,
                      receivableAssets: receivableAssets,
                      archivedReceivables: archivedReceivables,
                      unsupportedCurrencies: unsupportedCurrencies,
                      accountQualityIssueCount: includedBalances
                          .where((item) => item.qualityText != null)
                          .length,
                      netWorthPartial:
                          netWorthResult.status != MetricStatus.available,
                      includedCount: includedCount,
                      totalCount: totalCount,
                    ),
                  _AssetView.funds => _buildFunds(
                      context,
                      repo,
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
    required List<PhysicalAssetEntity> archivedAssets,
    required List<ReceivableAssetEntity> receivableAssets,
    required List<ReceivableAssetEntity> archivedReceivables,
    required List<String> unsupportedCurrencies,
    required int accountQualityIssueCount,
    required bool netWorthPartial,
    required int includedCount,
    required int totalCount,
  }) {
    final allPhysical = [...physicalAssets, ...archivedAssets];
    final allReceivables = [...receivableAssets, ...archivedReceivables];
    final physicalReviewCount = allPhysical
        .where((a) => a.inclusionQuality == AssetInclusionQuality.needsReview)
        .length;
    final receivableReviewCount = allReceivables
        .where((a) => a.inclusionQuality == AssetInclusionQuality.needsReview)
        .length;
    final missingPurchaseDateCount = physicalAssets
        .where((a) =>
            a.economicStatus == PhysicalAssetEconomicStatus.owned &&
            a.purchaseDate == null)
        .length;
    final warrantyReminderCount = physicalAssets
        .where((asset) => repo.warrantyReminderForAsset(asset).needsAttention)
        .length;
    final receivableDueReminderCount = receivableAssets
        .where((asset) => repo.dueReminderForReceivable(asset).needsAttention)
        .length;
    final pending = <_AssetPendingItem>[
      if (accountQualityIssueCount > 0)
        _AssetPendingItem(
          icon: Icons.account_balance_wallet_outlined,
          text: '$accountQualityIssueCount 个账户含待确认或历史推定的到账信息',
          onTap: () => setState(() => _view = _AssetView.funds),
        ),
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
            _fundsKind = _FundsKind.receivable;
          }),
        ),
      if (physicalReviewCount > 0)
        _AssetPendingItem(
          icon: Icons.fact_check_outlined,
          text: '$physicalReviewCount 件历史物品的状态与计入口径待确认',
          onTap: () => setState(() {
            _view = _AssetView.items;
            _itemsVisibility = _AssetListVisibility.archived;
            _itemKind = _ItemKind.all;
          }),
        ),
      if (receivableReviewCount > 0)
        _AssetPendingItem(
          icon: Icons.assignment_late_outlined,
          text: '$receivableReviewCount 项历史权益的状态与计入口径待确认',
          onTap: () => setState(() {
            _view = _AssetView.funds;
            _fundsVisibility = _AssetListVisibility.archived;
            _fundsKind = _FundsKind.receivable;
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
    final fundsAssets = breakdown.cashAssets +
        breakdown.investmentAssets +
        breakdown.receivableAssets;
    final fundsNetWorth = fundsAssets - breakdown.totalLiabilities;

    return ListView(
      key: const Key('asset-overview'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
        ),
        if (unsupportedCurrencies.isNotEmpty) ...[
          const SizedBox(height: 10),
          _HintBox(
            text: '当前为人民币口径，未含 ${unsupportedCurrencies.join('、')} 外币资产或负债。',
          ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AssetPendingCard(items: pending.take(3).toList()),
        ],
        const SizedBox(height: 12),
        NetWorthEstimatedTrendCard(trend: repo.netWorthEstimatedTrend),
        const SizedBox(height: 12),
        _VerifiedNetWorthCard(
          checkpoints: repo.verifiedNetWorthCheckpoints,
          comparison: repo.latestVerifiedNetWorthComparison,
          onVerify: () async {
            final staleCount = repo.stalePhysicalValuationCount();
            final confirmed = await showConfirmDialog(
              context,
              title: '核对当前净资产',
              message: staleCount > 0
                  ? '有 $staleCount 件物品使用超过 90 天的最近估值。继续表示你接受这些估值日期；其他数据缺口仍只会保存为“部分核对”。'
                  : '将冻结当前所有计入对象的余额和估值证据。数据仍有缺口时会保存为“部分核对”，不会冒充完整确认。',
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
          },
        ),
        const SizedBox(height: 12),
        _AssetAnalysisCard(
          breakdown: breakdown,
          onReport: () async {
            await repo.createAssetReport();
            if (context.mounted) {
              showAppToast(context, '已生成当前资产分析报告');
            }
          },
        ),
      ],
    );
  }

  Widget _buildFunds(
    BuildContext context,
    AppRepository repo, {
    required List<_AccountBalance> balances,
    required List<ReceivableAssetEntity> receivableAssets,
    required List<ReceivableAssetEntity> archivedReceivables,
  }) {
    final showAccounts = _fundsKind != _FundsKind.receivable;
    final sourceBalances = _fundsVisibility == _AssetListVisibility.archived
        ? balances.where((item) => item.account.isArchived)
        : balances.where((item) => !item.account.isArchived);
    final filteredBalances = showAccounts
        ? sourceBalances.where((item) {
            final account = item.account;
            final profile = repo.liabilityProfileForAccount(account.id);
            final isLiability = item.balance < Decimal.zero ||
                account.type == AccountType.credit ||
                account.type == AccountType.loan ||
                profile != null;
            return switch (_fundsKind) {
              _FundsKind.all => true,
              _FundsKind.accounts =>
                account.type != AccountType.investment && !isLiability,
              _FundsKind.investment => account.type == AccountType.investment,
              _FundsKind.receivable => false,
              _FundsKind.liabilities => isLiability,
            };
          }).toList()
        : <_AccountBalance>[];
    final sourceReceivables = _fundsVisibility == _AssetListVisibility.archived
        ? archivedReceivables
        : receivableAssets;
    final filteredReceivables =
        (_fundsKind == _FundsKind.all || _fundsKind == _FundsKind.receivable)
            ? sourceReceivables
            : <ReceivableAssetEntity>[];
    final groups = _groupBalances(filteredBalances);
    final isEmpty = groups.isEmpty && filteredReceivables.isEmpty;

    return Column(
      key: const Key('asset-funds'),
      children: [
        _AssetFilterBar(
          first: _MenuFilterButton<_FundsKind>(
            value: _fundsKind,
            values: _FundsKind.values,
            labelOf: _fundsKindLabel,
            iconOf: _fundsKindIcon,
            onChanged: (value) => setState(() => _fundsKind = value),
          ),
          second: _MenuFilterButton<_AssetListVisibility>(
            value: _fundsVisibility,
            values: _AssetListVisibility.values,
            labelOf: _visibilityLabel,
            iconOf: (value) => value == _AssetListVisibility.active
                ? Icons.visibility_outlined
                : Icons.archive_outlined,
            onChanged: (value) => setState(() => _fundsVisibility = value),
          ),
        ),
        Expanded(
          child: isEmpty
              ? const _AssetEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
                  children: [
                    if (filteredReceivables.isNotEmpty)
                      _ReceivableAssetGroupCard(
                        assets: filteredReceivables,
                        onTap: (asset) => _showReceivableDetail(context, asset),
                      ),
                    for (final group in groups) ...[
                      if (filteredReceivables.isNotEmpty ||
                          group != groups.first)
                        const SizedBox(height: 12),
                      _AccountGroupCard(
                        group: group,
                        onTap: (account) =>
                            _showAccountDetail(context, account),
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
    final source = _itemsVisibility == _AssetListVisibility.archived
        ? archivedAssets
        : physicalAssets;
    final filtered = source.where((asset) {
      final owned = asset.economicStatus == PhysicalAssetEconomicStatus.owned;
      return switch (_itemKind) {
        _ItemKind.all => true,
        _ItemKind.active =>
          owned && asset.usageStatus == PhysicalAssetUsageStatus.active,
        _ItemKind.idle =>
          owned && asset.usageStatus == PhysicalAssetUsageStatus.idle,
        _ItemKind.ended => !owned,
      };
    }).toList();
    final activeCount = physicalAssets
        .where((a) =>
            a.economicStatus == PhysicalAssetEconomicStatus.owned &&
            a.usageStatus == PhysicalAssetUsageStatus.active)
        .length;
    final idleCount = physicalAssets
        .where((a) =>
            a.economicStatus == PhysicalAssetEconomicStatus.owned &&
            a.usageStatus == PhysicalAssetUsageStatus.idle)
        .length;
    final endedCount = physicalAssets
        .where((a) => a.economicStatus != PhysicalAssetEconomicStatus.owned)
        .length;

    return Column(
      key: const Key('asset-items'),
      children: [
        _ItemCountLine(
          activeCount: activeCount,
          idleCount: idleCount,
          endedCount: endedCount,
        ),
        _AssetFilterBar(
          first: _MenuFilterButton<_ItemKind>(
            value: _itemKind,
            values: _ItemKind.values,
            labelOf: _itemKindLabel,
            iconOf: _itemKindIcon,
            onChanged: (value) => setState(() => _itemKind = value),
          ),
          second: _MenuFilterButton<_AssetListVisibility>(
            value: _itemsVisibility,
            values: _AssetListVisibility.values,
            labelOf: _visibilityLabel,
            iconOf: (value) => value == _AssetListVisibility.active
                ? Icons.visibility_outlined
                : Icons.archive_outlined,
            onChanged: (value) => setState(() => _itemsVisibility = value),
          ),
        ),
        Expanded(
          child: PhysicalAssetGrid(
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

  void _showAddForCurrentView(BuildContext context) {
    switch (_view) {
      case _AssetView.overview:
        _showAddSheet(context);
      case _AssetView.funds:
        _showFundsAddSheet(context);
      case _AssetView.items:
        _showAddAssetSheet(context);
    }
  }

  void _showAddSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: _AddAssetEntrySheet(
        onAccount: () {
          Navigator.pop(context);
          _showAddAccountSheet(context);
        },
        onPhysicalAsset: () {
          Navigator.pop(context);
          _showAddAssetSheet(context);
        },
        onReceivableAsset: () {
          Navigator.pop(context);
          _showAddReceivableSheet(context);
        },
      ),
    );
  }

  void _showFundsAddSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: _AddAssetEntrySheet(
        onAccount: () {
          Navigator.pop(context);
          _showAddAccountSheet(context);
        },
        onReceivableAsset: () {
          Navigator.pop(context);
          _showAddReceivableSheet(context);
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

  void _showAddAssetSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: _AddPhysicalAssetChoiceSheet(
        onFromTransaction: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showPhysicalAssetPurchaseSheet(
              context,
              repository: context.read<AppRepository>(),
            );
          });
        },
        onNewPurchase: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showBlurSheet<void>(
              context,
              child: const _PhysicalAssetFormSheet(
                sourceType: PhysicalAssetSourceType.newPurchaseWithAccount,
              ),
            );
          });
        },
        onManual: () {
          Navigator.pop(context);
          Future.microtask(() {
            if (!context.mounted) return;
            showBlurSheet<void>(
              context,
              child: const _PhysicalAssetFormSheet(),
            );
          });
        },
      ),
    );
  }

  void _showAddReceivableSheet(BuildContext context) {
    showBlurSheet<void>(
      context,
      child: const _ReceivableAssetFormSheet(),
    );
  }

  void _showEditReceivableSheet(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: _ReceivableAssetFormSheet(asset: asset),
    );
  }

  void _showReceivableDetail(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: _ReceivableAssetDetailSheet(
        asset: asset,
        onEdit: () {
          Navigator.pop(context);
          _showEditReceivableSheet(context, asset);
        },
      ),
    );
  }

  void _showAssetDetail(BuildContext context, PhysicalAssetEntity asset) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _PhysicalAssetDetailPage(
          assetId: asset.id,
          fallbackAsset: asset,
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, AccountEntity account) {
    showBlurSheet<void>(
      context,
      child: _AccountFormSheet(account: account),
    );
  }

  void _showAccountDetail(BuildContext context, AccountEntity account) {
    showBlurSheet<void>(
      context,
      child: _AccountDetailSheet(
        account: account,
        onEdit: () {
          Navigator.pop(context);
          _showEditSheet(context, account);
        },
      ),
    );
  }
}

String _fundsKindLabel(_FundsKind value) => switch (value) {
      _FundsKind.all => '全部资金',
      _FundsKind.accounts => '账户',
      _FundsKind.investment => '投资',
      _FundsKind.receivable => '权益',
      _FundsKind.liabilities => '负债',
    };

IconData _fundsKindIcon(_FundsKind value) => switch (value) {
      _FundsKind.all => Icons.account_balance_wallet_outlined,
      _FundsKind.accounts => Icons.account_balance_outlined,
      _FundsKind.investment => Icons.trending_up,
      _FundsKind.receivable => Icons.assignment_return_outlined,
      _FundsKind.liabilities => Icons.request_quote_outlined,
    };

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

class _MenuFilterButton<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final IconData Function(T value) iconOf;
  final ValueChanged<T> onChanged;

  const _MenuFilterButton({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.iconOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (menuContext) => AppPillButton(
        label: labelOf(value),
        onPressed: () => showIosMenu(
          menuContext,
          [
            for (final item in values)
              IosMenuItem(
                label: labelOf(item),
                icon: iconOf(item),
                selected: item == value,
                onTap: () => onChanged(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetFilterBar extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _AssetFilterBar({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          first,
          const SizedBox(width: 8),
          second,
        ],
      ),
    );
  }
}

class _ItemCountLine extends StatelessWidget {
  final int activeCount;
  final int idleCount;
  final int endedCount;

  const _ItemCountLine({
    required this.activeCount,
    required this.idleCount,
    required this.endedCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '在用 $activeCount · 闲置 $idleCount · 已结束 $endedCount',
          style: AppType.secondary(scheme),
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
  final Future<void> Function() onVerify;

  const _VerifiedNetWorthCard({
    required this.checkpoints,
    required this.comparison,
    required this.onVerify,
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
    final change = comparison?.later.header.id == latest?.header.id
        ? comparison?.change
        : null;
    final latestDate = latest?.header.asOf.toLocal();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('净资产核对', style: AppType.rowTitle(scheme))),
              AppPillButton(
                  label: latest == null ? '首次核对' : '再次核对', onPressed: onVerify),
            ],
          ),
          const SizedBox(height: 4),
          if (latest == null)
            Text('还没有冻结过完整资产证据。', style: AppType.secondary(scheme))
          else ...[
            Text(
              '${latest.header.completeness == NetWorthVerifiedCheckpointCompleteness.complete ? '完整核对' : '部分核对'}'
              ' · ${latestDate!.year}/${latestDate.month}/${latestDate.day} '
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
              Text('再完成一次相同口径的完整核对后显示变化。', style: AppType.caption(scheme)),
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
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = netWorth < Decimal.zero;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            partial ? '净资产（按已知金额）' : '净资产',
            style: AppType.secondary(scheme),
          ),
          const SizedBox(height: 6),
          Text(
            MoneyFormat.string(netWorth),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                  color: negative ? AppColors.warning : scheme.onSurface,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$includedCount/$accountCount 项计入 · 全局人民币口径',
            style: AppType.caption(scheme),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppType.caption(scheme),
        ),
        const SizedBox(height: 4),
        Text(
          MoneyFormat.string(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'Nunito',
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
  final Future<void> Function() onReport;

  const _AssetAnalysisCard({
    required this.breakdown,
    required this.onReport,
  });

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
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '资产结构',
                style: AppType.rowTitle(scheme),
              ),
              const Spacer(),
              AppPillButton(
                label: '生成报告',
                onPressed: () => onReport(),
              ),
            ],
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
                  backgroundColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
              ],
            ),
          ),
          for (int i = 0; i < group.items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 62,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
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
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
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
                  Text(
                    [
                      item.account.type.label,
                      if (item.account.institution.isNotEmpty)
                        item.account.institution,
                      item.account.currencyCode,
                      if (profile != null) profile.type.label,
                      if (profile?.repaymentDay != null)
                        '每月${profile!.repaymentDay}日还款',
                      if (item.qualityText != null) item.qualityText!,
                      if (!item.account.includeInNetWorth) '不计入净资产',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: muted
                              ? AppTextColor.hint(scheme)
                              : AppTextColor.secondary(scheme),
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w400,
                        ),
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

class _AccountDetailSheet extends StatefulWidget {
  final AccountEntity account;
  final VoidCallback onEdit;

  const _AccountDetailSheet({required this.account, required this.onEdit});

  @override
  State<_AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends State<_AccountDetailSheet> {
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
                ? '余额包含历史推定的到账日期或账户'
                : balanceResult.status != MetricStatus.available
                    ? '余额仍有待确认信息，当前只能部分核对'
                    : balanceResult.value!.checkpoint != null
                        ? '已核对于 ${_shortDateTime(balanceResult.value!.checkpoint!.effectiveMs)}'
                        : current.openingBalanceQuality ==
                                AccountOpeningBalanceQuality.exact
                            ? '从账户建立时点起可信'
                            : null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: current.name,
            onClose: () => Navigator.pop(context),
            actionLabel: '编辑',
            onAction: widget.onEdit,
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(scheme),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.hairline(scheme)),
                  ),
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
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                      subtitle: '按现在的实际余额建立绝对锚点，不计入收支',
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _showCalibration(context, current),
                    ),
                    SettingsRow(
                      key: ValueKey('account-archive-action-${current.id}'),
                      leading: Icon(current.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined),
                      title: current.isArchived ? '恢复到账户列表' : '归档账户',
                      subtitle: current.isArchived
                          ? '恢复后可继续用于新记账'
                          : recurringRuleCount > 0
                              ? '$recurringRuleCount 个定时记账仍使用此账户，先修改或删除相关规则'
                              : '只移出默认列表，余额和净资产不变',
                      onTap: () => _toggleArchive(
                        context,
                        repo,
                        current,
                        recurringRuleCount: recurringRuleCount,
                      ),
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
                  _DetailSection(
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
                _DetailSection(
                  title: '账户资料',
                  children: [
                    _DetailRow(label: '类型', value: current.type.label),
                    if (current.institution.isNotEmpty)
                      _DetailRow(
                        label: '机构',
                        value: current.institution,
                      ),
                    _DetailRow(label: '币种', value: current.currencyCode),
                    _DetailRow(
                      label: '净资产',
                      value: current.includeInNetWorth ? '计入净资产' : '不计入净资产',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AccountActivityList(items: activities),
              ],
            ),
          ),
        ],
      ),
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

String _shortDateTime(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${value.month}/${value.day} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
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
                  '${_shortDateTime(checkpoint.effectiveMs)} · '
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
                _DetailSection(
                  title: '本次核对',
                  children: [
                    _DetailRow(
                      label: '系统计算余额',
                      value: MoneyFormat.string(calculated),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('实际余额', style: AppType.caption(scheme)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _targetController,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            inputFormatters:
                                moneyInputFormatters(allowNegative: true),
                            decoration:
                                iosInputDecoration(context, hint: '输入当前实际余额'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    _DetailRow(
                      label: '差额',
                      value: difference == null
                          ? '待输入'
                          : MoneyFormat.string(difference),
                    ),
                    _DetailRow(
                      label: '核对时点',
                      value: '现在 · ${now.year}/${now.month}/${now.day} '
                          '${now.hour.toString().padLeft(2, '0')}:'
                          '${now.minute.toString().padLeft(2, '0')}',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('说明（可选）', style: AppType.caption(scheme)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _noteController,
                            minLines: 2,
                            maxLines: 3,
                            decoration:
                                iosInputDecoration(context, hint: '例如：微信实际余额'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '校准会建立绝对余额锚点，不会生成收入、支出或现金流。旧到账信息只在账户已确认时由本次余额吸收。',
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
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
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
            Text('历史期初时点无法证明，完成一次余额校准后再显示可信趋势。',
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

class _AddAssetEntrySheet extends StatelessWidget {
  final VoidCallback? onAccount;
  final VoidCallback? onPhysicalAsset;
  final VoidCallback? onReceivableAsset;

  const _AddAssetEntrySheet({
    this.onAccount,
    this.onPhysicalAsset,
    this.onReceivableAsset,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '新增资产',
            onClose: () => Navigator.pop(context),
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              if (onAccount != null)
                SettingsRow(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: '新增账户',
                  subtitle: '现金、银行卡、信用卡、存款、贷款',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: onAccount,
                ),
              if (onPhysicalAsset != null)
                SettingsRow(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: '添加实物资产',
                  subtitle: '手机、电脑、车辆、房产、贵重物品',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: onPhysicalAsset,
                ),
              if (onReceivableAsset != null)
                SettingsRow(
                  leading: const Icon(Icons.assignment_return_outlined),
                  title: '添加权益资产',
                  subtitle: '押金、借出款、应收款、预付余额',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: onReceivableAsset,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddPhysicalAssetChoiceSheet extends StatelessWidget {
  final VoidCallback onFromTransaction;
  final VoidCallback onNewPurchase;
  final VoidCallback onManual;

  const _AddPhysicalAssetChoiceSheet({
    required this.onFromTransaction,
    required this.onNewPurchase,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '添加物品',
            onClose: () => Navigator.pop(context),
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              SettingsRow(
                leading: const Icon(Icons.receipt_long_outlined),
                title: '从最近账单加入',
                subtitle: '继承购买日期和账本，不会重复记支出',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: onFromTransaction,
              ),
              SettingsRow(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: '新购买，同时记账',
                subtitle: '选择付款账户，购买日同时写入物品和支出',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: onNewPurchase,
              ),
              SettingsRow(
                leading: const Icon(Icons.edit_note_outlined),
                title: '手工补录物品',
                subtitle: '适合旧物、赠品或没有购买账单的物品',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: onManual,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Kept as a short-lived rollback renderer while the photo grid is first shipped.
// ignore: unused_element
class _PhysicalAssetGroupCard extends StatelessWidget {
  final List<PhysicalAssetEntity> assets;
  final ValueChanged<PhysicalAssetEntity> onTap;

  const _PhysicalAssetGroupCard({
    required this.assets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                Text(
                  '我的物品',
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(width: 6),
                Text(
                  '${assets.length} 件',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
          for (int i = 0; i < assets.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 62,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _PhysicalAssetTile(
              asset: assets[i],
              onTap: () => onTap(assets[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhysicalAssetTile extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final VoidCallback onTap;

  const _PhysicalAssetTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final cost = repo.physicalAssetAcquisitionCost(asset.id);
    final additional = repo.physicalAssetAdditionalCost(asset.id);
    final metrics = _resolveMetrics(repo, asset, cost);
    final muted = !asset.countsInNetWorth;
    final daily = metrics.dailyHoldingCost;
    final held = metrics.heldDays;
    final dailyText = cost.isExact && additional.isExact && daily.isExact
        ? '${MoneyFormat.string(daily.value!, currencyCode: asset.currencyCode)}/天'
        : '日均不可计算';
    final heldText = held.isExact ? '已持有 ${held.value} 天' : held.reason;
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
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _assetIcon(asset.assetType),
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
                    asset.name,
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
                  Text(
                    [
                      asset.assetType.label,
                      _physicalAssetStatusLabel(asset),
                      if (asset.inclusionQuality ==
                          AssetInclusionQuality.needsReview)
                        '计入口径待确认'
                      else if (!asset.includeInNetWorth)
                        '不计入净资产',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.secondary(scheme).copyWith(
                      color: muted
                          ? AppTextColor.hint(scheme)
                          : AppTextColor.secondary(scheme),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dailyText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w500,
                          color: muted
                              ? AppTextColor.hint(scheme)
                              : scheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    heldText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption(scheme),
                  ),
                ],
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
}

PhysicalAssetMetrics _resolveMetrics(
  AppRepository repo,
  PhysicalAssetEntity asset,
  PhysicalAssetAcquisitionCostResult cost,
) {
  final additional = repo.physicalAssetAdditionalCost(asset.id);
  final usage = repo.physicalAssetUsage(asset.id);
  return resolvePhysicalAssetMetrics(
    PhysicalAssetMetricInput(
      netAcquisitionCost: cost.amount ?? Decimal.zero,
      additionalNetCost: additional.amount,
      currentNetValue: asset.currentValue,
      purchasedAt: asset.purchaseDate,
      endedAt: asset.endedAt,
      isEconomicallyOwned:
          asset.economicStatus == PhysicalAssetEconomicStatus.owned,
      hasKnownValuation: repo.valuationsForAsset(asset.id).isNotEmpty,
      hasComparableCurrency: true,
      usageTrackingEnabled: asset.usageTrackingEnabled,
      usageCount: usage.totalCount,
    ),
  );
}

String _physicalAssetStatusLabel(PhysicalAssetEntity asset) {
  return switch (asset.economicStatus) {
    PhysicalAssetEconomicStatus.owned => switch (asset.usageStatus) {
        PhysicalAssetUsageStatus.active => '在用',
        PhysicalAssetUsageStatus.idle => '闲置',
        PhysicalAssetUsageStatus.unknown => '持有中',
      },
    PhysicalAssetEconomicStatus.sold => '已出售',
    PhysicalAssetEconomicStatus.returned => '已退货',
    PhysicalAssetEconomicStatus.scrapped => '已报废',
    PhysicalAssetEconomicStatus.lost => '已丢失',
    PhysicalAssetEconomicStatus.gifted => '已赠送',
  };
}

IconData _assetIcon(AssetType type) => switch (type) {
      AssetType.digital => Icons.devices_other_outlined,
      AssetType.appliance => Icons.chair_outlined,
      AssetType.vehicle => Icons.directions_car_outlined,
      AssetType.property => Icons.home_work_outlined,
      AssetType.valuables => Icons.diamond_outlined,
      AssetType.collectibles => Icons.collections_bookmark_outlined,
      AssetType.tools => Icons.handyman_outlined,
      AssetType.other => Icons.inventory_2_outlined,
    };

IconData _receivableIcon(ReceivableAssetType type) => switch (type) {
      ReceivableAssetType.rentalDeposit => Icons.key_outlined,
      ReceivableAssetType.loanOut => Icons.call_made_outlined,
      ReceivableAssetType.accountReceivable => Icons.receipt_long_outlined,
      ReceivableAssetType.prepaidCard => Icons.credit_card_outlined,
      ReceivableAssetType.membershipCard => Icons.card_membership_outlined,
      ReceivableAssetType.securityDeposit => Icons.verified_user_outlined,
      ReceivableAssetType.other => Icons.assignment_return_outlined,
    };

class _ReceivableAssetGroupCard extends StatelessWidget {
  final List<ReceivableAssetEntity> assets;
  final ValueChanged<ReceivableAssetEntity> onTap;

  const _ReceivableAssetGroupCard({
    required this.assets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                Text(
                  '权益资产',
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(width: 6),
                Text(
                  '${assets.length} 项',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
          for (int i = 0; i < assets.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 62,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _ReceivableAssetTile(
              asset: assets[i],
              onTap: () => onTap(assets[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceivableAssetTile extends StatelessWidget {
  final ReceivableAssetEntity asset;
  final VoidCallback onTap;

  const _ReceivableAssetTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dueReminder =
        context.watch<AppRepository>().dueReminderForReceivable(asset);
    final dueText = _receivableDueReminderText(dueReminder);
    final muted = !asset.countsInNetWorth;
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
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _receivableIcon(asset.type),
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
                    asset.name,
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
                  Text(
                    [
                      asset.type.label,
                      _receivableStatusLabel(asset),
                      if (asset.counterparty.isNotEmpty) asset.counterparty,
                      if (asset.inclusionQuality ==
                          AssetInclusionQuality.needsReview)
                        '计入口径待确认'
                      else if (!asset.includeInNetWorth)
                        '不计入净资产',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.secondary(scheme).copyWith(
                      color: muted
                          ? AppTextColor.hint(scheme)
                          : AppTextColor.secondary(scheme),
                    ),
                  ),
                  if (dueText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dueText,
                      key: Key('receivable-due-${asset.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption(scheme).copyWith(
                        color: dueReminder.status == AssetReminderStatus.expired
                            ? scheme.error
                            : AppTextColor.secondary(scheme),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              MoneyFormat.string(
                asset.remainingAmount,
                currencyCode: asset.currencyCode,
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w500,
                    color: muted ? AppTextColor.hint(scheme) : scheme.onSurface,
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
}

String _receivableStatusLabel(ReceivableAssetEntity asset) {
  return switch (asset.economicStatus) {
    ReceivableEconomicStatus.active => '待收回',
    ReceivableEconomicStatus.partialRecovered => '部分收回',
    ReceivableEconomicStatus.recovered => '已收回',
    ReceivableEconomicStatus.lost => '已损失',
    ReceivableEconomicStatus.unknown => '状态待确认',
  };
}

String _dateText(DateTime? date) {
  if (date == null) return '未填写';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _calendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

Future<void> _deleteManagedInvoiceQuietly(String filePath) async {
  final root = await getApplicationDocumentsDirectory();
  final managedRoot =
      path.normalize(path.absolute(path.join(root.path, 'asset_media')));
  final candidate = path.normalize(path.absolute(filePath));
  if (!path.isWithin(managedRoot, candidate)) return;
  try {
    await File(candidate).delete();
  } on FileSystemException {
    // The referenced file may already be gone.
  }
}

String? _receivableDueReminderText(AssetReminderState reminder) {
  return switch (reminder.status) {
    AssetReminderStatus.upcoming => '${reminder.daysUntilDue} 天后到期',
    AssetReminderStatus.dueToday => '今天到期',
    AssetReminderStatus.expired => '已逾期 ${reminder.daysUntilDue!.abs()} 天',
    AssetReminderStatus.none || AssetReminderStatus.inactive => null,
  };
}

String _reminderDetailText(
  AssetReminderState reminder, {
  required String upcomingLabel,
  required String dueTodayLabel,
  required String expiredLabel,
  required String inactiveLabel,
}) {
  return switch (reminder.status) {
    AssetReminderStatus.upcoming => '$upcomingLabel ${reminder.daysUntilDue} 天',
    AssetReminderStatus.dueToday => dueTodayLabel,
    AssetReminderStatus.expired =>
      '$expiredLabel ${reminder.daysUntilDue!.abs()} 天',
    AssetReminderStatus.none => reminder.daysUntilDue == null
        ? '未填写'
        : '$upcomingLabel ${reminder.daysUntilDue} 天',
    AssetReminderStatus.inactive => inactiveLabel,
  };
}

Decimal _parseDecimalInput(String raw) {
  final normalized = raw.trim().replaceAll(',', '').replaceAll('¥', '');
  if (normalized.isEmpty) return Decimal.zero;
  return Decimal.tryParse(normalized) ?? Decimal.zero;
}

bool _decimalInputValid(String raw, {bool required = false}) {
  final normalized = raw.trim().replaceAll(',', '').replaceAll('¥', '');
  if (normalized.isEmpty) return !required;
  return Decimal.tryParse(normalized) != null;
}

class _ReceivableAssetDetailSheet extends StatelessWidget {
  final ReceivableAssetEntity asset;
  final VoidCallback onEdit;

  const _ReceivableAssetDetailSheet({
    required this.asset,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final current = repo.receivableDetailById(asset.id) ?? asset;
    final dueReminder = repo.dueReminderForReceivable(current);
    final canRecover = current.remainingAmount > Decimal.zero &&
        (current.economicStatus == ReceivableEconomicStatus.active ||
            current.economicStatus ==
                ReceivableEconomicStatus.partialRecovered);
    final recoveries = repo.recoveriesForReceivableAsset(current.id).take(5);
    final events = repo.eventsForReceivableAsset(current.id).take(6).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: current.name,
              onClose: () => Navigator.pop(context),
              actionLabel: '编辑',
              onAction: onEdit,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailSection(
                      title: '权益信息',
                      children: [
                        _DetailRow(label: '类型', value: current.type.label),
                        _DetailRow(
                          label: '状态',
                          value: _receivableStatusLabel(current),
                        ),
                        _DetailRow(
                          label: '剩余金额',
                          value: MoneyFormat.string(current.remainingAmount),
                        ),
                        _DetailRow(
                          label: '原始金额',
                          value: MoneyFormat.string(current.originalAmount),
                        ),
                        if (current.counterparty.isNotEmpty)
                          _DetailRow(
                            label: '对象',
                            value: current.counterparty,
                          ),
                        _DetailRow(
                          label: '到期日',
                          value: current.dueDate == null
                              ? '未填写'
                              : '${_dateText(current.dueDate)} · ${_reminderDetailText(
                                  dueReminder,
                                  upcomingLabel: '还有',
                                  dueTodayLabel: '今天到期',
                                  expiredLabel: '已逾期',
                                  inactiveLabel: '已结束跟踪',
                                )}',
                        ),
                        _DetailRow(
                          label: '净资产',
                          value: current.countsInNetWorth ? '计入净资产' : '不计入净资产',
                        ),
                        if (current.note.isNotEmpty)
                          _DetailRow(label: '备注', value: current.note),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _AssetActionButton(
                            label: '收回',
                            icon: Icons.savings_outlined,
                            onTap: canRecover
                                ? () => _showRecoverSheet(context, current)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AssetActionButton(
                            label: current.isArchived ? '恢复' : '归档',
                            icon: current.isArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            onTap: () => _toggleArchive(context, repo, current),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AssetActionButton(
                            label: '损失',
                            icon: Icons.money_off_csred_outlined,
                            onTap: canRecover
                                ? () => _markLost(context, repo, current)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (current.inclusionQuality ==
                        AssetInclusionQuality.needsReview) ...[
                      const SizedBox(height: 12),
                      SettingsGroup(
                        margin: EdgeInsets.zero,
                        children: [
                          SettingsRow(
                            leading: const Icon(Icons.fact_check_outlined),
                            title: '确认状态与计入口径',
                            subtitle: '确认后结束迁移待处理状态',
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _showReviewSheet(context, current),
                          ),
                        ],
                      ),
                    ],
                    if (recoveries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailSection(
                        title: '收回历史',
                        children: [
                          for (final recovery in recoveries)
                            _DetailRow(
                              label: _dateText(recovery.recoveredAt),
                              value: MoneyFormat.string(recovery.amount),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _AssetActionButton(
                        label: '撤销最近一次收回',
                        icon: Icons.undo,
                        onTap: () => _undoLatestRecovery(
                          context,
                          repo,
                          recoveries.first,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: '最近事件',
                      children: events.isEmpty
                          ? const [
                              _DetailRow(label: '暂无', value: '还没有权益事件'),
                            ]
                          : [
                              for (final event in events)
                                _DetailRow(
                                  label: event.eventType.label,
                                  value:
                                      '${_dateText(event.occurredAt)}${event.value == null ? '' : ' · ${MoneyFormat.string(event.value!)}'}',
                                ),
                            ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecoverSheet(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: _ReceivableRecoverySheet(asset: asset),
    );
  }

  void _showReviewSheet(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: _ReceivableReviewSheet(asset: asset),
    );
  }

  Future<void> _toggleArchive(
    BuildContext context,
    AppRepository repo,
    ReceivableAssetEntity asset,
  ) async {
    if (asset.isArchived) {
      await repo.restoreReceivableAsset(asset.id);
      if (context.mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '归档权益资产',
      message: '归档只会把它移出默认列表，不会改变金额、状态或净资产合计。',
      confirmText: '归档',
    );
    if (confirmed) {
      await repo.archiveReceivableAsset(asset.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _markLost(
    BuildContext context,
    AppRepository repo,
    ReceivableAssetEntity asset,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '标记为损失',
      message: '这会把剩余可收回金额归零，并从净资产中移除。',
      confirmText: '标记损失',
    );
    if (confirmed) {
      await repo.markReceivableAssetLost(asset.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _undoLatestRecovery(
    BuildContext context,
    AppRepository repo,
    ReceivableRecoveryEntity recovery,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销最近一次收回',
      message: '到账流水会删除，金额会恢复到权益资产。',
      confirmText: '撤销',
    );
    if (!confirmed) return;
    await repo.undoReceivableRecovery(recovery.id);
    if (context.mounted) Navigator.pop(context);
  }
}

class _PhysicalAssetDetailPage extends StatelessWidget {
  final int assetId;
  final PhysicalAssetEntity fallbackAsset;

  const _PhysicalAssetDetailPage({
    required this.assetId,
    required this.fallbackAsset,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final current = repo.physicalAssetDetailById(assetId) ?? fallbackAsset;
    final scheme = Theme.of(context).colorScheme;
    final events = repo.eventsForAsset(current.id).take(6).toList();
    final links = repo.transactionLinksForAsset(current.id);
    final valuationTrend = resolveAssetValuationTrend(
      repo.valuationsForAsset(current.id).map(
            (valuation) => AssetValuationPoint(
              value: valuation.value,
              effectiveAt: valuation.valuedAt,
              isTermination: valuation.source == AssetValueSource.sale ||
                  valuation.source == AssetValueSource.statusZero,
            ),
          ),
      endedAt: current.endedAt,
    );
    final recentValuations = valuationTrend.points.reversed.take(4).toList();
    final hasKnownValuation = valuationTrend.points.isNotEmpty;
    final cost = repo.physicalAssetAcquisitionCost(current.id);
    final additional = repo.physicalAssetAdditionalCost(current.id);
    final usage = repo.physicalAssetUsage(current.id);
    final warrantyReminder = repo.warrantyReminderForAsset(current);
    final savingsGoal = current.savingsGoalId == null
        ? null
        : repo.savingsGoalById(current.savingsGoalId!);
    final costLabel = current.acquisitionCostSource ==
            AssetAcquisitionCostSource.transactionAllocations
        ? '净购置成本'
        : '购买价';
    final costText = cost.amount == null
        ? '待确认'
        : '${MoneyFormat.string(
            cost.amount!,
            currencyCode: current.currencyCode,
          )}${cost.isExact ? '' : ' · 待确认'}';
    final metrics = _resolveMetrics(repo, current, cost);
    final owned = current.economicStatus == PhysicalAssetEconomicStatus.owned;
    final hasPendingRefundAllocation = links.any(
      (link) =>
          link.costQuality ==
          AssetAllocationCostQuality.pendingRefundAllocation,
    );
    String holdingCostReason(String metricReason) {
      if (!cost.isExact) return cost.reason;
      if (!additional.isExact) return additional.reason;
      return metricReason.isEmpty ? '成本数据待确认' : metricReason;
    }

    final cumulativeText = cost.isExact &&
            additional.isExact &&
            metrics.cumulativeHoldingInvestment.isExact
        ? MoneyFormat.string(
            metrics.cumulativeHoldingInvestment.value!,
            currencyCode: current.currencyCode,
          )
        : '不可计算 · ${holdingCostReason(metrics.cumulativeHoldingInvestment.reason)}';
    final additionalText = additional.isExact
        ? MoneyFormat.string(
            additional.amount,
            currencyCode: current.currencyCode,
          )
        : '待确认 · ${additional.reason}';
    final dailyText = cost.isExact &&
            additional.isExact &&
            metrics.dailyHoldingCost.isExact
        ? '${MoneyFormat.string(metrics.dailyHoldingCost.value!, currencyCode: current.currencyCode)}/天'
        : '不可计算 · ${holdingCostReason(metrics.dailyHoldingCost.reason)}';
    final perUseText = usage.isExact &&
            cost.isExact &&
            additional.isExact &&
            metrics.perUseHoldingCost.isExact
        ? '${MoneyFormat.string(metrics.perUseHoldingCost.value!, currencyCode: current.currencyCode)}/次'
        : '不可计算 · ${!usage.isExact ? '使用记录待确认' : holdingCostReason(metrics.perUseHoldingCost.reason)}';
    final heldText = metrics.heldDays.isExact
        ? '${metrics.heldDays.value} 天'
        : '不可计算 · ${metrics.heldDays.reason}';
    final retentionText = cost.isExact && metrics.valueRetentionRatio.isExact
        ? '${(metrics.valueRetentionRatio.value!.toDouble() * 100).toStringAsFixed(1)}%'
        : '不可计算 · ${cost.isExact ? metrics.valueRetentionRatio.reason : cost.reason}';
    final warrantyText = current.warrantyUntil == null
        ? '未填写'
        : '${_dateText(current.warrantyUntil)} · ${_reminderDetailText(
            warrantyReminder,
            upcomingLabel: '还有',
            dueTodayLabel: '今天到期',
            expiredLabel: '已过期',
            inactiveLabel: '已结束持有',
          )}';
    final dailyAvailable =
        cost.isExact && additional.isExact && metrics.dailyHoldingCost.isExact;
    final primaryMetric = dailyAvailable ? dailyText : '日均暂不可计算';
    final primaryCaption = dailyAvailable
        ? '$heldText · ${hasKnownValuation ? '当前估值 ${MoneyFormat.string(current.currentValue, currencyCode: current.currencyCode)}' : '当前估值待确认'}'
        : '$heldText · ${holdingCostReason(metrics.dailyHoldingCost.reason)}';
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
                  context,
                  repo,
                  current,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        key: const Key('physical-asset-detail-page'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _PhysicalAssetHero(asset: current),
          const SizedBox(height: 16),
          Text(
            primaryMetric,
            key: const Key('physical-asset-primary-metric'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(primaryCaption, style: AppType.secondary(scheme)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(current.assetType.label),
              _InfoPill(_physicalAssetStatusLabel(current)),
              _InfoPill(
                current.countsInNetWorth ? '计入净资产' : '不计入净资产',
              ),
              if (current.inclusionQuality == AssetInclusionQuality.needsReview)
                const _InfoPill('计入口径待确认'),
            ],
          ),
          if (current.purchaseDate == null) ...[
            const SizedBox(height: 12),
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  key: const Key('physical-asset-fix-purchase-date'),
                  leading: const Icon(Icons.event_busy_outlined),
                  title: '补充购买日期',
                  subtitle: '补充后才能正确计算持有天数和日均花费',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: owned
                      ? () => showBlurSheet<void>(
                            context,
                            child: _PhysicalAssetFormSheet(asset: current),
                          )
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _DetailSection(
            title: '持有指标',
            children: [
              _DetailRow(label: '日均持有花费', value: dailyText),
              _DetailRow(label: '持有天数', value: heldText),
              _DetailRow(
                label: '当前估值',
                value: hasKnownValuation
                    ? MoneyFormat.string(
                        current.currentValue,
                        currencyCode: current.currencyCode,
                      )
                    : '待确认',
              ),
              _DetailRow(label: '累计持有投入', value: cumulativeText),
              _DetailRow(label: '后续支出', value: additionalText),
              if (current.usageTrackingEnabled) ...[
                _DetailRow(
                  label: '累计使用',
                  value:
                      '${usage.totalCount} 次${usage.isExact ? '' : ' · 待确认'}',
                ),
                _DetailRow(label: '每次使用成本', value: perUseText),
              ],
              _DetailRow(label: '保值率', value: retentionText),
              if (current.endedAt != null)
                _DetailRow(
                  label: '结束日期',
                  value: _dateText(current.endedAt),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentValuations.isNotEmpty) ...[
            _DetailSection(
              title: '估值记录',
              children: [
                for (final point in recentValuations)
                  _DetailRow(
                    label: _dateText(point.effectiveAt),
                    value: MoneyFormat.string(
                      point.value,
                      currencyCode: current.currencyCode,
                    ),
                  ),
                if (valuationTrend.ignoredFutureCount > 0 ||
                    valuationTrend.ignoredAfterTerminationCount > 0)
                  _DetailRow(
                    label: '未参与当前估值',
                    value:
                        '${valuationTrend.ignoredFutureCount + valuationTrend.ignoredAfterTerminationCount} 条',
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _DetailSection(
            title: '资产信息',
            children: [
              _DetailRow(label: '来源', value: current.sourceType.label),
              _DetailRow(
                label: costLabel,
                value: costText,
              ),
              _DetailRow(
                label: '购买日期',
                value: _dateText(current.purchaseDate),
              ),
              _DetailRow(label: '保修', value: warrantyText),
              if (current.brand.isNotEmpty)
                _DetailRow(label: '品牌', value: current.brand),
              if (current.model.isNotEmpty)
                _DetailRow(label: '型号', value: current.model),
              if (current.location.isNotEmpty)
                _DetailRow(label: '位置', value: current.location),
              if (current.note.isNotEmpty)
                _DetailRow(label: '备注', value: current.note),
            ],
          ),
          const SizedBox(height: 12),
          _DetailSection(
            title: '凭证与折旧',
            children: [
              _DetailRow(
                label: '照片',
                value: current.photoPath.isEmpty ? '未添加' : '已添加',
              ),
              _DetailRow(
                label: '发票',
                value: current.invoicePath.isEmpty ? '未添加' : '已添加',
              ),
              _DetailRow(
                label: '折旧',
                value: current.hasLinearDepreciation
                    ? '线性折旧 · ${current.usefulLifeMonths} 个月${current.depreciationPaused ? ' · 已暂停' : ''}'
                    : '未开启',
              ),
              if (current.hasLinearDepreciation)
                _DetailRow(
                  label: '残值',
                  value: MoneyFormat.string(current.salvageValue),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppPillButton(
                label: '更新估值',
                onPressed:
                    owned ? () => _showValueSheet(context, current) : null,
              ),
              AppPillButton(
                label: '关联支出',
                onPressed: owned
                    ? () => _showCostLinkSheet(context, repo, current)
                    : null,
              ),
              if (owned && current.usageTrackingEnabled)
                AppPillButton(
                  label: '记录使用',
                  onPressed: () => _recordUsage(context, repo, current),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                key: const Key('physical-asset-link-cost'),
                leading: const Icon(Icons.add_link),
                title: '持有成本',
                subtitle: '维修、配件、保险等支出可从上方关联',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: owned
                    ? () => _showCostLinkSheet(context, repo, current)
                    : null,
              ),
              SettingsRow(
                key: const Key('physical-asset-usage-tracking-row'),
                leading: const Icon(Icons.touch_app_outlined),
                title: '记录使用次数',
                subtitle: owned ? '用于计算每次使用成本' : '已结束持有，不能继续记录',
                trailing: AppSwitch(
                  key: const Key('physical-asset-usage-tracking'),
                  value: current.usageTrackingEnabled,
                  onChanged: owned
                      ? (enabled) => repo.setPhysicalAssetUsageTracking(
                            current.id,
                            enabled: enabled,
                          )
                      : null,
                ),
              ),
              if (current.usageTrackingEnabled)
                SettingsRow(
                  key: const Key('physical-asset-usage-controls'),
                  leading: const Icon(Icons.format_list_numbered),
                  title: '使用次数',
                  subtitle:
                      '累计 ${usage.totalCount} 次${usage.isExact ? '' : ' · 记录待确认'}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: '撤销最近一次',
                        child: AppCircleButton(
                          key: const Key('physical-asset-usage-undo'),
                          icon: Icons.undo,
                          size: 34,
                          iconSize: 18,
                          onPressed: owned && usage.totalCount > 0
                              ? () => _undoLatestUsage(
                                    context,
                                    repo,
                                    current,
                                  )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: '记录一次使用',
                        child: AppCircleButton(
                          key: const Key('physical-asset-usage-add'),
                          icon: Icons.add,
                          size: 34,
                          iconSize: 18,
                          onPressed: owned
                              ? () => _recordUsage(
                                    context,
                                    repo,
                                    current,
                                  )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              Builder(
                builder: (menuContext) => SettingsRow(
                  key: const Key('physical-asset-savings-goal'),
                  leading: const Icon(Icons.savings_outlined),
                  title: '存钱目标',
                  subtitle: savingsGoal == null
                      ? '未关联，可选择已有目标'
                      : '已关联：${savingsGoal.emoji} ${savingsGoal.name}',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showSavingsGoalMenu(
                    menuContext,
                    context,
                    repo,
                    current,
                  ),
                ),
              ),
              if (hasPendingRefundAllocation)
                SettingsRow(
                  leading: const Icon(Icons.call_split_outlined),
                  title: '分配退款',
                  subtitle: '多件物品订单的退款待确认',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showPhysicalAssetRefundAllocation(
                    context,
                    repo,
                    current.id,
                  ),
                ),
              if (current.inclusionQuality == AssetInclusionQuality.needsReview)
                SettingsRow(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: '确认状态与计入口径',
                  subtitle: '确认后结束迁移待处理状态',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showReviewSheet(context, current),
                ),
            ],
          ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailSection(
              title: '账单关联',
              children: [
                for (final link in links.take(4))
                  _DetailRow(
                    label: link.linkType.label,
                    value: '交易 #${link.transactionId} · '
                        '${MoneyFormat.string(
                      repo.physicalAssetLinkCurrentAmount(link),
                      currencyCode: current.currencyCode,
                    )}',
                  ),
              ],
            ),
            for (final link in links.where((item) =>
                item.linkType !=
                AssetTransactionLinkType.saleAccountMovement)) ...[
              const SizedBox(height: 8),
              _AssetActionButton(
                label: '解除${link.linkType.label}关联',
                icon: Icons.link_off_outlined,
                onTap: () => _unlinkTransaction(context, repo, link),
              ),
            ],
          ],
          const SizedBox(height: 12),
          _DetailSection(
            title: '最近事件',
            children: events.isEmpty
                ? const [
                    _DetailRow(label: '暂无', value: '还没有资产事件'),
                  ]
                : [
                    for (final event in events)
                      _DetailRow(
                        label: event.eventType.label,
                        value:
                            '${_dateText(event.occurredAt)}${event.value == null ? '' : ' · ${MoneyFormat.string(event.value!)}'}',
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(
    BuildContext menuContext,
    BuildContext pageContext,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) {
    final owned = asset.economicStatus == PhysicalAssetEconomicStatus.owned;
    final hasPurchaseLink = repo.transactionLinksForAsset(asset.id).any(
          (link) =>
              link.linkType == AssetTransactionLinkType.sourceTransaction ||
              link.linkType == AssetTransactionLinkType.purchaseTransaction,
        );
    final canUndoTerminal =
        (asset.economicStatus == PhysicalAssetEconomicStatus.scrapped ||
                asset.economicStatus == PhysicalAssetEconomicStatus.lost ||
                asset.economicStatus == PhysicalAssetEconomicStatus.gifted) &&
            repo.canUndoPhysicalAssetTerminalStatus(asset.id);
    showIosMenu(
      menuContext,
      [
        if (owned)
          IosMenuItem(
            label: '编辑资料',
            icon: Icons.edit_outlined,
            onTap: () => showBlurSheet<void>(
              pageContext,
              child: _PhysicalAssetFormSheet(asset: asset),
            ),
          ),
        if (owned)
          IosMenuItem(
            label: asset.usageStatus == PhysicalAssetUsageStatus.idle
                ? '标记为在用'
                : '标记为闲置',
            icon: asset.usageStatus == PhysicalAssetUsageStatus.idle
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline,
            onTap: () => _toggleUsageStatus(pageContext, repo, asset),
          ),
        IosMenuItem(
          label: '照片与凭证',
          icon: Icons.photo_library_outlined,
          onTap: () => _showEvidenceSheet(pageContext, asset),
        ),
        IosMenuItem(
          label: '折旧设置',
          icon: Icons.trending_down_outlined,
          onTap: () => _showDepreciationSheet(pageContext, asset),
        ),
        if (owned)
          IosMenuItem(
            label: '出售物品',
            icon: Icons.sell_outlined,
            onTap: () => _showSellSheet(pageContext, asset),
          ),
        if (asset.economicStatus == PhysicalAssetEconomicStatus.sold)
          IosMenuItem(
            label: '撤销出售',
            icon: Icons.undo,
            onTap: () => _undoSale(pageContext, repo, asset),
          ),
        if (owned && hasPurchaseLink)
          IosMenuItem(
            label: '确认退货',
            icon: Icons.assignment_return_outlined,
            onTap: () =>
                _returnPhysicalAssetFromDetail(pageContext, repo, asset),
          ),
        if (asset.economicStatus == PhysicalAssetEconomicStatus.returned)
          IosMenuItem(
            label: '撤销退货状态',
            icon: Icons.undo,
            onTap: () => _undoPhysicalAssetReturnFromDetail(
              pageContext,
              repo,
              asset,
            ),
          ),
        if (owned)
          IosMenuItem(
            label: '报废',
            icon: Icons.delete_sweep_outlined,
            onTap: () => _showTerminalSheet(
              pageContext,
              asset,
              status: PhysicalAssetStatus.disposed,
              actionLabel: '报废',
            ),
          ),
        if (owned)
          IosMenuItem(
            label: '标记丢失',
            icon: Icons.search_off_outlined,
            onTap: () => _showTerminalSheet(
              pageContext,
              asset,
              status: PhysicalAssetStatus.lost,
              actionLabel: '丢失',
            ),
          ),
        if (owned)
          IosMenuItem(
            label: '赠送他人',
            icon: Icons.redeem_outlined,
            onTap: () => _showTerminalSheet(
              pageContext,
              asset,
              status: PhysicalAssetStatus.gifted,
              actionLabel: '赠送',
            ),
          ),
        if (canUndoTerminal)
          IosMenuItem(
            label: '撤销结束持有',
            icon: Icons.undo,
            onTap: () => _undoTerminalStatus(pageContext, repo, asset),
          ),
        IosMenuItem(
          label: asset.isArchived ? '恢复到列表' : '归档',
          icon: asset.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          onTap: () => _toggleArchive(pageContext, repo, asset),
        ),
      ],
    );
  }

  Future<void> _toggleUsageStatus(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    final next = asset.usageStatus == PhysicalAssetUsageStatus.idle
        ? PhysicalAssetStatus.active
        : PhysicalAssetStatus.idle;
    await repo.setPhysicalAssetStatus(
      id: asset.id,
      status: next,
      note: next == PhysicalAssetStatus.idle ? '标记闲置' : '恢复在用',
    );
    if (context.mounted) {
      showAppToast(
          context, next == PhysicalAssetStatus.idle ? '已标记闲置' : '已标记在用');
    }
  }

  Future<void> _showCostLinkSheet(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) {
    return showPhysicalAssetCostLinkSheet(
      context,
      loadCandidates: () async {
        final bookNames = {
          for (final book in repo.books) book.id: book.name,
        };
        return [
          for (final transaction
              in repo.eligiblePhysicalAssetCostTransactions(assetId: asset.id))
            PhysicalAssetCostLinkCandidateData(
              transactionId: transaction.id,
              title: transaction.note.trim().isNotEmpty
                  ? transaction.note.trim()
                  : transaction.categoryNameZh.trim().isNotEmpty
                      ? transaction.categoryNameZh.trim()
                      : '未命名支出',
              date: transaction.date,
              amountCents: repo.physicalAssetTransactionFamilyNetCents(
                transaction.id,
              ),
              bookName: bookNames[transaction.bookId] ?? '未指定账本',
              alreadyLinked: repo.isTransactionLinkedAsPhysicalAssetCost(
                transaction.id,
              ),
            ),
        ];
      },
      onLink: (transactionId, costType) => repo.linkPhysicalAssetCost(
        assetId: asset.id,
        transactionId: transactionId,
        type: switch (costType) {
          PhysicalAssetCostType.maintenance =>
            AssetTransactionLinkType.maintenance,
          PhysicalAssetCostType.accessory => AssetTransactionLinkType.accessory,
          PhysicalAssetCostType.insurance => AssetTransactionLinkType.insurance,
          PhysicalAssetCostType.otherCost => AssetTransactionLinkType.otherCost,
        },
      ),
    );
  }

  Future<void> _recordUsage(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    await repo.recordPhysicalAssetUsage(asset.id);
    if (context.mounted) showAppToast(context, '已记录 1 次使用');
  }

  Future<void> _undoLatestUsage(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    await repo.undoLatestPhysicalAssetUsage(asset.id);
    if (context.mounted) showAppToast(context, '已撤销最近一次使用');
  }

  void _showSavingsGoalMenu(
    BuildContext menuContext,
    BuildContext sheetContext,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) {
    if (repo.savingsGoals.isEmpty && asset.savingsGoalId == null) {
      showAppToast(sheetContext, '还没有可关联的存钱目标');
      return;
    }
    showIosMenu(
      menuContext,
      [
        if (asset.savingsGoalId != null)
          IosMenuItem(
            label: '解除关联',
            icon: Icons.link_off_outlined,
            onTap: () async {
              await repo.setPhysicalAssetSavingsGoal(asset.id, null);
              if (sheetContext.mounted) {
                showAppToast(sheetContext, '已解除存钱目标');
              }
            },
          ),
        for (final goal in repo.savingsGoals)
          IosMenuItem(
            label: '${goal.emoji} ${goal.name}',
            icon: Icons.savings_outlined,
            selected: goal.id == asset.savingsGoalId,
            onTap: () async {
              await repo.setPhysicalAssetSavingsGoal(asset.id, goal.id);
              if (sheetContext.mounted) {
                showAppToast(sheetContext, '已关联「${goal.name}」');
              }
            },
          ),
      ],
    );
  }

  Future<void> _undoTerminalStatus(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销结束持有',
      message: '物品会恢复结束前的状态和估值，不会新建、删除或修改普通账单。',
      confirmText: '撤销',
    );
    if (!confirmed) return;
    await repo.undoPhysicalAssetTerminalStatus(asset.id);
    if (context.mounted) showAppToast(context, '已恢复持有状态');
  }

  void _showValueSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: _AssetValueSheet(asset: asset),
    );
  }

  void _showSellSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: _AssetSellSheet(asset: asset),
    );
  }

  void _showEvidenceSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: _AssetEvidenceSheet(asset: asset),
    );
  }

  void _showDepreciationSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: _AssetDepreciationSheet(asset: asset),
    );
  }

  void _showReviewSheet(
    BuildContext context,
    PhysicalAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: _PhysicalAssetReviewSheet(asset: asset),
    );
  }

  void _showTerminalSheet(
    BuildContext context,
    PhysicalAssetEntity asset, {
    required PhysicalAssetStatus status,
    required String actionLabel,
  }) {
    showBlurSheet<void>(
      context,
      child: _PhysicalAssetTerminalSheet(
        asset: asset,
        status: status,
        actionLabel: actionLabel,
      ),
    );
  }

  Future<void> _toggleArchive(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    if (asset.isArchived) {
      await repo.restorePhysicalAsset(asset.id);
      if (context.mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '归档资产',
      message: '归档只会把它移出默认列表，不会改变价值、持有状态或净资产合计。',
      confirmText: '归档',
    );
    if (confirmed) {
      await repo.archivePhysicalAsset(asset.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _undoSale(
    BuildContext context,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销出售',
      message: '出售入账流水会删除，资产会恢复到出售前的状态和价值。',
      confirmText: '撤销',
    );
    if (!confirmed) return;
    await repo.undoPhysicalAssetSale(asset.id);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _unlinkTransaction(
    BuildContext context,
    AppRepository repo,
    AssetTransactionLinkEntity link,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '解除账单关联',
      message: '资产会保留，原账单之后可独立编辑或删除。',
      confirmText: '解除',
    );
    if (!confirmed) return;
    await repo.unlinkPhysicalAssetTransaction(
      assetId: link.assetId,
      transactionId: link.transactionId,
    );
  }
}

Future<void> _showPhysicalAssetRefundAllocation(
  BuildContext context,
  AppRepository repo,
  int assetId,
) {
  return showPhysicalAssetRefundAllocationSheet(
    context,
    load: () async {
      final pending =
          await repo.pendingPhysicalAssetRefundAllocationsForAsset(assetId);
      return [
        for (final item in pending)
          PhysicalAssetRefundAllocationData(
            refundTransactionId: item.refundTransactionId,
            refundCents: item.refundCents,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(item.refundDateMs),
            orderLabel: item.orderLabel,
            untrackedLimitCents: item.untrackedLimitCents,
            currentUntrackedCents: item.currentUntrackedCents,
            targets: [
              for (final target in item.targets)
                PhysicalAssetRefundAllocationTargetData(
                  assetId: target.assetId,
                  assetName: target.name,
                  grossCents: target.grossCents,
                  totalAllocatedRefundCents: target.totalAllocatedRefundCents,
                  currentRefundAllocationCents:
                      target.currentAllocatedRefundCents,
                ),
            ],
          ),
      ];
    },
    submit: (refundTransactionId, allocationsByAssetId, untrackedCents) =>
        repo.allocatePhysicalAssetRefund(
      refundTransactionId: refundTransactionId,
      allocationsByAssetId: allocationsByAssetId,
      untrackedCents: untrackedCents,
    ),
  );
}

String _usageStatusLabel(PhysicalAssetUsageStatus value) => switch (value) {
      PhysicalAssetUsageStatus.active => '在用',
      PhysicalAssetUsageStatus.idle => '闲置',
      PhysicalAssetUsageStatus.unknown => '暂不确定',
    };

IconData _usageStatusIcon(PhysicalAssetUsageStatus value) => switch (value) {
      PhysicalAssetUsageStatus.active => Icons.check_circle_outline,
      PhysicalAssetUsageStatus.idle => Icons.pause_circle_outline,
      PhysicalAssetUsageStatus.unknown => Icons.help_outline,
    };

class _PhysicalAssetTerminalSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  final PhysicalAssetStatus status;
  final String actionLabel;

  const _PhysicalAssetTerminalSheet({
    required this.asset,
    required this.status,
    required this.actionLabel,
  });

  @override
  State<_PhysicalAssetTerminalSheet> createState() =>
      _PhysicalAssetTerminalSheetState();
}

class _PhysicalAssetTerminalSheetState
    extends State<_PhysicalAssetTerminalSheet> {
  final TextEditingController _noteController = TextEditingController();
  DateTime _endedAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '${widget.actionLabel}物品',
              subtitle: '结束持有后当前价值归零，但不会生成账户流水、普通收支或预算。',
              onClose: () => Navigator.pop(context),
              actionLabel: '确认${widget.actionLabel}',
              onAction: _saving ? null : _save,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppLabeledField(
                      label: '结束日期',
                      child: _IosPickerField(
                        text: _dateText(_endedAt),
                        hint: '选择日期',
                        onTapMenu: (_) => _pickDate(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '说明（可选）',
                      child: TextField(
                        controller: _noteController,
                        maxLength: 80,
                        maxLines: 2,
                        style: AppType.body(scheme),
                        decoration: iosInputDecoration(
                          context,
                          hint: '例如损坏原因、赠送对象',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final purchaseDate = widget.asset.purchaseDate;
    final selected = await showAppDatePicker(
      context,
      initial: _endedAt,
      first: purchaseDate != null && !purchaseDate.isAfter(now)
          ? purchaseDate
          : null,
      last: now,
      title: '结束日期',
    );
    if (selected != null && mounted) setState(() => _endedAt = selected);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().setPhysicalAssetStatus(
            id: widget.asset.id,
            status: widget.status,
            occurredAt: _endedAt,
            note: _noteController.text.trim(),
          );
      if (!mounted) return;
      showAppToast(
        context,
        '已将「${widget.asset.name}」标记为${widget.actionLabel}',
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PhysicalAssetReviewSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;

  const _PhysicalAssetReviewSheet({required this.asset});

  @override
  State<_PhysicalAssetReviewSheet> createState() =>
      _PhysicalAssetReviewSheetState();
}

class _PhysicalAssetReviewSheetState extends State<_PhysicalAssetReviewSheet> {
  late PhysicalAssetUsageStatus _usageStatus;
  late bool _includeInNetWorth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usageStatus = widget.asset.usageStatus;
    _includeInNetWorth = widget.asset.includeInNetWorth;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '确认物品状态',
            subtitle: '归档仍只控制是否显示，不会改变这次确认的状态。',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: _saving ? null : _save,
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              SettingsRow(
                title: '使用状态',
                subtitle: '只描述当前是正在使用、闲置还是暂不确定',
                trailing: _MenuFilterButton<PhysicalAssetUsageStatus>(
                  value: _usageStatus,
                  values: PhysicalAssetUsageStatus.values,
                  labelOf: _usageStatusLabel,
                  iconOf: _usageStatusIcon,
                  onChanged: (value) => setState(() => _usageStatus = value),
                ),
              ),
              SettingsRow(
                title: '计入净资产',
                subtitle: '按当前估值进入人民币净资产合计',
                trailing: AppSwitch(
                  value: _includeInNetWorth,
                  onChanged: (value) =>
                      setState(() => _includeInNetWorth = value),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: Text(
              '确认只修正历史迁移中无法还原的信息，不会生成账单或改变当前估值。',
              style: AppType.caption(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().confirmPhysicalAssetState(
            widget.asset.id,
            usageStatus: _usageStatus,
            includeInNetWorth: _includeInNetWorth,
          );
      if (!mounted) return;
      showAppToast(context, '已确认「${widget.asset.name}」');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _receivableEconomicLabel(ReceivableEconomicStatus value) =>
    switch (value) {
      ReceivableEconomicStatus.active => '待收回',
      ReceivableEconomicStatus.partialRecovered => '部分收回',
      ReceivableEconomicStatus.recovered => '已收回',
      ReceivableEconomicStatus.lost => '已损失',
      ReceivableEconomicStatus.unknown => '暂不确定',
    };

IconData _receivableEconomicIcon(ReceivableEconomicStatus value) =>
    switch (value) {
      ReceivableEconomicStatus.active => Icons.schedule_outlined,
      ReceivableEconomicStatus.partialRecovered => Icons.pie_chart_outline,
      ReceivableEconomicStatus.recovered => Icons.check_circle_outline,
      ReceivableEconomicStatus.lost => Icons.money_off_outlined,
      ReceivableEconomicStatus.unknown => Icons.help_outline,
    };

class _ReceivableReviewSheet extends StatefulWidget {
  final ReceivableAssetEntity asset;

  const _ReceivableReviewSheet({required this.asset});

  @override
  State<_ReceivableReviewSheet> createState() => _ReceivableReviewSheetState();
}

class _ReceivableReviewSheetState extends State<_ReceivableReviewSheet> {
  late ReceivableEconomicStatus _economicStatus;
  late bool _includeInNetWorth;
  bool _saving = false;

  List<ReceivableEconomicStatus> get _allowedStatuses {
    if (widget.asset.remainingAmount <= Decimal.zero) {
      return const [
        ReceivableEconomicStatus.recovered,
        ReceivableEconomicStatus.lost,
        ReceivableEconomicStatus.unknown,
      ];
    }
    if (widget.asset.remainingAmount < widget.asset.originalAmount) {
      return const [
        ReceivableEconomicStatus.partialRecovered,
        ReceivableEconomicStatus.unknown,
      ];
    }
    return const [
      ReceivableEconomicStatus.active,
      ReceivableEconomicStatus.unknown,
    ];
  }

  bool get _canCountInNetWorth =>
      _economicStatus == ReceivableEconomicStatus.active ||
      _economicStatus == ReceivableEconomicStatus.partialRecovered;

  @override
  void initState() {
    super.initState();
    final allowed = _allowedStatuses;
    _economicStatus = allowed.contains(widget.asset.economicStatus)
        ? widget.asset.economicStatus
        : allowed.first;
    _includeInNetWorth = _canCountInNetWorth && widget.asset.includeInNetWorth;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '确认权益状态',
            subtitle: '请根据剩余金额确认这项权益现在的真实状态。',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: _saving ? null : _save,
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              SettingsRow(
                title: '经济状态',
                subtitle:
                    '剩余 ${MoneyFormat.string(widget.asset.remainingAmount, currencyCode: widget.asset.currencyCode)}',
                trailing: _MenuFilterButton<ReceivableEconomicStatus>(
                  value: _economicStatus,
                  values: _allowedStatuses,
                  labelOf: _receivableEconomicLabel,
                  iconOf: _receivableEconomicIcon,
                  onChanged: (value) => setState(() {
                    _economicStatus = value;
                    if (!_canCountInNetWorth) _includeInNetWorth = false;
                  }),
                ),
              ),
              SettingsRow(
                title: '计入净资产',
                subtitle:
                    _canCountInNetWorth ? '按剩余金额进入人民币净资产合计' : '已结束或暂不确定的权益不能计入',
                trailing: AppSwitch(
                  value: _includeInNetWorth,
                  onChanged: _canCountInNetWorth
                      ? (value) => setState(() => _includeInNetWorth = value)
                      : null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: Text(
              '确认不会生成收支或到账流水，归档状态也会保持不变。',
              style: AppType.caption(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().confirmReceivableAssetState(
            widget.asset.id,
            economicStatus: _economicStatus,
            includeInNetWorth: _includeInNetWorth,
          );
      if (!mounted) return;
      showAppToast(context, '已确认「${widget.asset.name}」');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PhysicalAssetHero extends StatelessWidget {
  final PhysicalAssetEntity asset;

  const _PhysicalAssetHero({required this.asset});

  @override
  Widget build(BuildContext context) {
    final source = asset.photoPath.trim().isNotEmpty
        ? asset.photoPath.trim()
        : asset.thumbnailPath.trim();
    final file = source.isEmpty ? null : File(source);
    return Semantics(
      image: true,
      label: '${asset.name}的物品照片',
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: file != null && file.existsSync()
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) =>
                      _PhysicalAssetHeroPlaceholder(asset: asset),
                )
              : _PhysicalAssetHeroPlaceholder(asset: asset),
        ),
      ),
    );
  }
}

class _PhysicalAssetHeroPlaceholder extends StatelessWidget {
  final PhysicalAssetEntity asset;

  const _PhysicalAssetHeroPlaceholder({required this.asset});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: AppColors.inputFill(scheme),
      child: Center(
        child: Icon(
          _assetIcon(asset.assetType),
          size: 56,
          color: AppTextColor.secondary(scheme),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String text;
  const _InfoPill(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppType.caption(scheme),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 14,
                endIndent: 14,
                color: AppColors.hairline(scheme),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppType.secondary(scheme),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.trailingValue(scheme),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _AssetActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: AppTextColor.secondary(scheme)),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceivableAssetFormSheet extends StatefulWidget {
  final ReceivableAssetEntity? asset;

  const _ReceivableAssetFormSheet({this.asset});

  @override
  State<_ReceivableAssetFormSheet> createState() =>
      _ReceivableAssetFormSheetState();
}

class _ReceivableAssetFormSheetState extends State<_ReceivableAssetFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _originalCtrl;
  late final TextEditingController _remainingCtrl;
  late final TextEditingController _counterpartyCtrl;
  late final TextEditingController _noteCtrl;
  late ReceivableAssetType _type;
  late ReceivableAssetStatus _status;
  late bool _includeInNetWorth;
  bool _saving = false;

  bool get _editing => widget.asset != null;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _nameCtrl = TextEditingController(text: asset?.name ?? '');
    _originalCtrl =
        TextEditingController(text: asset?.originalAmount.toString() ?? '');
    _remainingCtrl =
        TextEditingController(text: asset?.remainingAmount.toString() ?? '');
    _counterpartyCtrl = TextEditingController(text: asset?.counterparty ?? '');
    _noteCtrl = TextEditingController(text: asset?.note ?? '');
    _type = asset?.type ?? ReceivableAssetType.rentalDeposit;
    _status = asset?.status ?? ReceivableAssetStatus.active;
    _includeInNetWorth = asset?.includeInNetWorth ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _originalCtrl.dispose();
    _remainingCtrl.dispose();
    _counterpartyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final original = _parseDecimalInput(_originalCtrl.text);
    final remaining = _parseDecimalInput(_remainingCtrl.text);
    final valid = _nameCtrl.text.trim().isNotEmpty &&
        _decimalInputValid(_originalCtrl.text, required: true) &&
        _decimalInputValid(_remainingCtrl.text, required: true) &&
        original >= Decimal.zero &&
        remaining >= Decimal.zero &&
        remaining <= original;
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
              title: _editing ? '编辑权益资产' : '添加权益资产',
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
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      decoration: iosInputDecoration(context, hint: '权益名称'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _EnumDropdown<ReceivableAssetType>(
                      value: _type,
                      values: ReceivableAssetType.values,
                      labelOf: (value) => value.label,
                      hint: '权益类型',
                      onChanged: (value) => setState(() => _type = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _originalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(context, hint: '原始金额'),
                      onChanged: (_) {
                        if (!_editing) _remainingCtrl.text = _originalCtrl.text;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remainingCtrl,
                      readOnly: _editing,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(context, hint: '剩余可收回金额'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _counterpartyCtrl,
                      decoration:
                          iosInputDecoration(context, hint: '对方/机构（可选）'),
                    ),
                    const SizedBox(height: 12),
                    if (_editing) ...[
                      const _HintBox(
                        text: '剩余金额和状态请通过收回、损失、归档或恢复操作修改。',
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: iosInputDecoration(context, hint: '备注'),
                    ),
                    const SizedBox(height: 12),
                    _SwitchRow(
                      title: '计入净资产',
                      subtitle: '关闭后仍保留权益记录，但不进入净资产合计',
                      value: _includeInNetWorth,
                      onChanged: (v) => setState(() => _includeInNetWorth = v),
                    ),
                    if (remaining > original) ...[
                      const SizedBox(height: 12),
                      const _HintBox(text: '剩余可收回金额不能超过原始金额。'),
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
      final repo = context.read<AppRepository>();
      final original = _parseDecimalInput(_originalCtrl.text);
      final remaining = _parseDecimalInput(_remainingCtrl.text);
      if (_editing) {
        await repo.updateReceivableAsset(
          id: widget.asset!.id,
          name: _nameCtrl.text,
          type: _type,
          originalAmount: original,
          remainingAmount: remaining,
          status: _status,
          counterparty: _counterpartyCtrl.text,
          includeInNetWorth: _includeInNetWorth,
          note: _noteCtrl.text,
        );
      } else {
        await repo.addReceivableAsset(
          name: _nameCtrl.text,
          type: _type,
          originalAmount: original,
          remainingAmount: remaining,
          counterparty: _counterpartyCtrl.text,
          includeInNetWorth: _includeInNetWorth,
          note: _noteCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }
}

class _ReceivableRecoverySheet extends StatefulWidget {
  final ReceivableAssetEntity asset;

  const _ReceivableRecoverySheet({required this.asset});

  @override
  State<_ReceivableRecoverySheet> createState() =>
      _ReceivableRecoverySheetState();
}

class _ReceivableRecoverySheetState extends State<_ReceivableRecoverySheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  int? _accountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.asset.remainingAmount.toString());
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    _accountId ??= repo.accounts.firstOrNull?.id;
    final amount = _parseDecimalInput(_amountCtrl.text);
    final valid = _decimalInputValid(_amountCtrl.text, required: true) &&
        amount > Decimal.zero &&
        amount <= widget.asset.remainingAmount &&
        _accountId != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '收回权益',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyInputFormatters(),
                  decoration: iosInputDecoration(context, hint: '收回金额'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _AccountDropdown(
                  value: _accountId,
                  accounts: repo.accounts,
                  hint: '到账账户',
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '备注'),
                ),
                const SizedBox(height: 12),
                const _HintBox(
                  text: '收回会增加到账账户余额，并减少权益资产剩余金额；这不是普通收入，不会进入收入统计。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<AppRepository>().recoverReceivableAsset(
            id: widget.asset.id,
            amount: _parseDecimalInput(_amountCtrl.text),
            targetAccountId: _accountId,
            note: _noteCtrl.text,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }
}

class _PhysicalAssetFormSheet extends StatefulWidget {
  final PhysicalAssetEntity? asset;
  final PhysicalAssetSourceType sourceType;

  const _PhysicalAssetFormSheet({
    this.asset,
    this.sourceType = PhysicalAssetSourceType.historicalExisting,
  });

  @override
  State<_PhysicalAssetFormSheet> createState() =>
      _PhysicalAssetFormSheetState();
}

class _PhysicalAssetFormSheetState extends State<_PhysicalAssetFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _currentCtrl;
  late final TextEditingController _purchaseCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _noteCtrl;
  late AssetType _assetType;
  late PhysicalAssetSourceType _sourceType;
  late PhysicalAssetStatus _status;
  late bool _includeInNetWorth;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;
  int? _paymentAccountId;
  int? _purchaseCategoryId;
  AssetMediaStore? _mediaStore;
  AssetMediaFiles? _pendingMedia;
  bool _mediaCommitted = false;
  bool _saving = false;
  bool _resolvedLinkedPurchasePrice = false;

  static const _manualSources = [
    PhysicalAssetSourceType.historicalExisting,
    PhysicalAssetSourceType.giftReceived,
    PhysicalAssetSourceType.inheritance,
    PhysicalAssetSourceType.manualOther,
  ];

  bool get _editing => widget.asset != null;
  bool get _newPurchase =>
      !_editing &&
      _sourceType == PhysicalAssetSourceType.newPurchaseWithAccount;
  bool get _purchasePriceLocked =>
      _editing &&
      widget.asset!.acquisitionCostSource ==
          AssetAcquisitionCostSource.transactionAllocations;
  bool get _purchaseDateLocked => _purchasePriceLocked;
  bool get _purchasePriceKnown =>
      _purchasePriceLocked ||
      _purchaseCtrl.text.trim().isNotEmpty ||
      _sourceType == PhysicalAssetSourceType.giftReceived ||
      _sourceType == PhysicalAssetSourceType.inheritance;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _nameCtrl = TextEditingController(text: asset?.name ?? '');
    _currentCtrl =
        TextEditingController(text: asset?.currentValue.toString() ?? '');
    _purchaseCtrl =
        TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    _brandCtrl = TextEditingController(text: asset?.brand ?? '');
    _modelCtrl = TextEditingController(text: asset?.model ?? '');
    _locationCtrl = TextEditingController(text: asset?.location ?? '');
    _noteCtrl = TextEditingController(text: asset?.note ?? '');
    _assetType = asset?.assetType ?? AssetType.digital;
    _sourceType = asset?.sourceType ?? widget.sourceType;
    _status = asset?.status ?? PhysicalAssetStatus.active;
    _includeInNetWorth = asset?.includeInNetWorth ?? false;
    _purchaseDate = asset?.purchaseDate ??
        (_sourceType == PhysicalAssetSourceType.newPurchaseWithAccount
            ? _today()
            : null);
    _warrantyUntil = asset?.warrantyUntil;
    if (asset != null &&
        asset.acquisitionCostSource ==
            AssetAcquisitionCostSource.manualUnknown) {
      _purchaseCtrl.clear();
    }
  }

  @override
  void dispose() {
    if (!_mediaCommitted && _pendingMedia != null && _mediaStore != null) {
      unawaited(_mediaStore!.deleteFiles(_pendingMedia!));
    }
    _nameCtrl.dispose();
    _currentCtrl.dispose();
    _purchaseCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedLinkedPurchasePrice || !_purchasePriceLocked) return;
    final repo = context.read<AppRepository>();
    final cost = repo.physicalAssetAcquisitionCost(widget.asset!.id);
    if (cost.amount != null) {
      _purchaseCtrl.text = cost.amount!.toString();
    }
    final purchaseLink = repo
        .transactionLinksForAsset(widget.asset!.id)
        .where((link) =>
            link.linkType == AssetTransactionLinkType.sourceTransaction ||
            link.linkType == AssetTransactionLinkType.purchaseTransaction)
        .firstOrNull;
    if (purchaseLink != null) {
      final transaction = repo.transactionById(purchaseLink.transactionId);
      if (transaction != null) _purchaseDate = transaction.date;
    }
    _resolvedLinkedPurchasePrice = true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final expenseCategories =
        repo.categoriesForKindRanked(TransactionKind.expense);
    _paymentAccountId ??= repo.accounts.firstOrNull?.id;
    _purchaseCategoryId ??= expenseCategories.firstOrNull?.id;

    final valid = _nameCtrl.text.trim().isNotEmpty &&
        _decimalInputValid(_currentCtrl.text, required: true) &&
        _decimalInputValid(_purchaseCtrl.text, required: _newPurchase) &&
        (!_newPurchase ||
            (_paymentAccountId != null && _purchaseDate != null)) &&
        (_warrantyUntil == null ||
            _purchaseDate == null ||
            !_calendarDay(_warrantyUntil!)
                .isBefore(_calendarDay(_purchaseDate!)));
    final screenH = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: _editing
                  ? '编辑物品'
                  : _newPurchase
                      ? '记录新购买'
                      : '手工补录物品',
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
                      label: '物品名称',
                      child: TextField(
                        key: const Key('physical-asset-name'),
                        controller: _nameCtrl,
                        autofocus: true,
                        maxLength: 30,
                        decoration:
                            iosInputDecoration(context, hint: '例如 无线耳机'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '物品分类',
                      child: _EnumDropdown<AssetType>(
                        value: _assetType,
                        values: AssetType.values,
                        labelOf: (value) => value.label,
                        hint: '选择分类',
                        onChanged: (value) =>
                            setState(() => _assetType = value),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '物品照片（可选）',
                      helperText: '照片会复制到 App 受管目录，并生成列表缩略图。',
                      child: _buildPhotoField(),
                    ),
                    const SizedBox(height: 14),
                    if (!_editing) ...[
                      AppLabeledField(
                        label: '物品来源',
                        helperText: _newPurchase
                            ? '保存后会同步生成购买支出，不会重复入账。'
                            : '历史物品不会减少账户余额，也不会补造旧支出。',
                        child: _newPurchase
                            ? _ReadOnlyValueField(
                                text: _sourceType.label,
                                icon: Icons.shopping_bag_outlined,
                              )
                            : _EnumDropdown<PhysicalAssetSourceType>(
                                value: _sourceType,
                                values: _manualSources,
                                labelOf: (value) => value.label,
                                hint: '选择来源',
                                onChanged: (value) =>
                                    setState(() => _sourceType = value),
                              ),
                      ),
                      const SizedBox(height: 14),
                      if (_newPurchase) ...[
                        AppLabeledField(
                          label: '付款账户',
                          child: _AccountDropdown(
                            value: _paymentAccountId,
                            accounts: repo.accounts,
                            hint: '选择付款账户',
                            onChanged: (value) =>
                                setState(() => _paymentAccountId = value),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppLabeledField(
                          label: '支出分类',
                          child: _CategoryDropdown(
                            value: _purchaseCategoryId,
                            categories: expenseCategories,
                            hint: '选择支出分类',
                            onChanged: (value) =>
                                setState(() => _purchaseCategoryId = value),
                          ),
                        ),
                      ],
                    ],
                    AppLabeledField(
                      label: '当前估值',
                      helperText: '填写今天大约能卖多少钱，不是原购买价。',
                      child: TextField(
                        key: const Key('physical-asset-current-value'),
                        controller: _currentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: moneyInputFormatters(),
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: '例如 1800',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: _purchasePriceLocked ? '净购置成本' : '购买价',
                      helperText: _purchasePriceLocked
                          ? '成本来自原购买账单，不能在这里重复修改。'
                          : _sourceType ==
                                      PhysicalAssetSourceType.giftReceived ||
                                  _sourceType ==
                                      PhysicalAssetSourceType.inheritance
                              ? '没有实际支出可留空，将按 ¥0 记录。'
                              : _newPurchase
                                  ? '新购买必须填写，金额会同步写入支出。'
                                  : '不知道可以留空，日均花费和保值率会显示待补充。',
                      child: TextField(
                        key: const Key('physical-asset-purchase-price'),
                        controller: _purchaseCtrl,
                        readOnly: _purchasePriceLocked,
                        enableInteractiveSelection: !_purchasePriceLocked,
                        showCursor: !_purchasePriceLocked,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: moneyInputFormatters(),
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: _newPurchase ? '必填' : '可留空',
                        ).copyWith(
                          suffixIcon: _purchasePriceLocked
                              ? Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: AppTextColor.secondary(scheme),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: _newPurchase || _purchaseDateLocked
                          ? '购买日期'
                          : '购买日期（可选）',
                      helperText: _purchaseDateLocked
                          ? '购买日期继承原账单，避免物品指标与账单日期冲突。'
                          : _purchaseDate == null
                              ? '未填写时持有天数和日均花费不会计算。'
                              : '持有天数会从这一天开始计算。',
                      child: _purchaseDateLocked
                          ? _ReadOnlyValueField(
                              text: _dateText(_purchaseDate),
                              icon: Icons.event_outlined,
                            )
                          : _NullableDateField(
                              fieldKey:
                                  const Key('physical-asset-purchase-date'),
                              value: _purchaseDate,
                              emptyText: _newPurchase ? '请选择购买日期' : '暂不清楚',
                              onTap: _pickPurchaseDate,
                              onClear: _newPurchase
                                  ? null
                                  : () => setState(() => _purchaseDate = null),
                            ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '使用状态',
                      child: SlidingSegment<PhysicalAssetStatus>(
                        key: const Key('physical-asset-usage-status'),
                        items: const [
                          (PhysicalAssetStatus.active, '在用'),
                          (PhysicalAssetStatus.idle, '闲置'),
                        ],
                        value: _status == PhysicalAssetStatus.idle
                            ? PhysicalAssetStatus.idle
                            : PhysicalAssetStatus.active,
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_editing) ...[
                      const _HintBox(
                        text: '出售、报废、丢失、赠送和归档请从资产详情执行。',
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppLabeledField(
                            label: '品牌（可选）',
                            child: TextField(
                              controller: _brandCtrl,
                              decoration:
                                  iosInputDecoration(context, hint: '例如 Apple'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppLabeledField(
                            label: '型号（可选）',
                            child: TextField(
                              controller: _modelCtrl,
                              decoration: iosInputDecoration(context,
                                  hint: '例如 AirPods Pro'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '保修到期日（可选）',
                      helperText: _warrantyUntil != null &&
                              _purchaseDate != null &&
                              _warrantyUntil!.isBefore(_purchaseDate!)
                          ? '保修到期日不能早于购买日期。'
                          : null,
                      child: _NullableDateField(
                        fieldKey: const Key('physical-asset-warranty-date'),
                        value: _warrantyUntil,
                        emptyText: '未设置',
                        onTap: _pickWarrantyDate,
                        onClear: _warrantyUntil == null
                            ? null
                            : () => setState(() => _warrantyUntil = null),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '存放位置（可选）',
                      child: TextField(
                        controller: _locationCtrl,
                        decoration:
                            iosInputDecoration(context, hint: '例如 客厅书桌'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '备注（可选）',
                      child: TextField(
                        controller: _noteCtrl,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 80,
                        decoration:
                            iosInputDecoration(context, hint: '购买渠道、配置等'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          title: '计入净资产',
                          subtitle: _includeInNetWorth
                              ? '按当前估值进入人民币净资产合计'
                              : '只记录物品，不影响顶部净资产',
                          trailing: AppSwitch(
                            key: const Key('physical-asset-net-worth-switch'),
                            value: _includeInNetWorth,
                            onChanged: (value) =>
                                setState(() => _includeInNetWorth = value),
                          ),
                        ),
                      ],
                    ),
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
      final repo = context.read<AppRepository>();
      final currentValue = _parseDecimalInput(_currentCtrl.text);
      final resolvedPurchasePrice = _purchasePriceLocked
          ? repo.physicalAssetAcquisitionCost(widget.asset!.id).amount
          : null;
      final purchasePrice = resolvedPurchasePrice ??
          (_purchaseCtrl.text.trim().isEmpty
              ? Decimal.zero
              : _parseDecimalInput(_purchaseCtrl.text));
      if (!_editing && _sourceType == PhysicalAssetSourceType.manualOther) {
        final needsConfirm = currentValue >= Decimal.fromInt(500) ||
            purchasePrice > Decimal.zero;
        if (needsConfirm) {
          final confirmed = await showConfirmDialog(
            context,
            title: '确认其他来源',
            message: '这不会减少账户余额，也不会生成支出记录。若是最近购买，建议改选“新购买，同时记账”。',
            confirmText: '仍然保存',
          );
          if (!confirmed) return;
        }
      }
      if (_editing) {
        await repo.updatePhysicalAsset(
          id: widget.asset!.id,
          name: _nameCtrl.text.trim(),
          assetType: _assetType,
          purchasePrice: purchasePrice,
          currentValue: currentValue,
          currencyCode: widget.asset!.currencyCode,
          status: _status,
          purchaseDate: _purchaseDate,
          clearPurchaseDate: !_purchaseDateLocked && _purchaseDate == null,
          purchasePriceKnown: _purchasePriceLocked ? null : _purchasePriceKnown,
          brand: _brandCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          warrantyUntil: _warrantyUntil,
          clearWarrantyUntil: _warrantyUntil == null,
          note: _noteCtrl.text.trim(),
          includeInNetWorth: _includeInNetWorth,
        );
        await _commitPendingMedia(repo, widget.asset!.id);
      } else {
        final assetId = await repo.addPhysicalAsset(
          name: _nameCtrl.text.trim(),
          assetType: _assetType,
          currentValue: currentValue,
          purchasePrice: purchasePrice,
          purchasePriceKnown: _purchasePriceKnown,
          sourceType: _sourceType,
          status: _status,
          paymentAccountId: _paymentAccountId,
          purchaseCategoryId: _purchaseCategoryId,
          brand: _brandCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          warrantyUntil: _warrantyUntil,
          note: _noteCtrl.text.trim(),
          includeInNetWorth: _includeInNetWorth,
          purchaseDate: _purchaseDate,
        );
        await _commitPendingMedia(repo, assetId);
      }
      _mediaCommitted = true;
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickPurchaseDate() async {
    final selected = await showAppDatePicker(
      context,
      initial: _purchaseDate ?? _today(),
      first: DateTime(1970),
      last: _today(),
      title: '购买日期',
    );
    if (selected != null && mounted) {
      setState(() => _purchaseDate = selected);
    }
  }

  Future<void> _pickWarrantyDate() async {
    final first = _purchaseDate ?? DateTime(1970);
    final last = DateTime(_today().year + 30, 12, 31);
    var initial = _warrantyUntil ?? first.add(const Duration(days: 365));
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final selected = await showAppDatePicker(
      context,
      initial: initial,
      first: first,
      last: last,
      title: '保修到期日',
    );
    if (selected != null && mounted) {
      setState(() => _warrantyUntil = selected);
    }
  }

  Widget _buildPhotoField() {
    final scheme = Theme.of(context).colorScheme;
    final existingPath = widget.asset == null
        ? ''
        : widget.asset!.thumbnailPath.isNotEmpty
            ? widget.asset!.thumbnailPath
            : widget.asset!.photoPath;
    final previewPath = _pendingMedia?.thumbnailPath ?? existingPath;
    return Container(
      height: 126,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inputFill(scheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: previewPath.isNotEmpty && File(previewPath).existsSync()
                  ? Image.file(File(previewPath), fit: BoxFit.cover)
                  : ColoredBox(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      child: Icon(
                        _assetIcon(_assetType),
                        color: AppTextColor.secondary(scheme),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              previewPath.isEmpty ? '添加封面照片' : '已选择封面照片',
              style: AppType.secondary(scheme),
            ),
          ),
          Tooltip(
            message: '拍照',
            child: AppCircleButton(
              icon: Icons.photo_camera_outlined,
              onPressed: () => _pickMedia(ImageSource.camera),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '从相册选择',
            child: AppCircleButton(
              icon: Icons.photo_library_outlined,
              onPressed: () => _pickMedia(ImageSource.gallery),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;
    try {
      _mediaStore ??= AssetMediaStore(
        applicationRoot: await getApplicationDocumentsDirectory(),
      );
      final imported = await _mediaStore!.importFile(picked.path);
      if (_pendingMedia != null) {
        await _mediaStore!.deleteFiles(_pendingMedia!);
      }
      if (mounted) setState(() => _pendingMedia = imported);
    } on AssetMediaException catch (error) {
      if (mounted) showAppToast(context, error.message);
    }
  }

  Future<void> _commitPendingMedia(AppRepository repo, int assetId) async {
    final media = _pendingMedia;
    if (media == null) return;
    await repo.updatePhysicalAssetEvidence(
      assetId,
      photoPath: media.originalPath,
      thumbnailPath: media.thumbnailPath,
      invoicePath: widget.asset?.invoicePath ?? '',
      note: '更新物品照片',
    );
    final existing = widget.asset;
    if (existing != null && _mediaStore != null) {
      try {
        await _mediaStore!.deleteFiles(AssetMediaFiles(
          originalPath: existing.photoPath,
          thumbnailPath: existing.thumbnailPath,
        ));
      } on FileSystemException {
        // New media is already committed; orphan cleanup can retry later.
      }
    }
  }
}

class _AssetValueSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const _AssetValueSheet({required this.asset});

  @override
  State<_AssetValueSheet> createState() => _AssetValueSheetState();
}

class _AssetValueSheetState extends State<_AssetValueSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _valuedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.asset.currentValue.toString());
    _noteCtrl = TextEditingController();
    _valuedAt = _today();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _decimalInputValid(_amountCtrl.text, required: true);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '更新当前价值',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              children: [
                AppLabeledField(
                  label: '当前估值',
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(
                      context,
                      prefix: '¥ ',
                      hint: '例如 1800',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '估值日期',
                  helperText: '历史估值会进入时间线，不会覆盖更晚的有效估值。',
                  child: _NullableDateField(
                    fieldKey: const Key('physical-asset-valuation-date'),
                    value: _valuedAt,
                    emptyText: '选择日期',
                    onTap: _pickValuationDate,
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '说明（可选）',
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: iosInputDecoration(context, hint: '例如 二手平台参考价'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<AppRepository>().updatePhysicalAssetValue(
            widget.asset.id,
            _parseDecimalInput(_amountCtrl.text),
            valuedAt: _valuedAt,
            note: _noteCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickValuationDate() async {
    final selected = await showAppDatePicker(
      context,
      initial: _valuedAt,
      first: widget.asset.purchaseDate ?? DateTime(1970),
      last: _today(),
      title: '估值日期',
    );
    if (selected != null && mounted) setState(() => _valuedAt = selected);
  }
}

class _AssetEvidenceSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const _AssetEvidenceSheet({required this.asset});

  @override
  State<_AssetEvidenceSheet> createState() => _AssetEvidenceSheetState();
}

class _AssetEvidenceSheetState extends State<_AssetEvidenceSheet> {
  late final TextEditingController _noteCtrl;
  AssetMediaStore? _mediaStore;
  AssetMediaFiles? _pendingMedia;
  bool _removePhoto = false;
  String? _pendingInvoicePath;
  bool _removeInvoice = false;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    if (!_saved && _pendingMedia != null && _mediaStore != null) {
      unawaited(_mediaStore!.deleteFiles(_pendingMedia!));
    }
    if (!_saved && _pendingInvoicePath != null) {
      unawaited(_deleteManagedInvoiceQuietly(_pendingInvoicePath!));
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewPath = _removePhoto
        ? ''
        : _pendingMedia?.thumbnailPath ??
            (widget.asset.thumbnailPath.isNotEmpty
                ? widget.asset.thumbnailPath
                : widget.asset.photoPath);
    final invoicePath =
        _removeInvoice ? '' : _pendingInvoicePath ?? widget.asset.invoicePath;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '资产凭证',
            subtitle: '照片会保存到 App 受管目录，并生成列表缩略图',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: _saving ? null : _save,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              children: [
                AppLabeledField(
                  label: '物品照片',
                  child: Container(
                    height: 156,
                    decoration: BoxDecoration(
                      color: AppColors.inputFill(scheme),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child:
                        previewPath.isNotEmpty && File(previewPath).existsSync()
                            ? Image.file(File(previewPath), fit: BoxFit.cover)
                            : Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 36,
                                  color: AppTextColor.secondary(scheme),
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: '拍照',
                      child: AppCircleButton(
                        icon: Icons.photo_camera_outlined,
                        onPressed: () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '从相册选择',
                      child: AppCircleButton(
                        icon: Icons.photo_library_outlined,
                        onPressed: () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                    if (previewPath.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '移除照片',
                        child: AppCircleButton(
                          icon: Icons.close,
                          onPressed: _clearPhoto,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                AppLabeledField(
                  label: '发票 / 保修单（可选）',
                  child: SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      SettingsRow(
                        title: invoicePath.isEmpty
                            ? '还没有添加凭证'
                            : path.basename(invoicePath),
                        subtitle: '文件会复制到 App 受管目录',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: '选择文件',
                              child: AppCircleButton(
                                icon: Icons.attach_file,
                                size: 36,
                                iconSize: 18,
                                onPressed: _pickInvoice,
                              ),
                            ),
                            if (invoicePath.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: '移除凭证',
                                child: AppCircleButton(
                                  icon: Icons.close,
                                  size: 36,
                                  iconSize: 18,
                                  onPressed: _clearInvoice,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppLabeledField(
                  label: '说明（可选）',
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: iosInputDecoration(context, hint: '例如保修范围'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().updatePhysicalAssetEvidence(
            widget.asset.id,
            photoPath: _removePhoto
                ? ''
                : _pendingMedia?.originalPath ?? widget.asset.photoPath,
            thumbnailPath: _removePhoto
                ? ''
                : _pendingMedia?.thumbnailPath ?? widget.asset.thumbnailPath,
            invoicePath: _removeInvoice
                ? ''
                : _pendingInvoicePath ?? widget.asset.invoicePath,
            note: _noteCtrl.text,
          );
      _saved = true;
      if ((_pendingMedia != null || _removePhoto) &&
          (widget.asset.photoPath.isNotEmpty ||
              widget.asset.thumbnailPath.isNotEmpty)) {
        try {
          final store = _mediaStore ??= AssetMediaStore(
            applicationRoot: await getApplicationDocumentsDirectory(),
          );
          await store.deleteFiles(AssetMediaFiles(
              originalPath: widget.asset.photoPath,
              thumbnailPath: widget.asset.thumbnailPath));
        } on FileSystemException {
          // The new paths are already committed; orphan cleanup can retry later.
        }
      }
      if ((_removeInvoice || _pendingInvoicePath != null) &&
          widget.asset.invoicePath.isNotEmpty) {
        try {
          await _deleteManagedInvoiceQuietly(widget.asset.invoicePath);
        } on FileSystemException {
          // The database already points at the new state.
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final selected = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
    );
    if (selected == null || !mounted) return;
    try {
      _mediaStore ??= AssetMediaStore(
        applicationRoot: await getApplicationDocumentsDirectory(),
      );
      final imported = await _mediaStore!.importFile(selected.path);
      if (_pendingMedia != null) {
        await _mediaStore!.deleteFiles(_pendingMedia!);
      }
      if (mounted) {
        setState(() {
          _pendingMedia = imported;
          _removePhoto = false;
        });
      }
    } on AssetMediaException catch (error) {
      if (mounted) showAppToast(context, error.message);
    }
  }

  Future<void> _clearPhoto() async {
    if (_pendingMedia != null && _mediaStore != null) {
      await _mediaStore!.deleteFiles(_pendingMedia!);
    }
    if (mounted) {
      setState(() {
        _pendingMedia = null;
        _removePhoto = true;
      });
    }
  }

  Future<void> _pickInvoice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(root.path, 'asset_media'));
    await directory.create(recursive: true);
    final extension = path.extension(sourcePath).toLowerCase();
    final destination = path.join(
      directory.path,
      'asset_invoice_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(sourcePath).copy(destination);
    if (_pendingInvoicePath != null) {
      await _deleteManagedInvoiceQuietly(_pendingInvoicePath!);
    }
    if (mounted) {
      setState(() {
        _pendingInvoicePath = destination;
        _removeInvoice = false;
      });
    }
  }

  Future<void> _clearInvoice() async {
    if (_pendingInvoicePath != null) {
      await _deleteManagedInvoiceQuietly(_pendingInvoicePath!);
    }
    if (mounted) {
      setState(() {
        _pendingInvoicePath = null;
        _removeInvoice = true;
      });
    }
  }
}

class _AssetDepreciationSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const _AssetDepreciationSheet({required this.asset});

  @override
  State<_AssetDepreciationSheet> createState() =>
      _AssetDepreciationSheetState();
}

class _AssetDepreciationSheetState extends State<_AssetDepreciationSheet> {
  late bool _enabled;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _salvageCtrl;
  late final TextEditingController _monthsCtrl;
  late final TextEditingController _noteCtrl;
  DateTime? _startAt;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _enabled = asset.hasLinearDepreciation;
    final defaultBase = asset.depreciationBase > Decimal.zero
        ? asset.depreciationBase
        : asset.purchasePrice > Decimal.zero
            ? asset.purchasePrice
            : asset.currentValue;
    _baseCtrl = TextEditingController(text: defaultBase.toString());
    _salvageCtrl = TextEditingController(text: asset.salvageValue.toString());
    _monthsCtrl = TextEditingController(
      text: asset.usefulLifeMonths > 0 ? asset.usefulLifeMonths.toString() : '',
    );
    _noteCtrl = TextEditingController();
    _startAt = asset.depreciationStartDate ?? asset.purchaseDate;
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _salvageCtrl.dispose();
    _monthsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _valid {
    if (!_enabled) return true;
    if (!_decimalInputValid(_baseCtrl.text, required: true)) return false;
    if (!_decimalInputValid(_salvageCtrl.text, required: true)) return false;
    final base = _parseDecimalInput(_baseCtrl.text);
    final salvage = _parseDecimalInput(_salvageCtrl.text);
    final months = int.tryParse(_monthsCtrl.text.trim()) ?? 0;
    return base > Decimal.zero &&
        salvage >= Decimal.zero &&
        salvage <= base &&
        months > 0 &&
        _startAt != null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '折旧设置',
            subtitle: '手动更新当前价值会暂停自动折旧，重新保存折旧设置后恢复。',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: _valid ? _save : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              children: [
                SettingsGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    SettingsRow(
                      title: '线性折旧',
                      subtitle: '按完整月份把价值降到残值，不写入普通收支',
                      trailing: AppSwitch(
                        value: _enabled,
                        onChanged: (value) => setState(() => _enabled = value),
                      ),
                    ),
                  ],
                ),
                if (_enabled) ...[
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '折旧基准金额',
                    child: TextField(
                      controller: _baseCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(context, prefix: '¥ '),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '预计残值',
                    child: TextField(
                      controller: _salvageCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(context, prefix: '¥ '),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '使用寿命（月）',
                    child: TextField(
                      controller: _monthsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: iosInputDecoration(context, hint: '例如 36'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '折旧开始日期',
                    helperText:
                        _startAt == null ? '购买日期未知，请明确选择折旧从哪一天开始。' : null,
                    child: _NullableDateField(
                      fieldKey:
                          const Key('physical-asset-depreciation-start-date'),
                      value: _startAt,
                      emptyText: '请选择开始日期',
                      onTap: _pickStartDate,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '说明（可选）',
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: iosInputDecoration(context, hint: '例如 按三年折旧'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await context.read<AppRepository>().configurePhysicalAssetDepreciation(
          id: widget.asset.id,
          enabled: _enabled,
          depreciationBase: _parseDecimalInput(_baseCtrl.text),
          salvageValue: _parseDecimalInput(_salvageCtrl.text),
          usefulLifeMonths: int.tryParse(_monthsCtrl.text.trim()) ?? 0,
          startAt: _startAt,
          note: _noteCtrl.text.trim(),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickStartDate() async {
    final first = widget.asset.purchaseDate ?? DateTime(1970);
    var initial = _startAt ?? widget.asset.purchaseDate ?? _today();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(_today())) initial = _today();
    final selected = await showAppDatePicker(
      context,
      initial: initial,
      first: first,
      last: _today(),
      title: '折旧开始日期',
    );
    if (selected != null && mounted) setState(() => _startAt = selected);
  }
}

class _AssetSellSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const _AssetSellSheet({required this.asset});

  @override
  State<_AssetSellSheet> createState() => _AssetSellSheetState();
}

class _AssetSellSheetState extends State<_AssetSellSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _noteCtrl;
  int? _accountId;
  DateTime _soldAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _feeCtrl = TextEditingController(text: '0');
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    _accountId ??= repo.accounts.firstOrNull?.id;
    final amount = _parseDecimalInput(_amountCtrl.text);
    final fee = _parseDecimalInput(_feeCtrl.text);
    final valid = _decimalInputValid(_amountCtrl.text, required: true) &&
        _decimalInputValid(_feeCtrl.text, required: true) &&
        amount >= Decimal.zero &&
        fee >= Decimal.zero &&
        fee <= amount;
    final net = amount - fee;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '出售资产',
            subtitle: '出售入账只影响账户余额，不进入普通收入统计。',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              children: [
                AppLabeledField(
                  label: '成交价',
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(context,
                        prefix: '¥ ', hint: '实际成交金额'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                AppLabeledField(
                  label: '出售费用',
                  helperText: '平台手续费、运费等；不会另记普通支出',
                  child: TextField(
                    controller: _feeCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(context, prefix: '¥ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                _DetailSection(
                  title: '结算',
                  children: [
                    _DetailRow(
                      label: '净到账',
                      value: MoneyFormat.string(net),
                    ),
                    _DetailRow(
                      label: '成交日期',
                      value: _dateText(_soldAt),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _AssetActionButton(
                  label: '选择成交日期',
                  icon: Icons.event_outlined,
                  onTap: _pickSoldAt,
                ),
                const SizedBox(height: 12),
                _AccountDropdown(
                  value: _accountId,
                  accounts: repo.accounts,
                  hint: '收款账户',
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '备注（可选）'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<AppRepository>().sellPhysicalAsset(
            id: widget.asset.id,
            saleAmount: _parseDecimalInput(_amountCtrl.text),
            saleFee: _parseDecimalInput(_feeCtrl.text),
            accountId: _accountId,
            soldAt: _soldAt,
            note: _noteCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickSoldAt() async {
    final selected = await showAppDatePicker(
      context,
      initial: _soldAt,
      first: widget.asset.purchaseDate,
      last: DateTime.now(),
      title: '成交日期',
    );
    if (selected != null && mounted) setState(() => _soldAt = selected);
  }
}

Future<void> _returnPhysicalAssetFromDetail(
  BuildContext context,
  AppRepository repo,
  PhysicalAssetEntity asset,
) async {
  var cost = repo.physicalAssetAcquisitionCost(asset.id);
  if (!cost.isExact) {
    showAppToast(context, '这件物品的退款分配待确认，暂不能确认退货');
    return;
  }
  if (cost.amount == Decimal.zero) {
    await _confirmPhysicalAssetReturned(context, repo, asset, DateTime.now());
    return;
  }
  final links = repo
      .transactionLinksForAsset(asset.id)
      .where((link) =>
          link.linkType == AssetTransactionLinkType.sourceTransaction ||
          link.linkType == AssetTransactionLinkType.purchaseTransaction)
      .toList();
  if (links.length != 1) {
    showAppToast(context, '这件物品关联了多笔购买账单，请先分别完成退款');
    return;
  }
  final original = repo.visibleTransactions
      .where((transaction) => transaction.id == links.single.transactionId)
      .firstOrNull;
  if (original == null) {
    showAppToast(context, '原购买账单已不可用，暂不能发起退货');
    return;
  }
  await showRefundSheet(context, original);
  if (!context.mounted) return;
  cost = repo.physicalAssetAcquisitionCost(asset.id);
  if (!cost.isExact || cost.amount != Decimal.zero) {
    showAppToast(context, '退款已记录；净购置成本归零后才能确认退货');
    return;
  }
  final settledDates = repo
      .refundsOf(original.id)
      .map((refund) => refund.settledAt)
      .whereType<DateTime>()
      .toList()
    ..sort();
  await _confirmPhysicalAssetReturned(
    context,
    repo,
    asset,
    settledDates.isEmpty ? DateTime.now() : settledDates.last,
  );
}

Future<void> _confirmPhysicalAssetReturned(
  BuildContext context,
  AppRepository repo,
  PhysicalAssetEntity asset,
  DateTime returnedAt,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: '确认退货完成',
    message: '物品当前估值会归零并结束持有；退款仍附着在原购买账单。',
    confirmText: '确认退货',
  );
  if (!confirmed) return;
  await repo.returnPhysicalAsset(
    assetId: asset.id,
    returnedAt: returnedAt,
  );
  if (!context.mounted) return;
  showAppToast(context, '已确认「${asset.name}」退货');
  Navigator.pop(context);
}

Future<void> _undoPhysicalAssetReturnFromDetail(
  BuildContext context,
  AppRepository repo,
  PhysicalAssetEntity asset,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: '撤销退货状态',
    message: '物品会恢复退货前的状态和估值，原账单退款不会撤销。',
    confirmText: '撤销',
  );
  if (!confirmed) return;
  await repo.undoPhysicalAssetReturn(asset.id);
  if (context.mounted) Navigator.pop(context);
}

class _EnumDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final String hint;
  final ValueChanged<T> onChanged;

  const _EnumDropdown({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _IosPickerField(
      key: ValueKey(value),
      text: labelOf(value),
      hint: hint,
      onTapMenu: (menuCtx) => _showPickerMenu(
        menuCtx,
        [
          for (final item in values)
            IosMenuItem(
              label: labelOf(item),
              icon: Icons.tune_rounded,
              selected: item == value,
              onTap: () => onChanged(item),
            ),
        ],
      ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final int? value;
  final List<AccountEntity> accounts;
  final String hint;
  final ValueChanged<int?> onChanged;

  const _AccountDropdown({
    required this.value,
    required this.accounts,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        accounts.where((account) => account.id == value).firstOrNull;
    return _IosPickerField(
      key: ValueKey(value),
      text: selected?.name,
      hint: hint,
      onTapMenu: (menuCtx) => _showPickerMenu(
        menuCtx,
        [
          for (final account in accounts)
            IosMenuItem(
              label: account.name,
              icon: Icons.account_balance_wallet_outlined,
              selected: account.id == value,
              onTap: () => onChanged(account.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final int? value;
  final List<CategoryEntity> categories;
  final String hint;
  final ValueChanged<int?> onChanged;

  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        categories.where((category) => category.id == value).firstOrNull;
    return _IosPickerField(
      key: ValueKey(value),
      text: selected?.nameZh,
      hint: hint,
      onTapMenu: (menuCtx) => _showPickerMenu(
        menuCtx,
        [
          for (final category in categories)
            IosMenuItem(
              label: category.nameZh,
              icon: Icons.category_outlined,
              selected: category.id == value,
              onTap: () => onChanged(category.id),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyValueField extends StatelessWidget {
  final String text;
  final IconData icon;

  const _ReadOnlyValueField({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.inputFill(scheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTextColor.secondary(scheme)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppType.body(scheme))),
        ],
      ),
    );
  }
}

class _NullableDateField extends StatelessWidget {
  final Key fieldKey;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _NullableDateField({
    required this.fieldKey,
    required this.value,
    required this.emptyText,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _IosPickerField(
            key: fieldKey,
            text: value == null ? null : _dateText(value),
            hint: emptyText,
            onTapMenu: (_) => onTap(),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: '清除日期',
            child: AppCircleButton(
              icon: Icons.close,
              size: 38,
              iconSize: 18,
              onPressed: onClear,
            ),
          ),
        ],
      ],
    );
  }
}

class _IosPickerField extends StatelessWidget {
  final String? text;
  final String hint;
  final void Function(BuildContext menuContext) onTapMenu;

  const _IosPickerField({
    super.key,
    required this.text,
    required this.hint,
    required this.onTapMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = text != null && text!.trim().isNotEmpty;
    return Builder(
      builder: (menuCtx) => PressableScale(
        onPressed: () => onTapMenu(menuCtx),
        pressedScale: 0.985,
        pressedOpacity: 0.92,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.inputFill(scheme),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasText ? text! : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: hasText
                        ? AppTextColor.primary(scheme)
                        : AppTextColor.hint(scheme),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppTextColor.secondary(scheme),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showPickerMenu(BuildContext menuCtx, List<IosMenuItem> items) {
  if (items.isEmpty) return;
  showIosMenu(
    menuCtx,
    items,
    width: _pickerMenuWidth(menuCtx),
    alignToAnchorLeft: true,
  );
}

double _pickerMenuWidth(BuildContext context) {
  final screenMax = MediaQuery.sizeOf(context).width - 16;
  final renderObject = context.findRenderObject();
  final fieldWidth =
      renderObject is RenderBox ? renderObject.size.width : 260.0;
  final minWidth = fieldWidth < 220.0 ? 220.0 : fieldWidth;
  return minWidth > screenMax ? screenMax : minWidth;
}

class _HintBox extends StatelessWidget {
  final String text;
  const _HintBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppType.secondary(scheme),
      ),
    );
  }
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
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: iosInputDecoration(context, hint: '账户名称'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _AccountTypePicker(
                      value: _type,
                      onChanged: (next) => setState(() {
                        _type = next;
                        if (next == AccountType.credit) {
                          _liabilityType = LiabilityProfileType.creditCard;
                        } else if (next == AccountType.loan &&
                            _liabilityType == LiabilityProfileType.creditCard) {
                          _liabilityType = LiabilityProfileType.other;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _currencyCtrl,
                      readOnly: true,
                      decoration: iosInputDecoration(
                        context,
                        hint: _currencyCtrl.text == 'CNY'
                            ? '人民币 CNY'
                            : '${_currencyCtrl.text}（仅保留，不计入净资产）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
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
                        hint: _type.liability ? '当前欠款（可填负数）' : '期初余额',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_editing) ...[
                      const SizedBox(height: 5),
                      Text(
                        '期初余额用于建立账户起点，修改当前余额请在账户详情选择“校准余额”。',
                        style: AppType.caption(Theme.of(context).colorScheme),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _institutionCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          iosInputDecoration(context, hint: '机构/银行（可选）'),
                    ),
                    const SizedBox(height: 14),
                    _SwitchRow(
                      title: '计入净资产',
                      subtitle: '关闭后仍显示账户，但不计入顶部合计',
                      value: _includeInNetWorth,
                      onChanged: (value) =>
                          setState(() => _includeInNetWorth = value),
                    ),
                    if (_type.liability) ...[
                      const SizedBox(height: 14),
                      _DetailSection(
                        title: '负债详情',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _EnumDropdown<LiabilityProfileType>(
                                  value: _liabilityType,
                                  values: LiabilityProfileType.values,
                                  labelOf: (value) => value.label,
                                  hint: '负债类型',
                                  onChanged: (value) =>
                                      setState(() => _liabilityType = value),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _liabilityOriginalCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: moneyInputFormatters(),
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '原始金额（可选）',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _liabilityPrincipalCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters:
                                      moneyInputFormatters(allowNegative: true),
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '剩余本金/当前欠款（可选）',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _liabilityRateCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '年化利率 %（可选）',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _repaymentDayCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '每月还款日 1-31（可选）',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 10),
                                _AccountDropdown(
                                  value: _repaymentAccountId,
                                  accounts: repo.accounts
                                      .where((a) => a.id != widget.account?.id)
                                      .toList(),
                                  hint: '默认还款账户（可选）',
                                  onChanged: (value) => setState(
                                      () => _repaymentAccountId = value),
                                ),
                                const SizedBox(height: 10),
                                _EnumDropdown<LiabilityProfileStatus>(
                                  value: _liabilityStatus,
                                  values: LiabilityProfileStatus.values,
                                  labelOf: (value) => value.label,
                                  hint: '负债状态',
                                  onChanged: (value) =>
                                      setState(() => _liabilityStatus = value),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _liabilityNoteCtrl,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration:
                                      iosInputDecoration(context, hint: '负债备注'),
                                ),
                                if (!_liabilityInputValid) ...[
                                  const SizedBox(height: 10),
                                  const _HintBox(
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.onSurface.withValues(alpha: 0.08)
              : AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? scheme.onSurface.withValues(alpha: 0.48)
                : AppColors.hairline(scheme),
          ),
        ),
        child: Text(
          type.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: selected
                    ? AppTextColor.primary(scheme)
                    : AppTextColor.secondary(scheme),
              ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppType.secondary(scheme),
                ),
              ],
            ),
          ),
          AppSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
