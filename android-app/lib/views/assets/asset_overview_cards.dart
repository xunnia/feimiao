// 资产总览页卡片，从 accounts_view.dart 拆出。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';

class AssetEmptyState extends StatelessWidget {
  const AssetEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Mascot(mood: MascotMood.empty, size: 96));
  }
}

class AssetPendingItem {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const AssetPendingItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });
}

class AssetPendingCard extends StatelessWidget {
  final List<AssetPendingItem> items;

  const AssetPendingCard({super.key, required this.items});

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

class VerifiedNetWorthCard extends StatelessWidget {
  final List<NetWorthVerifiedCheckpoint> checkpoints;
  final NetWorthVerifiedCheckpointComparison? comparison;

  const VerifiedNetWorthCard({
    super.key,
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

class AssetSummaryCard extends StatelessWidget {
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

  const AssetSummaryCard({
    super.key,
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

class AssetAnalysisCard extends StatelessWidget {
  final NetWorthBreakdown breakdown;

  const AssetAnalysisCard({super.key, required this.breakdown});

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
