import 'package:flutter/material.dart';

import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import 'asset_overview_style.dart';

bool fundsSummaryIsPartial({
  required MetricResult<NetWorthBreakdown> netWorthResult,
  required Iterable<PhysicalAssetEntity> physicalAssets,
  required Iterable<ReceivableAssetEntity> receivableAssets,
}) {
  if (netWorthResult.status == MetricStatus.available) return false;
  if (netWorthResult.status != MetricStatus.partial) return true;
  final physicalCurrencies = {
    for (final asset in physicalAssets.where((asset) => asset.countsInNetWorth))
      (asset.id, asset.currencyCode),
  };
  final receivableCurrencies = {
    for (final asset
        in receivableAssets.where((asset) => asset.countsInNetWorth))
      (asset.id, asset.currencyCode),
  };
  return netWorthResult.reasons.any((reason) {
    final details = reason.details;
    if (details.containsKey('account_id')) return true;
    final domain = details['domain'];
    if (domain == 'physical_asset' || domain == 'valuation') return false;
    if (reason.code != MetricReasonCode.unsupportedCurrencyAggregation ||
        domain != null) {
      return true;
    }
    final id = details['asset_id'];
    final currency = details['currency'];
    if (id is! int || currency is! String) return true;
    final key = (id, currency);
    // Physical and receivable tables have independent IDs; ambiguous IDs stay partial.
    return !physicalCurrencies.contains(key) ||
        receivableCurrencies.contains(key);
  });
}

/// Global CNY funds, not the subtotal of the search results or active list.
class FundsSummaryCard extends StatelessWidget {
  const FundsSummaryCard(
      {super.key, required this.breakdown, required this.partial});
  final NetWorthBreakdown breakdown;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final funds = breakdown.cashAssets +
        breakdown.investmentAssets +
        breakdown.receivableAssets;
    final total =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('资金净值 · 人民币', style: AssetOverviewStyle.label(context)),
      const SizedBox(height: 2),
      SizedBox(
          width: double.infinity,
          child: AssetOverviewAmount(funds - breakdown.totalLiabilities,
              size: 28)),
    ]);
    final detail =
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('资金 ${AssetOverviewStyle.amount(funds)}',
          style: AppType.caption(scheme)
              .copyWith(fontSize: 12, fontFamily: 'Nunito')),
      Text('负债 ${AssetOverviewStyle.amount(breakdown.totalLiabilities)}',
          style: AppType.caption(scheme)
              .copyWith(fontSize: 12, fontFamily: 'Nunito')),
    ]);
    return Container(
      key: const Key('funds-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.hairline(scheme), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(
            builder: (context, constraints) => MediaQuery.textScalerOf(context)
                            .scale(12) >
                        17 ||
                    constraints.maxWidth < 280
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [total, const SizedBox(height: 8), detail])
                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(flex: 3, child: total),
                    const SizedBox(width: 12),
                    Flexible(flex: 2, child: detail)
                  ])),
        if (partial) ...[
          const SizedBox(height: 6),
          Text('部分金额待确认，仅含已覆盖的人民币资金', style: AppType.caption(scheme))
        ],
      ]),
    );
  }
}
