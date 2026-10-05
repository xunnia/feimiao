// 资产总览页卡片，从 accounts_view.dart 拆出。
import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/assets/asset_structure_projection.dart';
import '../../core/money_cents.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'asset_overview_style.dart';

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

/// D2b: 计算连续核对月份数（已激活记录，从最近月份往前连续）。
int _computeCheckInStreak(List<NetWorthVerifiedCheckpoint> ordered) {
  // ordered 已按 asOf 降序排列
  if (ordered.isEmpty) return 0;
  int streak = 1;
  var prevLocal = ordered[0].header.asOf.toLocal();
  var prevYM = (prevLocal.year, prevLocal.month);
  for (var i = 1; i < ordered.length; i++) {
    final curLocal = ordered[i].header.asOf.toLocal();
    final curYM = (curLocal.year, curLocal.month);
    if (curYM == prevYM) continue;
    // 计算 prevYM 的上一个月
    final expYear = prevYM.$2 == 1 ? prevYM.$1 - 1 : prevYM.$1;
    final expMonth = prevYM.$2 == 1 ? 12 : prevYM.$2 - 1;
    if (curYM.$1 == expYear && curYM.$2 == expMonth) {
      streak++;
      prevYM = curYM;
    } else {
      break;
    }
  }
  return streak;
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
    final change = comparison?.later.header.uuid == latest.header.uuid
        ? comparison?.change
        : null;
    final latestDate = latest.header.asOf.toLocal();
    final streak = _computeCheckInStreak(ordered); // D2b
    final completeness = latest.header.completeness ==
            NetWorthVerifiedCheckpointCompleteness.complete
        ? '完整核对'
        : '部分核对';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _OverviewSectionTitle('上次核对'),
      Container(
        key: const ValueKey('asset-verified-summary'),
        padding: const EdgeInsets.all(16),
        decoration: appCardDecoration(scheme),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('$completeness · 人民币',
                    style: AppType.secondary(scheme))),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                tooltip: '查看上次核对详情',
                padding: EdgeInsets.zero,
                iconSize: 16,
                color: AssetOverviewStyle.labelColor(context),
                icon: const Icon(CupertinoIcons.info_circle),
                onPressed: () => _showDetails(context, latest, change),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
              width: double.infinity,
              child: AssetOverviewAmount(
                  budgetDecimalFromCents(latest.header.totals.netWorthMinor)!,
                  size: 22.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text(_checkpointDate(latestDate), style: AppType.secondary(scheme)),
            if (streak >= 2)
              Text('连续 $streak 月核对', style: AppType.caption(scheme)),
          ]),
          if (change != null) ...[
            const SizedBox(height: 6),
            Text(
                '较上次完整核对 ${change.netWorthDeltaMinor >= 0 ? '+' : ''}'
                '${AssetOverviewStyle.amount(budgetDecimalFromCents(change.netWorthDeltaMinor)!)}',
                style:
                    AppType.secondary(scheme).copyWith(fontFamily: 'Nunito')),
          ] else if (latest.header.completeness ==
              NetWorthVerifiedCheckpointCompleteness.partial) ...[
            const SizedBox(height: 6),
            Text('有 ${latest.header.incompletenessReasons.length} 项待完善，暂不比较变化',
                style: AppType.secondary(scheme)),
          ] else ...[
            const SizedBox(height: 6),
            Text(
                comparison?.later.header.uuid == latest.header.uuid &&
                        comparison!.issues.isNotEmpty
                    ? '两次核对口径不同，暂不比较变化'
                    : '再完成一次可比的完整核对后显示变化',
                style: AppType.caption(scheme)),
          ],
        ]),
      ),
    ]);
  }

  void _showDetails(BuildContext context, NetWorthVerifiedCheckpoint checkpoint,
      NetWorthVerifiedCheckpointChange? change) {
    final scheme = Theme.of(context).colorScheme;
    final header = checkpoint.header;
    showBlurSheet<void>(context,
        child: Builder(
            builder: (sheetContext) => DecoratedBox(
                  decoration:
                      BoxDecoration(color: AppColors.sheetSurface(scheme)),
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHeader(
                          title: '上次核对详情',
                          onClose: () => Navigator.of(sheetContext).pop()),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_checkpointDate(header.asOf.toLocal()),
                                    style: AppType.body(scheme)),
                                const SizedBox(height: 8),
                                Text(
                                    '${header.completeness == NetWorthVerifiedCheckpointCompleteness.complete ? '完整核对' : '部分核对'} · 人民币 · 历史金额，不代表当前余额',
                                    style: AppType.secondary(scheme)),
                                const SizedBox(height: 16),
                                for (final item in [
                                  ('当时总资产', header.totals.totalAssetsMinor),
                                  (
                                    '当时总负债',
                                    header.totals.totalLiabilitiesMinor
                                  ),
                                  ('当时净资产', header.totals.netWorthMinor),
                                  if (change != null)
                                    ('较上次完整核对变化', change.netWorthDeltaMinor),
                                ]) ...[
                                  Text(item.$1,
                                      style: AppType.secondary(scheme)),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                      width: double.infinity,
                                      child: AssetOverviewAmount(
                                          budgetDecimalFromCents(item.$2)!,
                                          size: 22.5)),
                                  const SizedBox(height: 16),
                                ],
                                for (final reason
                                    in header.incompletenessReasons)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Text(reason.message,
                                          style: AppType.secondary(scheme))),
                                if (comparison?.later.header.uuid ==
                                        header.uuid &&
                                    change == null)
                                  for (final issue in comparison!.issues)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(_comparisonIssueText(issue),
                                            style: AppType.secondary(scheme))),
                                Text(
                                    '统计范围版本 ${header.scopeVersion} · 计算版本 ${header.calculationVersion}',
                                    style: AppType.caption(scheme)),
                              ])),
                    ],
                  )),
                )));
  }
}

