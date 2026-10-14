import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cloud/cloud_account.dart';
import '../../core/cloud/cloud_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import 'account_page.dart';
import 'account_widgets.dart';
import 'login_sheet.dart';

/// 设置页顶部的账号区。
///
/// 账号功能没打开（默认构建）或上层没挂 [CloudAccount] 时什么都不显示，
/// 设置页和现在一模一样。
class AccountSettingsSection extends StatelessWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<CloudAccount?>();
    if (account == null || !account.enabled) return const SizedBox.shrink();
    return _AccountSectionBody(account: account);
  }
}

class _AccountSectionBody extends StatefulWidget {
  const _AccountSectionBody({required this.account});

  final CloudAccount account;

  @override
  State<_AccountSectionBody> createState() => _AccountSectionBodyState();
}

class _AccountSectionBodyState extends State<_AccountSectionBody> {
  @override
  void initState() {
    super.initState();
    // 打开设置页时刷新一次权益（ETag 缓存，没变化只回 304）。
    if (widget.account.signedIn) widget.account.refreshEntitlements();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeIfAny());
  }

  @override
  void didUpdateWidget(covariant _AccountSectionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeIfAny());
  }

  /// 在别处被下线 / 登录过期：提示一次，然后清掉。
  void _showNoticeIfAny() {
    if (!mounted) return;
    final notice = widget.account.signOutNotice;
    if (notice == null) return;
    showAppToast(context, notice, icon: CupertinoIcons.info_circle);
    widget.account.clearSignOutNotice();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (!account.signedIn) {
      return SettingsGroup(children: [
        SettingsRow(
          key: const ValueKey('account-login-row'),
          leading: const Icon(CupertinoIcons.person_crop_circle),
          title: '登录 / 注册',
          subtitle: '会员和 AI 额度跟着账号走，账本仍只存在本机',
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: () => showLoginSheet(context),
        ),
      ]);
    }

    final ent = account.entitlements;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ent != null) MembershipCard(entitlements: ent),
        SettingsGroup(children: [
          SettingsRow(
            key: const ValueKey('account-row'),
            leading: const Icon(CupertinoIcons.person_crop_circle),
            title: '账号',
            subtitle: account.me?.email,
            trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
            onTap: () => Navigator.push(
              context,
              AppPageRoute<void>(
                builder: (_) => ChangeNotifierProvider<CloudAccount>.value(
                  value: account,
                  child: const AccountPage(),
                ),
              ),
            ),
          ),
          if (ent?.redeemInApp ?? false)
            SettingsRow(
              key: const ValueKey('account-redeem-row'),
              leading: const Icon(CupertinoIcons.gift),
              title: '兑换码',
              trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
              onTap: () => showRedeemDialog(context, account),
            ),
        ]),
      ],
    );
  }
}

/// 会员卡：等级 + 到期时间 + 额度进度条。
///
/// 只显示百分比和时间，不出现积分、金额、token 数（后端 04 §A.4）。
/// `quota.display == hidden` 时整块额度不显示。
class MembershipCard extends StatelessWidget {
  const MembershipCard({super.key, required this.entitlements, this.now});

  final Entitlements entitlements;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quota = entitlements.quota;
    final weekly = quota.showBar ? quota.weekly : null;
    final bonus = quota.showBar ? quota.bonus : null;
    final warnAt = quota.warnPct.isEmpty
        ? 80
        : quota.warnPct.reduce((a, b) => a < b ? a : b);
    return Container(
      key: const ValueKey('membership-card'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entitlements.tier.name.isEmpty
                      ? '免费版'
                      : entitlements.tier.name,
                  style: AppType.rowTitle(scheme)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                membershipStatusText(entitlements.membership, now: now),
                style: AppType.trailingValue(scheme),
              ),
            ],
          ),
          if (weekly != null) ...[
            const SizedBox(height: 14),
            _QuotaBar(
              key: const ValueKey('quota-weekly'),
              label: '本周额度',
              value: weekly.usedPct / 100,
              valueText: '已用 ${weekly.usedPct.round()}%',
              hint: weekly.resetsAt == null
                  ? null
                  : '${formatAccountDate(weekly.resetsAt!, now: now)} 重置',
              warn: weekly.usedPct >= warnAt,
            ),
          ],
          if (bonus != null && bonus.remainingPct > 0) ...[
            const SizedBox(height: 12),
            _QuotaBar(
              key: const ValueKey('quota-bonus'),
              label: '额外额度',
              value: bonus.remainingPct / 100,
              valueText: '剩余 ${bonus.remainingPct.round()}%',
              hint: bonus.nextExpiryAt == null
                  ? null
                  : '${formatAccountDate(bonus.nextExpiryAt!, now: now)} 起部分到期',
            ),
          ],
        ],
      ),
    );
  }
}

String membershipStatusText(Membership m, {DateTime? now}) {
  final trial = m.trial ? '试用 · ' : '';
  switch (m.status) {
    case MembershipStatus.active:
      final end = m.endsAt;
      return end == null
          ? '$trial生效中'
          : '$trial${formatAccountDate(end, now: now)} 到期';
    case MembershipStatus.grace:
      final until = m.graceUntil;
      return until == null
          ? '已到期，宽限中'
          : '宽限至 ${formatAccountDate(until, now: now)}';
    case MembershipStatus.expired:
      return '已到期';
    case MembershipStatus.none:
    case MembershipStatus.unknown:
      return '未开通会员';
  }
}

class _QuotaBar extends StatelessWidget {
  const _QuotaBar({
    super.key,
    required this.label,
    required this.value,
    required this.valueText,
    this.hint,
    this.warn = false,
  });

  final String label;
  final double value;
  final String valueText;
  final String? hint;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppType.secondary(scheme))),
            Text(
              valueText,
              style: AppType.secondary(scheme).copyWith(
                fontFamily: 'Nunito',
                color: warn ? AppColors.warning : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 6,
            color: warn ? AppColors.warning : scheme.primary,
            backgroundColor: AppColors.cardTrack(scheme),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: AppType.caption(scheme)),
        ],
      ],
    );
  }
}

/// 兑换码（仅安卓，服务端 `redeem.in_app` 为 true 时才有入口）。
Future<void> showRedeemDialog(
    BuildContext context, CloudAccount account) async {
  // 和其它表单弹窗一样不手动 dispose：弹窗关闭动画期间输入框还在用它。
  final controller = TextEditingController();
  final ok = await showIosFormDialog(
    context,
    title: '兑换码',
    subtitle: '输入兑换码开通或延长会员',
    confirmText: '兑换',
    content: Builder(
      builder: (ctx) => TextField(
        key: const ValueKey('redeem-code'),
        controller: controller,
        autofocus: true,
        autocorrect: false,
        maxLength: 64,
        textCapitalization: TextCapitalization.characters,
        decoration: iosInputDecoration(ctx, hint: '例如 FM-XXXX-XXXX'),
      ),
    ),
  );
  final code = controller.text.trim();
  if (!ok || code.isEmpty || !context.mounted) return;
  try {
    final grant = await account.redeem(code);
    if (!context.mounted) return;
    showAppToast(context, grant.summary ?? '兑换成功');
  } catch (error) {
    if (!context.mounted) return;
    showAppToast(context, accountErrorText(error),
        icon: CupertinoIcons.exclamationmark_circle);
  }
}
