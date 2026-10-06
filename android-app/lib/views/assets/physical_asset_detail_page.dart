// 物品资产详情页与退货/撤销流程（从 accounts_view.dart 拆出）。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_allocation.dart';
import '../../core/assets/asset_metrics.dart';
import '../../core/app_clock.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/transaction_actions.dart';
import '../common/app_sheet.dart';
import 'asset_form_kit.dart';
import 'physical_asset_cost_link_sheet.dart';
import 'physical_asset_form_sheet.dart';
import 'physical_asset_grid.dart';
import 'physical_asset_refund_allocation_sheet.dart';
import 'physical_asset_sheets.dart';

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
    asOf: AppClock.now,
  );
}

String _detailDateText(DateTime? date) =>
    date == null ? '未填写' : '${date.year}年${date.month}月${date.day}日';

File? _assetPhotoFile(PhysicalAssetEntity asset) {
  for (final source in [asset.photoPath.trim(), asset.thumbnailPath.trim()]) {
    if (source.isNotEmpty) {
      final file = File(source);
      if (file.existsSync()) return file;
    }
  }
  return null;
}

String _detailAmountNumber(Decimal amount, String currencyCode) {
  final symbol = currencyCode == 'CNY' ? '¥' : MoneyFormat.symbol(currencyCode);
  return MoneyFormat.string(amount, currencyCode: currencyCode)
      .replaceFirst(symbol, '')
      .trim();
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

class PhysicalAssetDetailPage extends StatelessWidget {
  final int assetId;
  final PhysicalAssetEntity fallbackAsset;

  const PhysicalAssetDetailPage({
    super.key,
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
      asOf: AppClock.now,
    );
    final recentValuations = valuationTrend.points.reversed.take(4).toList();
    final hasKnownValuation = valuationTrend.points.isNotEmpty;
    final cost = repo.physicalAssetAcquisitionCost(current.id);
    final additional = repo.physicalAssetAdditionalCost(current.id);
    final usage = repo.physicalAssetUsage(current.id);
    final warrantyReminder =
        repo.warrantyReminderForAsset(current, asOf: AppClock.now);
    final savingsGoal = current.savingsGoalId == null
        ? null
        : repo.savingsGoalById(current.savingsGoalId!);
    final costLabel = current.acquisitionCostSource ==
            AssetAcquisitionCostSource.transactionAllocations
        ? '净购置成本'
        : '购买成本';
    final costText = cost.amount == null
        ? '待确认'
        : '${MoneyFormat.string(
            cost.amount!,
            currencyCode: current.currencyCode,
          )}${cost.isExact ? '' : ' · 待确认'}';
    final metrics = _resolveMetrics(repo, current, cost);
    final owned = current.economicStatus == PhysicalAssetEconomicStatus.owned;
    final saleLinks = links
        .where(
          (l) => l.linkType == AssetTransactionLinkType.saleAccountMovement,
        )
        .toList();
    final saleProceeds = saleLinks.fold(
      Decimal.zero,
      (sum, l) => sum + repo.physicalAssetLinkCurrentAmount(l),
    );
    final hasFullInvestment = cost.isExact &&
        additional.isExact &&
        metrics.cumulativeHoldingInvestment.isExact;
    final investmentAmount =
        hasFullInvestment ? metrics.cumulativeHoldingInvestment.value! : null;
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
        : '${assetReminderDetailText(
            warrantyReminder,
            upcomingLabel: '剩',
            dueTodayLabel: '今天到期',
            expiredLabel: '已过期',
            inactiveLabel: '已结束持有',
          )} · 至${_detailDateText(current.warrantyUntil)}';
    final dailyAvailable =
        cost.isExact && additional.isExact && metrics.dailyHoldingCost.isExact;
    final primaryMetric = dailyAvailable
        ? MoneyFormat.string(metrics.dailyHoldingCost.value!,
            currencyCode: current.currencyCode)
        : '暂不可计算';
    final primaryCaption = dailyAvailable
        ? '${owned ? '已持有' : '持有'} $heldText · ${current.purchaseDate == null ? '购买日期未填写' : '${_detailDateText(current.purchaseDate)}购入'}'
        : '$heldText · ${holdingCostReason(metrics.dailyHoldingCost.reason)}';
    final photo = _assetPhotoFile(current);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('物品详情'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Builder(
              builder: (menuContext) => AppCircleButton(
                icon: Icons.more_horiz,
                semanticLabel: '更多物品操作',
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
          _DetailCard(
            key: const Key('physical-asset-summary-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo != null) ...[
                  _PhysicalAssetHero(
                    asset: current,
                    file: photo,
                    onPressed: () => _showEvidenceSheet(context, current),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    if (photo == null) ...[
                      _PhysicalAssetHeroPlaceholder(
                        asset: current,
                        onPressed: () => _showEvidenceSheet(context, current),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(current.name,
                              style: AppType.rowTitle(scheme).copyWith(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _InfoPill(current.assetType.label),
                              _InfoPill(_physicalAssetStatusLabel(current),
                                  emphasized: owned),
                              _InfoPill(current.countsInNetWorth
                                  ? '计入净资产'
                                  : '不计入净资产'),
                              if (current.inclusionQuality ==
                                  AssetInclusionQuality.needsReview)
                                const _InfoPill('待确认'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('日均持有花费', style: AppType.secondary(scheme)),
                const SizedBox(height: 4),
                _DailyHoldingAmount(
                    amount: primaryMetric, available: dailyAvailable),
                const SizedBox(height: 4),
                Text(primaryCaption, style: AppType.secondary(scheme)),
                const SizedBox(height: 14),
                _AssetMetricStrip(
                  value: hasKnownValuation
                      ? _detailAmountNumber(
                          current.currentValue, current.currencyCode)
                      : '待确认',
                  valueCaption: recentValuations.isEmpty
                      ? '估值未填写'
                      : '${recentValuations.first.effectiveAt.month}月${recentValuations.first.effectiveAt.day}日估',
                  retention: cost.isExact && metrics.valueRetentionRatio.isExact
                      ? retentionText
                      : '不可计算',
                  retentionCaption:
                      cost.isExact && metrics.valueRetentionRatio.isExact
                          ? '估值 ÷ 成本'
                          : cost.isExact
                              ? metrics.valueRetentionRatio.reason
                              : cost.reason,
                  costLabel: costLabel,
                  cost: cost.amount == null
                      ? '待确认'
                      : _detailAmountNumber(cost.amount!, current.currencyCode),
                  costCaption: !cost.isExact
                      ? cost.reason
                      : current.acquisitionCostSource ==
                              AssetAcquisitionCostSource.transactionAllocations
                          ? '已关联账单'
                          : '手动填写',
                  currencyCode: current.currencyCode,
                ),
                const SizedBox(height: 14),
                _DetailActions(
                  onValue:
                      owned ? () => _showValueSheet(context, current) : null,
                  onLink: owned
                      ? () => _showCostLinkSheet(context, repo, current)
                      : null,
                  menuBuilder: (menuContext) =>
                      _showMoreMenu(menuContext, context, repo, current),
                ),
              ],
            ),
          ),
          // D1b: 卖出盈亏复盘卡
          if (!owned && saleLinks.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SellPnLCard(
              currencyCode: current.currencyCode,
              saleProceeds: saleProceeds,
              investment: investmentAmount,
            ),
          ],
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
                            child: PhysicalAssetFormSheet(asset: current),
                          )
                      : null,
                ),
              ],
            ),
          ],
          if (current.warrantyUntil != null) ...[
            const SizedBox(height: 12),
            _WarrantyCard(asset: current, description: warrantyText),
          ],
          const SizedBox(height: 12),
          _DetailSection(
            title: '资料',
            children: [
              _DetailRow(label: '类型', value: current.assetType.label),
              _DetailRow(label: '来源', value: current.sourceType.label),
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
          if (current.hasLinearDepreciation) ...[
            const SizedBox(height: 12),
            _DetailCard(
              child: _ServiceProgressBar(asset: current, metrics: metrics),
            ),
          ],
          const SizedBox(height: 12),
          AssetDetailSection(
            title: '持有指标',
            children: [
              AssetDetailRow(label: '日均持有花费', value: dailyText),
              AssetDetailRow(label: '持有天数', value: heldText),
              AssetDetailRow(
                label: '当前估值',
                value: hasKnownValuation
                    ? MoneyFormat.string(
                        current.currentValue,
                        currencyCode: current.currencyCode,
                      )
                    : '待确认',
              ),
              AssetDetailRow(label: '累计持有投入', value: cumulativeText),
              AssetDetailRow(label: '后续支出', value: additionalText),
              if (current.usageTrackingEnabled) ...[
                AssetDetailRow(
                  label: '累计使用',
                  value:
                      '${usage.totalCount} 次${usage.isExact ? '' : ' · 待确认'}',
                ),
                AssetDetailRow(label: '每次使用成本', value: perUseText),
              ],
              AssetDetailRow(label: '保值率', value: retentionText),
              if (current.endedAt != null)
                AssetDetailRow(
                  label: '结束日期',
                  value: _detailDateText(current.endedAt),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentValuations.isNotEmpty) ...[
            AssetDetailSection(
              title: '估值记录',
              children: [
                for (final point in recentValuations)
                  AssetDetailRow(
                    label: _detailDateText(point.effectiveAt),
                    value: MoneyFormat.string(
                      point.value,
                      currencyCode: current.currencyCode,
                    ),
                  ),
                if (valuationTrend.ignoredFutureCount > 0 ||
                    valuationTrend.ignoredAfterTerminationCount > 0)
                  AssetDetailRow(
                    label: '未参与当前估值',
                    value:
                        '${valuationTrend.ignoredFutureCount + valuationTrend.ignoredAfterTerminationCount} 条',
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          AssetDetailSection(
            title: '资产信息',
            children: [
              AssetDetailRow(label: '来源', value: current.sourceType.label),
              AssetDetailRow(
                label: costLabel,
                value: costText,
              ),
              AssetDetailRow(
                label: '购买日期',
                value: _detailDateText(current.purchaseDate),
              ),
              AssetDetailRow(label: '保修', value: warrantyText),
            ],
          ),
          const SizedBox(height: 12),
          AssetDetailSection(
            title: '凭证与折旧',
            children: [
              AssetDetailRow(
                label: '照片',
                value: current.photoPath.isEmpty ? '未添加' : '已添加',
              ),
              AssetDetailRow(
                label: '发票',
                value: current.invoicePath.isEmpty ? '未添加' : '已添加',
              ),
              AssetDetailRow(
                label: '折旧',
                value: current.hasLinearDepreciation
                    ? '线性折旧 · ${current.usefulLifeMonths} 个月${current.depreciationPaused ? ' · 已暂停' : ''}'
                    : '未开启',
              ),
              if (current.hasLinearDepreciation)
                AssetDetailRow(
                  label: '残值',
                  value: MoneyFormat.string(current.salvageValue),
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
                  title: '确认状态与是否计入',
                  subtitle: '确认后不再提醒',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showReviewSheet(context, current),
                ),
            ],
          ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 12),
            AssetDetailSection(
              title: '账单关联',
              children: [
                for (final link in links.take(4))
                  AssetDetailRow(
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
              AssetActionButton(
                label: '解除${link.linkType.label}关联',
                icon: Icons.link_off_outlined,
                onTap: () => _unlinkTransaction(context, repo, link),
              ),
            ],
          ],
          const SizedBox(height: 12),
          AssetDetailSection(
            title: '最近事件',
            children: events.isEmpty
                ? const [
                    AssetDetailRow(label: '暂无', value: '还没有资产事件'),
                  ]
                : [
                    for (final event in events)
                      AssetDetailRow(
                        label: event.eventType.label,
                        value:
                            '${_detailDateText(event.occurredAt)}${event.value == null ? '' : ' · ${MoneyFormat.string(event.value!)}'}',
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  /// 一级 ⋯ 菜单：只放高频操作，低频的终止/撤销类收进「更多操作…」二级菜单。
  void _showMoreMenu(
    BuildContext menuContext,
    BuildContext pageContext,
    AppRepository repo,
    PhysicalAssetEntity asset,
  ) {
    final owned = asset.economicStatus == PhysicalAssetEconomicStatus.owned;
    showIosMenu(
      menuContext,
      [
        if (owned)
          IosMenuItem(
            label: '编辑资料',
            icon: Icons.edit_outlined,
            onTap: () => showBlurSheet<void>(
              pageContext,
              child: PhysicalAssetFormSheet(asset: asset),
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
        IosMenuItem(
          label: '更多操作…',
          icon: Icons.more_horiz,
          onTap: () => _showMoreActionsMenu(
            menuContext,
            pageContext,
            repo,
            asset,
          ),
        ),
      ],
    );
  }

  /// 二级「更多操作…」菜单：退货、报废、丢失、赠送等终止类和归档操作。
  void _showMoreActionsMenu(
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
      child: AssetValueSheet(asset: asset),
    );
  }

  void _showSellSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: AssetSellSheet(asset: asset),
    );
  }

  void _showEvidenceSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: AssetEvidenceSheet(asset: asset),
    );
  }

  void _showDepreciationSheet(BuildContext context, PhysicalAssetEntity asset) {
    showBlurSheet<void>(
      context,
      child: AssetDepreciationSheet(asset: asset),
    );
  }

  void _showReviewSheet(
    BuildContext context,
    PhysicalAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: PhysicalAssetReviewSheet(asset: asset),
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
      child: PhysicalAssetTerminalSheet(
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

class _PhysicalAssetHero extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final File file;
  final VoidCallback onPressed;

  const _PhysicalAssetHero(
      {required this.asset, required this.file, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      button: true,
      label: '${asset.name}的物品照片',
      child: PressableScale(
        onPressed: onPressed,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Center(
                child: _PhysicalAssetHeroPlaceholder(
                    asset: asset, onPressed: onPressed),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhysicalAssetHeroPlaceholder extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final VoidCallback onPressed;

  const _PhysicalAssetHeroPlaceholder(
      {required this.asset, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '添加照片',
      child: PressableScale(
        onPressed: onPressed,
        child: CustomPaint(
          painter: _PhotoPlaceholderBorder(
              color: scheme.onSurface.withValues(alpha: 0.22)),
          child: SizedBox(
            key: const Key('physical-asset-photo-placeholder'),
            width: 68,
            height: 68,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(assetTypeIcon(asset.assetType),
                    size: 24, color: AppTextColor.hint(scheme)),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('添加照片',
                      style: AppType.caption(scheme).copyWith(fontSize: 10.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String text;
  final bool emphasized;
  const _InfoPill(this.text, {this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primary.withValues(alpha: 0.14)
            : AppColors.iconCircleFill(scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppType.secondary(scheme).copyWith(
          fontSize: 11.5,
          color: emphasized ? scheme.primary : AppTextColor.secondary(scheme),
        ),
      ),
    );
  }
}

class _PhotoPlaceholderBorder extends CustomPainter {
  final Color color;
  const _PhotoPlaceholderBorder({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.6), const Radius.circular(18)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 8) {
        canvas.drawPath(
            metric.extractPath(offset, math.min(offset + 5, metric.length)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PhotoPlaceholderBorder oldDelegate) =>
      color != oldDelegate.color;
}

class _DetailCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _DetailCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline(scheme), width: 0.5),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _DailyHoldingAmount extends StatelessWidget {
  final String amount;
  final bool available;
  const _DailyHoldingAmount({required this.amount, required this.available});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Text.rich(
        key: const Key('physical-asset-primary-metric'),
        TextSpan(children: [
          TextSpan(text: amount),
          if (available)
            TextSpan(
              text: ' /天',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTextColor.secondary(scheme),
              ),
            ),
        ]),
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'AssetAmount',
          fontSize: available ? 40 : 24,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: 0,
          color: scheme.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _AssetMetricStrip extends StatelessWidget {
  final String value;
  final String valueCaption;
  final String retention;
  final String retentionCaption;
  final String costLabel;
  final String cost;
  final String costCaption;
  final String currencyCode;

  const _AssetMetricStrip({
    required this.value,
    required this.valueCaption,
    required this.retention,
    required this.retentionCaption,
    required this.costLabel,
    required this.cost,
    required this.costCaption,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      ('当前估值', value, valueCaption),
      ('保值率', retention, retentionCaption),
      (costLabel, cost, costCaption),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 270 ||
          MediaQuery.textScalerOf(context).scale(15.5) > 22;
      Widget tile((String, String, String) item) => Semantics(
            label: '${item.$1} ${item.$2}'
                '${item.$1 == '保值率' ? '' : ' $currencyCode'}，${item.$3}',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.iconCircleFill(scheme),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$1,
                        style:
                            AppType.secondary(scheme).copyWith(fontSize: 11.5)),
                    const SizedBox(height: 3),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(item.$2,
                          style: TextStyle(
                            fontFamily: 'AssetAmount',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                    const SizedBox(height: 1),
                    Text(item.$3,
                        style: AppType.caption(scheme).copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
          );
      if (stacked) {
        return Column(
          key: const Key('physical-asset-metrics-stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              tile(items[i]),
            ],
          ],
        );
      }
      return Row(
        key: const Key('physical-asset-metrics-three-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: tile(items[i])),
          ],
        ],
      );
    });
  }
}

class _DetailActions extends StatelessWidget {
  final VoidCallback? onValue;
  final VoidCallback? onLink;
  final ValueChanged<BuildContext> menuBuilder;
  const _DetailActions(
      {required this.onValue, required this.onLink, required this.menuBuilder});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context);
    final height = math.max(40.0, scale.scale(15.5) * 1.3 + 12);
    Widget button(bool primary, double width) => AppPillButton(
          label: primary ? '更新估值' : '关联支出',
          onPressed: primary ? onValue : onLink,
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          fillColor:
              primary ? scheme.primary : AppColors.iconCircleFill(scheme),
          foregroundColor: primary ? scheme.onPrimary : scheme.onSurface,
        );
    final menu = Builder(
      builder: (anchor) => AppCircleButton(
        icon: CupertinoIcons.ellipsis,
        semanticLabel: '更多操作',
        size: 40,
        expandHitTarget: false,
        onPressed: () => menuBuilder(anchor),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (scale.scale(15.5) > 22 || constraints.maxWidth < 270) {
        return Column(children: [
          button(true, constraints.maxWidth),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: button(false, constraints.maxWidth - 48)),
            const SizedBox(width: 8),
            menu,
          ]),
        ]);
      }
      final width = (constraints.maxWidth - 56) / 2;
      return Row(children: [
        Expanded(child: button(true, width)),
        const SizedBox(width: 8),
        Expanded(child: button(false, width)),
        const SizedBox(width: 8),
        menu,
      ]);
    });
  }
}

class _WarrantyCard extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final String description;
  const _WarrantyCard({required this.asset, required this.description});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final purchase = asset.purchaseDate;
    final end = asset.warrantyUntil!;
    final total = purchase == null
        ? 0
        : assetCalendarDay(end).difference(assetCalendarDay(purchase)).inDays;
    final passed = purchase == null
        ? 0
        : assetCalendarDay(AppClock.now)
            .difference(assetCalendarDay(purchase))
            .inDays;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text('保修',
                  style: AppType.rowTitle(scheme).copyWith(fontSize: 15)),
              Text(description, style: AppType.secondary(scheme)),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (passed / total).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: scheme.primary.withValues(alpha: 0.16),
                color: scheme.primary,
              ),
            ),
          ],
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
          child: Text(title,
              style: AppType.secondary(Theme.of(context).colorScheme)),
        ),
        _DetailCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.hairline(Theme.of(context).colorScheme)),
              children[i],
            ],
          ]),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppType.secondary(scheme).copyWith(fontSize: 14.5)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppType.body(scheme).copyWith(fontSize: 14.5)),
          ),
        ],
      ),
    );
  }
}

/// D1a 服役进度条：有线性折旧（usefulLifeMonths > 0）或保修区间时显示。
class _ServiceProgressBar extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final PhysicalAssetMetrics metrics;

  const _ServiceProgressBar({
    required this.asset,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final heldDays = metrics.heldDays.isExact ? metrics.heldDays.value! : null;
    if (heldDays == null) return const SizedBox.shrink();

    int lifespanDays;
    String lifespanLabel;

    if (asset.hasLinearDepreciation && asset.usefulLifeMonths > 0) {
      lifespanDays = (asset.usefulLifeMonths * 30.44).round();
      lifespanLabel = '预计 ${asset.usefulLifeMonths} 个月';
    } else if (asset.warrantyUntil != null && asset.purchaseDate != null) {
      lifespanDays =
          asset.warrantyUntil!.difference(asset.purchaseDate!).inDays;
      lifespanLabel = '保修至 ${_detailDateText(asset.warrantyUntil)}';
    } else {
      return const SizedBox.shrink();
    }

    if (lifespanDays <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final ratio = (heldDays / lifespanDays).clamp(0.0, 1.0);
    // 文字与进度条用同一个舍入后的值，避免「显示 100% 但条子没满」的割裂。
    final displayRatio = ((ratio * 100).round() / 100.0).clamp(0.0, 1.0);
    final pct = (displayRatio * 100).toInt();
    final exceeds = heldDays > lifespanDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '服役 $pct%${exceeds ? ' · 已超期' : ''}',
                style: AppType.secondary(scheme),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(lifespanLabel, style: AppType.caption(scheme)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: displayRatio,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              exceeds ? kOverspendOrange : scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// D1b 卖出盈亏复盘卡：已出售物品且有出售到账关联时显示。
class _SellPnLCard extends StatelessWidget {
  final String currencyCode;
  final Decimal saleProceeds;
  final Decimal? investment;

  const _SellPnLCard({
    required this.currencyCode,
    required this.saleProceeds,
    required this.investment,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pnl = investment != null ? saleProceeds - investment! : null;
    final profit = pnl != null && pnl >= Decimal.zero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.iconCircleFill(scheme),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('卖出复盘', style: AppType.rowTitle(scheme)),
                const SizedBox(height: 6),
                _PnLRow(
                  label: '累计投入',
                  value: investment != null
                      ? MoneyFormat.string(investment!,
                          currencyCode: currencyCode)
                      : '待确认',
                  scheme: scheme,
                ),
                _PnLRow(
                  label: '出售到账',
                  value: MoneyFormat.string(saleProceeds,
                      currencyCode: currencyCode),
                  scheme: scheme,
                ),
              ],
            ),
          ),
          if (pnl != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(profit ? '盈利' : '亏损', style: AppType.caption(scheme)),
                const SizedBox(height: 2),
                Text(
                  '${profit ? '+' : ''}${MoneyFormat.string(pnl, currencyCode: currencyCode)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        color: profit
                            ? AppColors.income(scheme)
                            : AppColors.warning,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PnLRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;

  const _PnLRow({
    required this.label,
    required this.value,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('$label ', style: AppType.caption(scheme)),
          Text(value, style: AppType.secondary(scheme)),
        ],
      ),
    );
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