String _checkpointDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _comparisonIssueText(NetWorthVerifiedComparabilityIssue issue) =>
    switch (issue) {
      NetWorthVerifiedComparabilityIssue.nonIncreasingAsOf =>
        '两次核对的时间顺序不符，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.earlierNotActive =>
        '上一次核对已撤销或被替代，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.laterNotActive =>
        '本次核对已撤销或被替代，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.earlierIncomplete =>
        '上一次核对只覆盖部分资产，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.laterIncomplete =>
        '本次核对只覆盖部分资产，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.scopeVersionMismatch =>
        '两次核对的资产计入范围不同，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.calculationVersionMismatch =>
        '两次核对的计算口径不同，暂不比较变化。',
      NetWorthVerifiedComparabilityIssue.currencyCoverageMismatch =>
        '两次核对覆盖的币种不同，暂不比较变化。',
    };

class _OverviewSectionTitle extends StatelessWidget {
  const _OverviewSectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(title, style: AssetOverviewStyle.label(context)));
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
            '净资产（按 CNY 计）',
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

Color _structureColor(AssetStructureKind kind, ColorScheme scheme) =>
    switch (kind) {
      AssetStructureKind.cash => scheme.primary,
      AssetStructureKind.investment => scheme.onSurface.withValues(alpha: 0.52),
      AssetStructureKind.receivable => kCatPink,
      AssetStructureKind.physical => kCatGold,
    };

class AssetAnalysisCard extends StatelessWidget {
  final NetWorthBreakdown breakdown;
  final bool partial;

  const AssetAnalysisCard(
      {super.key, required this.breakdown, this.partial = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final structure = AssetStructureProjection(
        totalAssets: breakdown.totalAssets,
        totalLiabilities: breakdown.totalLiabilities,
        cash: breakdown.cashAssets,
        investment: breakdown.investmentAssets,
        receivable: breakdown.receivableAssets,
        physical: breakdown.physicalAssets,
        partial: partial);
    final kinds = structure.visibleKinds.toList();
    final rate = structure.liabilityPercentage;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _OverviewSectionTitle('资产结构'),
      Container(
        key: const ValueKey('asset-structure-card'),
        padding: const EdgeInsets.all(16),
        decoration: appCardDecoration(scheme),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (structure.hasShares && kinds.length > 1) ...[
            SizedBox(
                width: double.infinity,
                height: 6,
                child: CustomPaint(
                  key: const ValueKey('asset-structure-bar'),
                  painter: _AssetStructurePainter([
                    for (final kind in kinds)
                      (
                        structure.percentage(kind)!.toDouble() / 100,
                        _structureColor(kind, scheme)
                      ),
                  ]),
                )),
            const SizedBox(height: 16),
          ],
          if (kinds.isEmpty)
            Text('暂无已计入的人民币资产', style: AppType.secondary(scheme)),
          for (var i = 0; i < kinds.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _AssetStructureRow(
                kind: kinds[i],
                amount: structure.amounts[kinds[i]]!,
                percentage: structure.percentage(kinds[i]),
                color: _structureColor(kinds[i], scheme)),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 0.5, color: AppColors.hairline(scheme)),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            Text('人民币 · 已计入资产', style: AppType.caption(scheme)),
            Text('负债率 ${rate == null ? '—' : '${rate.toStringAsFixed(1)}%'}',
                style:
                    AppType.secondary(scheme).copyWith(fontFamily: 'Nunito')),
          ]),
          if (partial || !structure.isConsistent) ...[
            const SizedBox(height: 6),
            Text(partial ? '部分金额待确认，占比暂不可比' : '金额口径待核实，占比暂不可比',
                style: AppType.secondary(scheme)),
          ],
        ]),
      ),
    ]);
  }
}

class _AssetStructureRow extends StatelessWidget {
  const _AssetStructureRow(
      {required this.kind,
      required this.amount,
      required this.percentage,
      required this.color});
  final AssetStructureKind kind;
  final Decimal amount;
  final Decimal? percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Row(children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(kind.label, style: AppType.secondary(scheme))),
    ]);
    final percentText =
        percentage == null ? '—' : '${percentage!.toStringAsFixed(1)}%';
    final values = Row(children: [
      Expanded(child: AssetOverviewAmount(amount, size: 18)),
      const SizedBox(width: 12),
      Text(percentText,
          style: AppType.secondary(scheme).copyWith(fontFamily: 'Nunito')),
    ]);
    return Semantics(
      key: ValueKey('asset-structure-${kind.name}'),
      label: '${kind.label} ${AssetOverviewStyle.amount(amount)} 人民币，'
          '${percentage == null ? '占比不可计算' : '占比$percentText'}',
      child: ExcludeSemantics(
          child: LayoutBuilder(builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(13) > 18;
        return large || constraints.maxWidth < 300
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 6), values])
            : Row(children: [
                Expanded(flex: 4, child: title),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: values)
              ]);
      })),
    );
  }
}

class _AssetStructurePainter extends CustomPainter {
  const _AssetStructurePainter(this.segments);
  final List<(double, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)));
    double x = 0;
    for (final (share, color) in segments) {
      final width = size.width * share;
      canvas.drawRect(
          Rect.fromLTWH(x, 0, width, size.height), Paint()..color = color);
      x += width;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AssetStructurePainter oldDelegate) =>
      !listEquals(segments, oldDelegate.segments);
}
