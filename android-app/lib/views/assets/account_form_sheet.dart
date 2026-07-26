// 账户新建/编辑表单弹层（含负债详情与类型选择），从 accounts_view.dart 拆出。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

class AccountFormSheet extends StatefulWidget {
  final AccountEntity? account;

  const AccountFormSheet({super.key, this.account});

  @override
  State<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<AccountFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _institutionCtrl;
  late final TextEditingController _liabilityOriginalCtrl;
  late final TextEditingController _liabilityPrincipalCtrl;
  late final TextEditingController _liabilityRateCtrl;
  late final TextEditingController _repaymentDayCtrl;
  late final TextEditingController _liabilityNoteCtrl;
  late AccountType _type;
  late bool _includeInNetWorth;
  bool _saving = false;
  late LiabilityProfileType _liabilityType;
  late LiabilityProfileStatus _liabilityStatus;
  int? _repaymentAccountId;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameCtrl = TextEditingController(text: account?.name ?? '');
    _currencyCtrl = TextEditingController(text: account?.currencyCode ?? 'CNY');
    _openingCtrl =
        TextEditingController(text: account?.openingBalance.toString() ?? '');
    _institutionCtrl = TextEditingController(text: account?.institution ?? '');
    _type = account?.type ?? AccountType.cash;
    _includeInNetWorth = account?.includeInNetWorth ?? true;
    final profile = account == null
        ? null
        : context.read<AppRepository>().liabilityProfileForAccount(account.id);
    _liabilityOriginalCtrl =
        TextEditingController(text: profile?.originalAmount.toString() ?? '');
    _liabilityPrincipalCtrl =
        TextEditingController(text: profile?.currentPrincipal.toString() ?? '');
    _liabilityRateCtrl =
        TextEditingController(text: profile?.interestRate.toString() ?? '');
    _repaymentDayCtrl =
        TextEditingController(text: profile?.repaymentDay?.toString() ?? '');
    _liabilityNoteCtrl = TextEditingController(text: profile?.note ?? '');
    _liabilityType = profile?.type ??
        (_type == AccountType.credit
            ? LiabilityProfileType.creditCard
            : LiabilityProfileType.other);
    _liabilityStatus = profile?.status ?? LiabilityProfileStatus.active;
    _repaymentAccountId = profile?.repaymentAccountId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    _openingCtrl.dispose();
    _institutionCtrl.dispose();
    _liabilityOriginalCtrl.dispose();
    _liabilityPrincipalCtrl.dispose();
    _liabilityRateCtrl.dispose();
    _repaymentDayCtrl.dispose();
    _liabilityNoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final valid = _nameCtrl.text.trim().isNotEmpty &&
        _openingBalanceInputValid &&
        _liabilityInputValid;
    final screenH = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: _editing ? '编辑账户' : '新增账户',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLabeledField(
                    label: '账户名称',
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: iosInputDecoration(context, hint: '例如 招行储蓄卡'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '账户类型',
                    child: _AccountTypePicker(
                      value: _type,
                      onChanged: (next) => setState(() {
                        _type = next;
                        if (next == AccountType.credit) {
                          _liabilityType = LiabilityProfileType.creditCard;
                        } else if (next == AccountType.loan &&
                            _liabilityType == LiabilityProfileType.creditCard) {
                          _liabilityType = LiabilityProfileType.other;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '币种',
                    child: AppReadOnlyField(
                      text: _currencyCtrl.text == 'CNY'
                          ? '人民币'
                          : '${_currencyCtrl.text}（仅保留，不计入净资产）',
                      icon: Icons.currency_yuan,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: _type.liability ? '当前欠款' : '期初余额',
                    helperText:
                        _editing ? '期初余额用于建立账户起点，修改当前余额请在账户详情选择“校准余额”。' : null,
                    child: TextField(
                      controller: _openingCtrl,
                      readOnly: _editing,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      inputFormatters:
                          moneyInputFormatters(allowNegative: true),
                      decoration: iosInputDecoration(
                        context,
                        prefix: '¥ ',
                        hint: _type.liability ? '例如 -3000（可填负数）' : '例如 1000',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '机构/银行（可选）',
                    child: TextField(
                      controller: _institutionCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: iosInputDecoration(context, hint: '例如 招商银行'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      SettingsRow(
                        title: '计入净资产',
                        subtitle: '关闭后仍显示账户，但不计入顶部合计',
                        trailing: AppSwitch(
                          value: _includeInNetWorth,
                          onChanged: (value) =>
                              setState(() => _includeInNetWorth = value),
                        ),
                      ),
                    ],
                  ),
                  if (_type.liability) ...[
                    const SizedBox(height: 14),
                    AssetDetailSection(
                      title: '负债详情',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppLabeledField(
                                label: '负债类型',
                                child: AssetEnumDropdown<LiabilityProfileType>(
                                  value: _liabilityType,
                                  values: LiabilityProfileType.values,
                                  labelOf: (value) => value.label,
                                  hint: '选择类型',
                                  onChanged: (value) =>
                                      setState(() => _liabilityType = value),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '原始金额（可选）',
                                child: TextField(
                                  controller: _liabilityOriginalCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: moneyInputFormatters(),
                                  decoration: iosInputDecoration(
                                    context,
                                    prefix: '¥ ',
                                    hint: '例如 12000',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '剩余本金/当前欠款（可选）',
                                child: TextField(
                                  controller: _liabilityPrincipalCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters:
                                      moneyInputFormatters(allowNegative: true),
                                  decoration: iosInputDecoration(
                                    context,
                                    prefix: '¥ ',
                                    hint: '例如 8000',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '年化利率 %（可选）',
                                child: TextField(
                                  controller: _liabilityRateCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '例如 3.5',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '每月还款日（可选）',
                                child: TextField(
                                  controller: _repaymentDayCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: iosInputDecoration(
                                    context,
                                    hint: '1-31，例如 9',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '默认还款账户（可选）',
                                child: AssetAccountDropdown(
                                  value: _repaymentAccountId,
                                  accounts: repo.accounts
                                      .where((a) => a.id != widget.account?.id)
                                      .toList(),
                                  hint: '选择账户',
                                  onChanged: (value) => setState(
                                      () => _repaymentAccountId = value),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '负债状态',
                                child:
                                    AssetEnumDropdown<LiabilityProfileStatus>(
                                  value: _liabilityStatus,
                                  values: LiabilityProfileStatus.values,
                                  labelOf: (value) => value.label,
                                  hint: '选择状态',
                                  onChanged: (value) =>
                                      setState(() => _liabilityStatus = value),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '负债备注（可选）',
                                child: TextField(
                                  controller: _liabilityNoteCtrl,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: iosInputDecoration(context,
                                      hint: '例如 房贷、分期说明'),
                                ),
                              ),
                              if (!_liabilityInputValid) ...[
                                const SizedBox(height: 10),
                                const AssetHintBox(
                                  text: '负债金额和利率不能为负；还款日必须在 1 到 31 之间。',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final opening = _parseDecimal(_openingCtrl.text);
      final currency = _currencyCtrl.text.trim().toUpperCase();
      final repo = context.read<AppRepository>();
      late int accountId;
      if (_editing) {
        accountId = widget.account!.id;
        await repo.updateAccount(
          id: accountId,
          name: _nameCtrl.text.trim(),
          currencyCode: currency.isEmpty ? 'CNY' : currency,
          type: _type,
          openingBalance: opening,
          includeInNetWorth: _includeInNetWorth,
          institution: _institutionCtrl.text.trim(),
        );
      } else {
        accountId = await repo.addAccount(
          name: _nameCtrl.text.trim(),
          currencyCode: currency.isEmpty ? 'CNY' : currency,
          type: _type,
          openingBalance: opening,
          includeInNetWorth: _includeInNetWorth,
          institution: _institutionCtrl.text.trim(),
        );
      }
      await _saveLiabilityProfile(repo, accountId);
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveLiabilityProfile(AppRepository repo, int accountId) async {
    if (!_type.liability) {
      await repo.deleteLiabilityProfileForAccount(accountId);
      return;
    }
    final hasAny = [
      _liabilityOriginalCtrl.text,
      _liabilityPrincipalCtrl.text,
      _liabilityRateCtrl.text,
      _repaymentDayCtrl.text,
      _liabilityNoteCtrl.text,
    ].any((text) => text.trim().isNotEmpty);
    if (!hasAny) return;
    await repo.upsertLiabilityProfile(
      accountId: accountId,
      type: _liabilityType,
      originalAmount: _parseDecimal(_liabilityOriginalCtrl.text),
      currentPrincipal: _parseDecimal(_liabilityPrincipalCtrl.text),
      interestRate: _parseDecimal(_liabilityRateCtrl.text),
      repaymentDay: int.tryParse(_repaymentDayCtrl.text.trim()),
      repaymentAccountId: _repaymentAccountId,
      status: _liabilityStatus,
      note: _liabilityNoteCtrl.text,
    );
  }

  Decimal _parseDecimal(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    if (normalized.isEmpty) return Decimal.zero;
    return Decimal.tryParse(normalized) ?? Decimal.zero;
  }

  bool get _openingBalanceInputValid {
    final normalized = _openingCtrl.text.trim().replaceAll(',', '');
    return normalized.isEmpty || Decimal.tryParse(normalized) != null;
  }

  bool get _liabilityInputValid {
    if (!_type.liability) return true;
    final fields = [
      _liabilityOriginalCtrl.text,
      _liabilityPrincipalCtrl.text,
      _liabilityRateCtrl.text,
    ];
    for (final field in fields) {
      final normalized = field.trim().replaceAll(',', '');
      if (normalized.isEmpty) continue;
      final value = Decimal.tryParse(normalized);
      if (value == null || value < Decimal.zero) return false;
    }
    final dayText = _repaymentDayCtrl.text.trim();
    if (dayText.isEmpty) return true;
    final day = int.tryParse(dayText);
    return day != null && day >= 1 && day <= 31;
  }
}

class _AccountTypePicker extends StatelessWidget {
  final AccountType value;
  final ValueChanged<AccountType> onChanged;

  const _AccountTypePicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in AccountType.values)
          _TypeChip(
            type: type,
            selected: value == type,
            onTap: () => onChanged(type),
          ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 选中态走主色（UI 标准：强调/选中 = scheme.primary）+ 按压反馈。
    return PressableScale(
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : AppColors.hairline(scheme),
          ),
        ),
        child: Text(
          type.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color:
                    selected ? scheme.primary : AppTextColor.secondary(scheme),
              ),
        ),
      ),
    );
  }
}
