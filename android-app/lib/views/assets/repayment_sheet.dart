// 还款弹层（A 批 A1）：从「最近要还」卡进入，一笔转账把钱划去负债账户。
//
// 语义与数据诚实性（跟 repo.repayLiabilityProfile 契约一致）：
// - 档案有剩余本金：本金部分记转账并递减档案本金，超出部分自动记利息支出，
//   保存后的提示会如实带上「其中利息 ¥X」。
// - 信用卡这类档案本金为 0 的：整笔就是转账，不会编造利息。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

class RepaymentSheet extends StatefulWidget {
  final LiabilityProfileEntity profile;

  const RepaymentSheet({super.key, required this.profile});

  @override
  State<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends State<RepaymentSheet> {
  late final TextEditingController _amountCtrl;
  int? _fromAccountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    // 预填口径（能回答「哪来的」）：档案剩余本金 > 0 就填它；
    // 本金为 0（信用卡欠款挂在账户负余额上）就填负余额的绝对值；都没有留空。
    var prefill = '';
    if (widget.profile.currentPrincipal > Decimal.zero) {
      prefill = widget.profile.currentPrincipal.toString();
    } else {
      final account = repo.accounts
          .where((a) => a.id == widget.profile.accountId && !a.isDeleted)
          .firstOrNull;
      if (account != null) {
        final balance = repo.accountBalanceOf(account);
        if (balance < Decimal.zero) prefill = (-balance).toString();
      }
    }
    _amountCtrl = TextEditingController(text: prefill);
    // 付款账户默认 = 档案上的还款账户（得仍在可选列表里才算数）。
    final defaultFrom = widget.profile.repaymentAccountId;
    if (defaultFrom != null &&
        _payerAccounts(repo).any((a) => a.id == defaultFrom)) {
      _fromAccountId = defaultFrom;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  /// 可当付款账户的：未删未归档的 CNY 账户，且不能是负债账户本身。
  List<AccountEntity> _payerAccounts(AppRepository repo) => repo.accounts
      .where((a) =>
          !a.isDeleted &&
          !a.isArchived &&
          a.currencyCode == 'CNY' &&
          a.id != widget.profile.accountId)
      .toList();

  Decimal? get _amount {
    final normalized = _amountCtrl.text.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    final value = Decimal.tryParse(normalized);
    if (value == null || value <= Decimal.zero) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final liabilityAccount = repo.accounts
        .where((a) => a.id == widget.profile.accountId && !a.isDeleted)
        .firstOrNull;
    final principal = widget.profile.currentPrincipal;
    final canSave = !_saving && _amount != null && _fromAccountId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: '还款',
          subtitle: liabilityAccount?.name,
          onClose: () => Navigator.pop(context),
          actionLabel: '确认',
          actionKey: const Key('repayment-confirm'),
          onAction: canSave ? _save : null,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppLabeledField(
                  label: '还款金额',
                  child: TextField(
                    key: const Key('repayment-amount'),
                    controller: _amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: moneyInputFormatters(),
                    decoration:
                        iosInputDecoration(context, prefix: '¥ ', hint: '0.00'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '付款账户',
                  child: AssetAccountDropdown(
                    value: _fromAccountId,
                    accounts: _payerAccounts(repo),
                    hint: '选择账户',
                    onChanged: (value) =>
                        setState(() => _fromAccountId = value),
                  ),
                ),
                if (principal > Decimal.zero) ...[
                  const SizedBox(height: 12),
                  Text(
                    '剩余本金 ${MoneyFormat.string(principal)}；'
                    '超出本金的部分会自动记成一笔利息支出。',
                    style: AppType.caption(scheme),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final amount = _amount;
    final fromAccountId = _fromAccountId;
    if (amount == null || fromAccountId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await context.read<AppRepository>().repayLiabilityProfile(
            profileId: widget.profile.id,
            amount: amount,
            fromAccountId: fromAccountId,
          );
      if (!mounted) return;
      showAppToast(
        context,
        result.interestPaid > Decimal.zero
            ? '已还款，其中利息 ${MoneyFormat.string(result.interestPaid)}'
            : '已还款',
        mascot: MascotMood.success,
      );
      Navigator.pop(context);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      showAppToast(context, '${error.message}', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
