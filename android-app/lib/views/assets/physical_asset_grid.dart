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
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';

class PhysicalAssetGrid extends StatefulWidget {
  final List<PhysicalAssetEntity> assets;
  final ValueChanged<PhysicalAssetEntity> onTap;

  const PhysicalAssetGrid({
    super.key,
    required this.assets,
    required this.onTap,
  });

  @override
  State<PhysicalAssetGrid> createState() => _PhysicalAssetGridState();
}

class _PhysicalAssetGridState extends State<PhysicalAssetGrid> {
  final _searchController = TextEditingController();
  AssetType? _type;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PhysicalAssetEntity> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return widget.assets.where((asset) {
      if (_type != null && asset.assetType != _type) return false;
      if (query.isEmpty) return true;
      return [
        asset.name,
        asset.brand,
        asset.model,
        asset.note,
        asset.location,
      ].any((value) => value.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('asset-grid-search'),
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: iosInputDecoration(
                    context,
                    hint: '搜索物品',
                  ).copyWith(
                    prefixIcon: const Icon(Icons.search, size: 19),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (buttonContext) => AppPillButton(
                  label: _type?.label ?? '全部分类',
                  onPressed: () => showIosMenu(
                    buttonContext,
                    [
                      IosMenuItem(
                        label: '全部分类',
                        icon: Icons.inventory_2_outlined,
                        selected: _type == null,
                        onTap: () => setState(() => _type = null),
                      ),
                      for (final type in AssetType.values)
                        IosMenuItem(
                          label: type.label,
                          icon: assetTypeIcon(type),
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    widget.assets.isEmpty ? '还没有物品' : '没有匹配的物品',
                    style: AppType.secondary(scheme),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final largeText = textScale >= 1.3;
                    final singleColumn =
                        constraints.maxWidth < 360 || largeText;
                    return GridView.builder(
                      key: const Key('physical-asset-grid'),
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: singleColumn ? 1 : 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio:
                            singleColumn ? (largeText ? 1.75 : 2.25) : 0.78,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _AssetGridCard(
                        asset: filtered[index],
                        horizontal: singleColumn,
                        onTap: () => widget.onTap(filtered[index]),
                      ),
                    );
                  },
                ),
        ),
      ],
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
                        Expanded(flex: 6, child: image),
                        Expanded(flex: 5, child: content),
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
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption(scheme),
          ),
          const Spacer(),
          Text(
            primaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            secondaryText,
            key: Key('physical-asset-secondary-${asset.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption(scheme),
          ),
        ],
      ),
    );
  }
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
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
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
