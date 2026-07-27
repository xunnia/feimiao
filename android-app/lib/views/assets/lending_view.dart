// 借贷往来页（A 批 A2）：借出(receivable.loanOut) + 借入(personalBorrow 档案)
// 按「人」聚合，一人一张卡：净额 + 展开时间线（借出/收回/借入/还款）。
//
// 数据口径（每个数都能回答「哪来的」）：
// - TA欠我 = 该对象名下借出款剩余之和（active/partialRecovered）；
// - 我欠TA = 该对象名下 personalBorrow 档案的剩余本金之和（active）；
// - 时间线：借出=权益登记、收回=收回记录、借入=档案登记、
//   还款=转入借入账户的真实转账流水；两边都有剩余时副标题给出两侧毛额，
//   不拿净额把毛额藏起来。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'asset_form_kit.dart';
import 'asset_overview_cards.dart';
import 'receivable_sheets.dart';
import 'repayment_sheet.dart';

class LendingView extends StatefulWidget {
  const LendingView({super.key});

  @override
  State<LendingView> createState() => _LendingViewState();
}

class _LendingViewState extends State<LendingView> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final parties = _buildParties(repo);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('借贷往来'),
      ),
      body: parties.isEmpty
          ? const AssetEmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                for (int i = 0; i < parties.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _PartyCard(
                    party: parties[i],
                    expanded: _expanded.contains(parties[i].name),
                    onToggle: () => setState(() {
                      if (!_expanded.add(parties[i].name)) {
                        _expanded.remove(parties[i].name);
                      }
                    }),
                    onRecover: (asset) => showBlurSheet<void>(
                      context,
                      child: ReceivableRecoverySheet(asset: asset),
                    ),
                    onRepay: (profile) => showBlurSheet<void>(
                      context,
                      child: RepaymentSheet(profile: profile),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  List<_LendingParty> _buildParties(AppRepository repo) {
    final byName = <String, _LendingParty>{};
    _LendingParty partyOf(String name) =>
        byName.putIfAbsent(name, () => _LendingParty(name));

    final loanOuts = [
      ...repo.globalActiveReceivables,
      ...repo.globalArchivedReceivables,
    ].where((a) => a.type == ReceivableAssetType.loanOut);
    for (final asset in loanOuts) {
      // 没填对象时用权益名称兜底成卡片名（如「借给小明」），
      // 不把所有无对象借出混进同一张卡。
      final name = asset.counterparty.trim().isNotEmpty
          ? asset.counterparty.trim()
          : asset.name.trim().isNotEmpty
              ? asset.name.trim()
              : '未注明对象';
      partyOf(name).loanOuts.add(asset);
    }
    for (final profile in repo.liabilityProfiles
        .where((p) => p.type == LiabilityProfileType.personalBorrow)) {
      final name = profile.counterparty.trim().isNotEmpty
          ? profile.counterparty.trim()
          : '未注明对象';
      partyOf(name).borrows.add(profile);
    }
    final parties = byName.values.toList();
    for (final party in parties) {
      party.resolve(repo);
    }
    // 最近有动静的排前面。
    parties.sort((a, b) => b.latestEventMs.compareTo(a.latestEventMs));
    return parties;
  }
}

class _LendingParty {
  final String name;
  final List<ReceivableAssetEntity> loanOuts = [];
  final List<LiabilityProfileEntity> borrows = [];
  final List<_LendingEvent> events = [];
  Decimal lentRemaining = Decimal.zero;
  Decimal borrowedRemaining = Decimal.zero;

  _LendingParty(this.name);

  Decimal get net => lentRemaining - borrowedRemaining;
  int get latestEventMs =>
      events.isEmpty ? 0 : events.first.date.millisecondsSinceEpoch;

  void resolve(AppRepository repo) {
    lentRemaining = Decimal.zero;
    borrowedRemaining = Decimal.zero;
    events.clear();
    for (final asset in loanOuts) {
      final open = !asset.isDeleted &&
          (asset.economicStatus == ReceivableEconomicStatus.active ||
              asset.economicStatus == ReceivableEconomicStatus.partialRecovered);
      if (open) lentRemaining += asset.remainingAmount;
      events.add(_LendingEvent(
        date: DateTime.fromMillisecondsSinceEpoch(asset.createdMs),
        label: '借出',
        amount: asset.originalAmount,
        annotation: asset.inclusionQuality == AssetInclusionQuality.needsReview
            ? '待确认'
            : null,
        recoverAsset:
            open && asset.remainingAmount > Decimal.zero ? asset : null,
      ));
      for (final recovery in repo.recoveriesForReceivableAsset(asset.id)) {
        events.add(_LendingEvent(
          date: recovery.recoveredAt,
          label: '收回',
          amount: recovery.amount,
        ));
      }
    }
    for (final profile in borrows) {
      final open = profile.status == LiabilityProfileStatus.active &&
          profile.currentPrincipal > Decimal.zero;
      if (open) borrowedRemaining += profile.currentPrincipal;
      events.add(_LendingEvent(
        date: profile.startDate ??
            DateTime.fromMillisecondsSinceEpoch(profile.createdMs),
        label: '借入',
        amount: profile.originalAmount,
        // 老档案没记起始日时只能用登记时间，如实标注。
        annotation: profile.startDateMs == null ? '按登记时间' : null,
        repayProfile: open ? profile : null,
      ));
      // 还款 = 转入借入账户的真实转账（借入到账那笔是从该账户转出，
      // 已由上面的「借入」行表达，这里不重复显示）。
      for (final transfer in repo.transfersInvolvingAccount(profile.accountId)) {
        if (transfer.toAccountId != profile.accountId) continue;
        events.add(_LendingEvent(
          date: transfer.date,
          label: '还款',
          amount: transfer.amount,
        ));
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));
  }
}

class _LendingEvent {
  final DateTime date;
  final String label;
  final Decimal amount;
  final String? annotation;
  final ReceivableAssetEntity? recoverAsset;
  final LiabilityProfileEntity? repayProfile;

  const _LendingEvent({
    required this.date,
    required this.label,
    required this.amount,
    this.annotation,
    this.recoverAsset,
    this.repayProfile,
  });
}

class _PartyCard extends StatelessWidget {
  final _LendingParty party;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ReceivableAssetEntity> onRecover;
  final ValueChanged<LiabilityProfileEntity> onRepay;

  const _PartyCard({
    required this.party,
    required this.expanded,
    required this.onToggle,
    required this.onRecover,
    required this.onRepay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = party.net;
    final bothSides = party.lentRemaining > Decimal.zero &&
        party.borrowedRemaining > Decimal.zero;
    final (statusText, amountColor) = net > Decimal.zero
        ? ('TA欠我', kCatGold)
        : net < Decimal.zero
            ? ('我欠TA', scheme.onSurface)
            : ('已结清', AppTextColor.secondary(scheme));
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('lending-party-${party.name}'),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                      Icons.person_outline,
                      size: 18,
                      color: AppTextColor.secondary(scheme),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          party.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.rowTitle(scheme),
                        ),
                        if (bothSides) ...[
                          const SizedBox(height: 2),
                          Text.rich(
                            // 两边都有剩余时给出两侧毛额，净额不藏毛额。
                            digitAwareAmountSpan(
                              '借出剩 ${MoneyFormat.string(party.lentRemaining)}'
                              ' · 借入剩 '
                              '${MoneyFormat.string(party.borrowedRemaining)}',
                              AppType.caption(scheme),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(statusText, style: AppType.caption(scheme)),
                      if (net != Decimal.zero) ...[
                        const SizedBox(height: 1),
                        Text(
                          MoneyFormat.string(net.abs()),
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: amountColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppTextColor.hint(scheme),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final event in party.events) ...[
              appCardDivider(scheme),
              _EventRow(
                event: event,
                onRecover: onRecover,
                onRepay: onRepay,
              ),
            ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final _LendingEvent event;
  final ValueChanged<ReceivableAssetEntity> onRecover;
  final ValueChanged<LiabilityProfileEntity> onRepay;

  const _EventRow({
    required this.event,
    required this.onRecover,
    required this.onRepay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      assetDateText(event.date),
      if (event.annotation != null) event.annotation!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.label, style: AppType.body(scheme)),
                const SizedBox(height: 2),
                Text.rich(
                  digitAwareAmountSpan(subtitle, AppType.caption(scheme)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            MoneyFormat.string(event.amount),
            style: AppType.body(scheme).copyWith(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w600,
            ),
          ),
          if (event.recoverAsset != null) ...[
            const SizedBox(width: 10),
            AppPillButton(
              key: Key('lending-recover-${event.recoverAsset!.id}'),
              label: '收回',
              onPressed: () => onRecover(event.recoverAsset!),
            ),
          ],
          if (event.repayProfile != null) ...[
            const SizedBox(width: 10),
            AppPillButton(
              key: Key('lending-repay-${event.repayProfile!.id}'),
              label: '还款',
              onPressed: () => onRepay(event.repayProfile!),
            ),
          ],
        ],
      ),
    );
  }
}
