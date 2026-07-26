// 权益(应收)资产：列表卡片与详情页（从 accounts_view.dart 拆出）。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_enhancements.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'asset_form_kit.dart';
import 'receivable_sheets.dart';

IconData _receivableIcon(ReceivableAssetType type) => switch (type) {
      ReceivableAssetType.rentalDeposit => Icons.key_outlined,
      ReceivableAssetType.loanOut => Icons.call_made_outlined,
      ReceivableAssetType.accountReceivable => Icons.receipt_long_outlined,
      ReceivableAssetType.prepaidCard => Icons.credit_card_outlined,
      ReceivableAssetType.membershipCard => Icons.card_membership_outlined,
      ReceivableAssetType.securityDeposit => Icons.verified_user_outlined,
      ReceivableAssetType.other => Icons.assignment_return_outlined,
    };

class ReceivableAssetGroupCard extends StatelessWidget {
  final List<ReceivableAssetEntity> assets;
  final ValueChanged<ReceivableAssetEntity> onTap;

  const ReceivableAssetGroupCard({
    super.key,
    required this.assets,
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
            if (i > 0) appCardDivider(scheme),
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
    // 副标题减负：最多「类型 + 1 个附加段」，
    // 优先级 = 非默认状态 > 对象 > 「待确认」 > 「不计入」。
    final statusLabel = _receivableStatusLabel(asset);
    final extra = asset.economicStatus != ReceivableEconomicStatus.active
        ? statusLabel
        : asset.counterparty.isNotEmpty
            ? asset.counterparty
            : asset.inclusionQuality == AssetInclusionQuality.needsReview
                ? '待确认'
                : !asset.includeInNetWorth
                    ? '不计入'
                    : null;
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
                      if (extra != null) extra,
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
                            ? AppColors.warning
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

String? _receivableDueReminderText(AssetReminderState reminder) {
  return switch (reminder.status) {
    AssetReminderStatus.upcoming => '${reminder.daysUntilDue} 天后到期',
    AssetReminderStatus.dueToday => '今天到期',
    AssetReminderStatus.expired => '已逾期 ${reminder.daysUntilDue!.abs()} 天',
    AssetReminderStatus.none || AssetReminderStatus.inactive => null,
  };
}

class ReceivableAssetDetailPage extends StatelessWidget {
  final ReceivableAssetEntity asset;

  const ReceivableAssetDetailPage({super.key, required this.asset});

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
                  canRecover: canRecover,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AssetDetailSection(
            title: '权益信息',
            children: [
              AssetDetailRow(label: '类型', value: current.type.label),
              AssetDetailRow(
                label: '状态',
                value: _receivableStatusLabel(current),
              ),
              AssetDetailRow(
                label: '剩余金额',
                value: MoneyFormat.string(current.remainingAmount),
              ),
              AssetDetailRow(
                label: '原始金额',
                value: MoneyFormat.string(current.originalAmount),
              ),
              if (current.counterparty.isNotEmpty)
                AssetDetailRow(
                  label: '对象',
                  value: current.counterparty,
                ),
              AssetDetailRow(
                label: '到期日',
                value: current.dueDate == null
                    ? '未填写'
                    : '${assetDateText(current.dueDate)} · ${assetReminderDetailText(
                        dueReminder,
                        upcomingLabel: '还有',
                        dueTodayLabel: '今天到期',
                        expiredLabel: '已逾期',
                        inactiveLabel: '已结束跟踪',
                      )}',
              ),
              AssetDetailRow(
                label: '净资产',
                value: current.countsInNetWorth ? '计入净资产' : '不计入净资产',
              ),
              if (current.note.isNotEmpty)
                AssetDetailRow(label: '备注', value: current.note),
            ],
          ),
          const SizedBox(height: 12),
          AssetActionButton(
            label: '收回',
            icon: Icons.savings_outlined,
            onTap:
                canRecover ? () => _showRecoverSheet(context, current) : null,
          ),
          if (current.inclusionQuality ==
              AssetInclusionQuality.needsReview) ...[
            const SizedBox(height: 12),
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: '确认状态与是否计入',
                  subtitle: '确认后不再提醒',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showReviewSheet(context, current),
                ),
              ],
            ),
          ],
          if (recoveries.isNotEmpty) ...[
            const SizedBox(height: 12),
            AssetDetailSection(
              title: '收回历史',
              children: [
                for (final recovery in recoveries)
                  AssetDetailRow(
                    label: assetDateText(recovery.recoveredAt),
                    value: MoneyFormat.string(recovery.amount),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AssetActionButton(
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
          AssetDetailSection(
            title: '最近事件',
            children: events.isEmpty
                ? const [
                    AssetDetailRow(label: '暂无', value: '还没有权益事件'),
                  ]
                : [
                    for (final event in events)
                      AssetDetailRow(
                        label: event.eventType.label,
                        value:
                            '${assetDateText(event.occurredAt)}${event.value == null ? '' : ' · ${MoneyFormat.string(event.value!)}'}',
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  /// 右上角 ⋯ 菜单：编辑资料、标记损失、归档/恢复等动作类操作收在这里。
  void _showMoreMenu(
    BuildContext menuContext,
    BuildContext pageContext,
    AppRepository repo,
    ReceivableAssetEntity current, {
    required bool canRecover,
  }) {
    showIosMenu(
      menuContext,
      [
        IosMenuItem(
          label: '编辑资料',
          icon: Icons.edit_outlined,
          onTap: () => showBlurSheet<void>(
            pageContext,
            child: ReceivableAssetFormSheet(asset: current),
          ),
        ),
        if (canRecover)
          IosMenuItem(
            label: '标记损失',
            icon: Icons.money_off_csred_outlined,
            onTap: () => _markLost(pageContext, repo, current),
          ),
        IosMenuItem(
          label: current.isArchived ? '恢复到列表' : '归档',
          icon: current.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          onTap: () => _toggleArchive(pageContext, repo, current),
        ),
      ],
    );
  }

  void _showRecoverSheet(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: ReceivableRecoverySheet(asset: asset),
    );
  }

  void _showReviewSheet(
    BuildContext context,
    ReceivableAssetEntity asset,
  ) {
    showBlurSheet<void>(
      context,
      child: ReceivableReviewSheet(asset: asset),
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
