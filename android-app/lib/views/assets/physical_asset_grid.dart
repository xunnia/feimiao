import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_enhancements.dart';
import '../../core/assets/asset_metrics.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pressable_scale.dart';

/// 纯展示的物品网格：搜索/筛选状态由上层（资产管理页）统一持有，
/// 这里只负责把已筛好的 assets 摆成响应式网格。
class PhysicalAssetGrid extends StatelessWidget {
  final List<PhysicalAssetEntity> assets;
  final ValueChanged<PhysicalAssetEntity> onTap;

  const PhysicalAssetGrid({
    super.key,
    required this.assets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final largeText = textScale >= 1.3;
        final singleColumn = constraints.maxWidth < 360 || largeText;
        return GridView.builder(
          key: const Key('physical-asset-grid'),
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: singleColumn ? 1 : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // 2 栏卡片改矮胖为瘦高（0.78→0.66），给底部文字行留够高度，
            // 否则窄屏上名称+说明+提醒三行会被固定宽高比裁成溢出碎块。
            childAspectRatio: singleColumn ? (largeText ? 1.75 : 2.25) : 0.66,
          ),
          itemCount: assets.length,
          itemBuilder: (context, index) => _AssetGridCard(
            asset: assets[index],
            horizontal: singleColumn,
            onTap: () => onTap(assets[index]),
          ),
        );
      },
    );
  }
}

