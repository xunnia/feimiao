// 资产页统一「添加」入口弹层：资金/物品两组入口 + 最近账单候选行。
import 'package:flutter/material.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

/// 统一「添加」弹层：三个 tab 的右上 ＋ 都开它。
/// 资金=添加账户/添加权益；物品=新购买记账/从最近账单加入/手工补录物品。
/// 「从最近账单加入」行下方内嵌最近几笔可加入的支出账单，点行一步直达表单。
class AssetAddEntrySheet extends StatelessWidget {
  final VoidCallback onAccount;
  final VoidCallback onReceivableAsset;
  final VoidCallback onBorrow;
  final VoidCallback onLoanWizard;
  final VoidCallback onNewPurchase;
  final VoidCallback onFromTransaction;
  final VoidCallback onManual;
  final List<AssetPurchaseAllocationCandidate> recentCandidates;
  final ValueChanged<AssetPurchaseAllocationCandidate> onRecentCandidate;

  const AssetAddEntrySheet({
    super.key,
    required this.onAccount,
    required this.onReceivableAsset,
    required this.onBorrow,
    required this.onLoanWizard,
    required this.onNewPurchase,
    required this.onFromTransaction,
    required this.onManual,
    required this.recentCandidates,
    required this.onRecentCandidate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: '添加',
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SettingsSectionLabel('资金'),
                    SettingsGroup(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      children: [
                        SettingsRow(
                          leading:
                              const Icon(Icons.account_balance_wallet_outlined),
                          title: '添加账户',
                          subtitle: '现金、银行卡、信用卡、存款、贷款',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onAccount,
                        ),
                        SettingsRow(
                          leading: const Icon(Icons.assignment_return_outlined),
                          title: '添加权益',
                          subtitle: '押金、借出款、应收款、预付余额',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onReceivableAsset,
                        ),
                        SettingsRow(
                          key: const Key('add-entry-borrow'),
                          leading: const Icon(Icons.call_received_outlined),
                          title: '记一笔借入',
                          subtitle: '向别人借的钱，按人管理',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onBorrow,
                        ),
                        SettingsRow(
                          key: const Key('add-entry-loan-wizard'),
                          leading: const Icon(Icons.home_work_outlined),
                          title: '房贷/分期向导',
                          subtitle: '一次设好账户、档案和每月自动还款',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onLoanWizard,
                        ),
                      ],
                    ),
                    const SettingsSectionLabel('物品'),
                    SettingsGroup(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      children: [
                        SettingsRow(
                          leading: const Icon(Icons.shopping_bag_outlined),
                          title: '新购买记账',
                          subtitle: '选择付款账户，购买日同时写入物品和支出',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onNewPurchase,
                        ),
                        SettingsRow(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: '从最近账单加入',
                          subtitle: '继承购买日期和账本，不会重复记支出',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: onFromTransaction,
                        ),
                        for (final candidate in recentCandidates)
                          _RecentPurchaseCandidateRow(
                            candidate: candidate,
                            onTap: () => onRecentCandidate(candidate),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「从最近账单加入」行下内嵌的候选账单行：点一下直达「填写物品信息」表单。
class _RecentPurchaseCandidateRow extends StatelessWidget {
  final AssetPurchaseAllocationCandidate candidate;
  final VoidCallback onTap;

  const _RecentPurchaseCandidateRow({
    required this.candidate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transaction = candidate.transaction;
    final note = transaction.note.trim();
    final title = note.isEmpty
        ? transaction.categoryNameZh.isEmpty
            ? '支出账单'
            : transaction.categoryNameZh
        : note;
    final date = transaction.date;
    final dateText = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 左侧多缩进一档，表明从属于上面的「从最近账单加入」。
        padding: const EdgeInsets.fromLTRB(28, 9, 16, 9),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.iconCircleFill(scheme),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 15,
                color: AppTextColor.secondary(scheme),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(scheme),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    digitAwareAmountSpan(dateText, AppType.caption(scheme)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode),
              style: AppType.body(scheme).copyWith(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppTextColor.secondary(scheme),
            ),
          ],
        ),
      ),
    );
  }
}
