// 懒人盘点：列出所有计入净资产的 CNY 账户，逐一确认余额，完成后创建核对记录。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/account/net_worth_verified_checkpoint.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import 'account_detail_page.dart';

class AssetBalanceReviewSheet extends StatelessWidget {
  const AssetBalanceReviewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    // 只列出：未归档 + 计入净资产 + 人民币账户。
    final accounts = repo.accounts
        .where((a) =>
            !a.isDeleted &&
            !a.isArchived &&
            a.includeInNetWorth &&
            a.currencyCode == 'CNY')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '余额盘点',
            onClose: () => Navigator.pop(context),
          ),
          // 说明文字
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '逐一核对各账户实际余额，需要校准时点击账户行进入校准页。',
              style: AppType.secondary(scheme),
            ),
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('暂无计入净资产的人民币账户', style: AppType.secondary(scheme)),
            )
          else
            SettingsGroup(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final account in accounts)
                  _AccountReviewRow(account: account),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: AppPillButton(
              label: '完成盘点并核对',
              onPressed: () => _complete(context, repo),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(BuildContext context, AppRepository repo) async {
    final staleCount = repo.stalePhysicalValuationCount();
    final confirmed = await showConfirmDialog(
      context,
      title: '完成盘点',
      message: staleCount > 0
          ? '有 $staleCount 件物品使用超过 90 天的最近估值，继续表示接受这些估值日期。'
          : '将以当前各账户余额创建一条净资产核对记录。',
      confirmText: staleCount > 0 ? '接受并核对' : '确认核对',
    );
    if (!confirmed) return;
    final checkpoint = await repo.createVerifiedNetWorthCheckpoint(
      acceptStaleValuations: staleCount > 0,
    );
    if (!context.mounted) return;
    Navigator.pop(context);
    showAppToast(
      context,
      checkpoint.header.completeness ==
              NetWorthVerifiedCheckpointCompleteness.complete
          ? '盘点完成，净资产已核对'
          : '盘点完成，部分数据待确认',
      mascot: MascotMood.success,
    );
  }
}

class _AccountReviewRow extends StatelessWidget {
  final AccountEntity account;

  const _AccountReviewRow({required this.account});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final balance = repo.accountBalanceResultOf(account).value?.balance;
    return SettingsRow(
      leading: Icon(
        Icons.account_balance_outlined,
        color: AppTextColor.secondary(scheme),
        size: 20,
      ),
      title: account.name,
      subtitle: balance != null
          ? MoneyFormat.string(balance)
          : '余额计算中…',
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: AppTextColor.secondary(scheme),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AccountDetailPage(account: account),
        ),
      ),
    );
  }
}