class _AssetGridCard extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final bool horizontal;
  final VoidCallback onTap;

  const _AssetGridCard({
    required this.asset,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final cost = repo.physicalAssetAcquisitionCost(asset.id);
    final additional = repo.physicalAssetAdditionalCost(asset.id);
    final usage = repo.physicalAssetUsage(asset.id);
    final hasKnownValuation = repo.valuationsForAsset(asset.id).isNotEmpty;
    final metrics = resolvePhysicalAssetMetrics(PhysicalAssetMetricInput(
      netAcquisitionCost: cost.amount ?? Decimal.zero,
      additionalNetCost: additional.amount,
      currentNetValue: asset.currentValue,
      purchasedAt: asset.purchaseDate,
      endedAt: asset.endedAt,
      isEconomicallyOwned:
          asset.economicStatus == PhysicalAssetEconomicStatus.owned,
      hasKnownValuation: hasKnownValuation,
      hasComparableCurrency: true,
      usageTrackingEnabled: asset.usageTrackingEnabled,
      usageCount: usage.totalCount,
    ));
    final held = metrics.heldDays;
    final daily = metrics.dailyHoldingCost;
    final subtitle = [
      asset.assetType.label,
      physicalAssetStatusLabel(asset),
      if (held.isExact) '${held.value} 天',
    ].join(' · ');
    final dailyText = asset.purchaseDate == null
        ? '补购买日期'
        : !cost.isExact || !additional.isExact
            ? '成本待确认'
            : daily.isExact
                ? '${MoneyFormat.string(daily.value!, currencyCode: asset.currencyCode)}/天'
                : '日均待确认';
    final valuationText = hasKnownValuation
        ? '估值 ${MoneyFormat.string(
            asset.currentValue,
            currencyCode: asset.currencyCode,
          )}'
        : '估值待确认';
    final reminderText = _warrantyReminderText(
      repo.warrantyReminderForAsset(asset),
    );
    final canQuickRecord = asset.isOwned && asset.usageTrackingEnabled;
    final image = _AssetImage(asset: asset);
    final content = _AssetCardText(
      asset: asset,
      subtitle: subtitle,
      primaryText: dailyText,
      secondaryText: reminderText ?? valuationText,
      reserveQuickActionSpace: canQuickRecord,
    );

    return Stack(
      key: Key('physical-asset-card-${asset.id}'),
      fit: StackFit.expand,
      children: [
        Semantics(
          button: true,
          label:
              '${asset.name}，${physicalAssetStatusLabel(asset)}，$dailyText，$valuationText',
          child: PressableScale(
            onPressed: onTap,
            pressedScale: 0.985,
            pressedOpacity: 0.92,
            child: Material(
              color: AppColors.card(scheme),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: horizontal
                  ? Row(
                      children: [
                        SizedBox(
                          width: 132,
                          height: double.infinity,
                          child: image,
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: image),
                        Expanded(flex: 6, child: content),
                      ],
                    ),
            ),
          ),
        ),
        if (canQuickRecord)
          Positioned(
            right: 8,
            bottom: 8,
            child: Semantics(
              button: true,
              label: '为${asset.name}记录一次使用',
              child: Tooltip(
                message: '记录一次使用',
                child: AppCircleButton(
                  key: Key('physical-asset-quick-use-${asset.id}'),
                  icon: Icons.add,
                  size: 32,
                  iconSize: 18,
                  onPressed: () async {
                    await repo.recordPhysicalAssetUsage(asset.id);
                    if (context.mounted) {
                      showAppToast(context, '已记录 1 次使用');
                    }
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AssetCardText extends StatelessWidget {
  final PhysicalAssetEntity asset;
  final String subtitle;
  final String primaryText;
  final String secondaryText;
  final bool reserveQuickActionSpace;

  const _AssetCardText({
    required this.asset,
    required this.subtitle,
    required this.primaryText,
    required this.secondaryText,
    required this.reserveQuickActionSpace,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        reserveQuickActionSpace ? 48 : 10,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            asset.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.rowTitle(scheme),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.secondary(scheme),
          ),
          const Spacer(),
          Text.rich(
            _digitAwareSpan(
              primaryText,
              (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            secondaryText,
            key: Key('physical-asset-secondary-${asset.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.secondary(scheme),
          ),
        ],
      ),
    );
  }
}

/// 中文混排文案里只给数字子串套 Nunito（UI 标准：Nunito 只准用于纯数字/金额）。
TextSpan _digitAwareSpan(String text, TextStyle base) {
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in RegExp(r'[0-9][0-9,.]*').allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(TextSpan(
      text: text.substring(match.start, match.end),
      style: base.copyWith(fontFamily: 'Nunito'),
    ));
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: spans);
}

String? _warrantyReminderText(AssetReminderState reminder) {
  return switch (reminder.status) {
    AssetReminderStatus.upcoming => '保修还有 ${reminder.daysUntilDue} 天',
    AssetReminderStatus.dueToday => '保修今天到期',
    AssetReminderStatus.expired => '保修已过期 ${reminder.daysUntilDue!.abs()} 天',
    AssetReminderStatus.none || AssetReminderStatus.inactive => null,
  };
}

class _AssetImage extends StatelessWidget {
  final PhysicalAssetEntity asset;

  const _AssetImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    final imagePath = asset.thumbnailPath.trim().isNotEmpty
        ? asset.thumbnailPath.trim()
        : asset.photoPath.trim();
    final file = imagePath.isEmpty ? null : File(imagePath);
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 480,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _AssetImagePlaceholder(asset: asset),
      );
    }
    return _AssetImagePlaceholder(asset: asset);
  }
}

class _AssetImagePlaceholder extends StatelessWidget {
  final PhysicalAssetEntity asset;

  const _AssetImagePlaceholder({required this.asset});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: AppColors.iconCircleFill(scheme),
      child: Center(
        child: Icon(
          assetTypeIcon(asset.assetType),
          size: 34,
          color: AppTextColor.secondary(scheme),
        ),
      ),
    );
  }
}

IconData assetTypeIcon(AssetType type) => switch (type) {
      AssetType.digital => Icons.devices_other,
      AssetType.appliance => Icons.kitchen_outlined,
      AssetType.vehicle => Icons.directions_car_outlined,
      AssetType.property => Icons.home_work_outlined,
      AssetType.valuables => Icons.diamond_outlined,
      AssetType.collectibles => Icons.collections_bookmark_outlined,
      AssetType.tools => Icons.handyman_outlined,
      AssetType.other => Icons.inventory_2_outlined,
    };

String physicalAssetStatusLabel(PhysicalAssetEntity asset) =>
    switch (asset.economicStatus) {
      PhysicalAssetEconomicStatus.owned => switch (asset.usageStatus) {
          PhysicalAssetUsageStatus.active => '在用',
          PhysicalAssetUsageStatus.idle => '闲置',
          PhysicalAssetUsageStatus.unknown => '待确认',
        },
      PhysicalAssetEconomicStatus.sold => '已出售',
      PhysicalAssetEconomicStatus.returned => '已退货',
      PhysicalAssetEconomicStatus.scrapped => '已报废',
      PhysicalAssetEconomicStatus.lost => '已丢失',
      PhysicalAssetEconomicStatus.gifted => '已赠送',
    };
