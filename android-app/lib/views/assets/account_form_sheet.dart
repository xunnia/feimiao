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
import 'loan_wizard_sheet.dart';

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
  late final TextEditingController _creditLimitCtrl;
  late final TextEditingController _liabilityNoteCtrl;
  late AccountType _type;
  late bool _includeInNetWorth;
  bool _saving = false;
  late LiabilityProfileType _liabilityType;
  late LiabilityProfileStatus _liabilityStatus;
  int? _repaymentAccountId;
  int? _repaymentDay;
  int? _statementDay;

  /// 编辑时已存在的负债档案；保存时把本表单不管的字段（counterparty、
  /// 起止日期）原样透传，别把 A2 借贷侧写进去的数据抹掉。
  LiabilityProfileEntity? _profile;

  bool get _editing => widget.account != null;

  /// 信用卡账期字段（账单日/额度）只对信用卡档案有意义，别的负债类型
  /// 展示这些字段就是引导用户填没意义的数。
  bool get _isCreditCard => _liabilityType == LiabilityProfileType.creditCard;

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
    _profile = profile;
    _liabilityOriginalCtrl =
        TextEditingController(text: profile?.originalAmount.toString() ?? '');
    _liabilityPrincipalCtrl =
        TextEditingController(text: profile?.currentPrincipal.toString() ?? '');
    _liabilityRateCtrl =
        TextEditingController(text: profile?.interestRate.toString() ?? '');
    _creditLimitCtrl =
        TextEditingController(text: profile?.creditLimit?.toString() ?? '');
    _liabilityNoteCtrl = TextEditingController(text: profile?.note ?? '');
    _liabilityType = profile?.type ??
        (_type == AccountType.credit
            ? LiabilityProfileType.creditCard
            : LiabilityProfileType.other);
    _liabilityStatus = profile?.status ?? LiabilityProfileStatus.active;
    _repaymentAccountId = profile?.repaymentAccountId;
    _repaymentDay = profile?.repaymentDay;
    _statementDay = profile?.statementDay;
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
    _creditLimitCtrl.dispose();
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
                                  // 「个人借入」档案由借贷流程创建（带对象、
                                  // 一次性还款日语义），不在账户表单里手选；
                                  // 已是借入档案的编辑时保留可见。
                                  values: [
                                    for (final type
                                        in LiabilityProfileType.values)
                                      if (type !=
                                              LiabilityProfileType
                                                  .personalBorrow ||
                                          _liabilityType == type)
                                        type,
                                  ],
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
                              if (_isCreditCard) ...[
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '账单日（可选）',
                                  child: AssetDayOfMonthDropdown(
                                    key: const Key('liability-statement-day'),
                                    value: _statementDay,
                                    hint: '选择每月出账日',
                                    onChanged: (value) =>
                                        setState(() => _statementDay = value),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '还款日（可选）',
                                child: AssetDayOfMonthDropdown(
                                  key: const Key('liability-repayment-day'),
                                  value: _repaymentDay,
                                  hint: '选择每月还款日',
                                  onChanged: (value) =>
                                      setState(() => _repaymentDay = value),
                                ),
                              ),
                              if (_isCreditCard) ...[
                                const SizedBox(height: 12),
                                AppLabeledField(
                                  label: '信用额度（可选）',
                                  child: TextField(
                                    key: const Key('liability-credit-limit'),
                                    controller: _creditLimitCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: moneyInputFormatters(),
                                    decoration: iosInputDecoration(
                                      context,
                                      prefix: '¥ ',
                                      hint: '例如 20000',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              AppLabeledField(
                                label: '还款账户（可选）',
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
                                  text: '负债金额、额度和利率不能为负。',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 新建贷款账户时给向导指路：账户+档案+每月自动还款一次设好。
                  if (!_editing && _type == AccountType.loan) ...[
                    const SizedBox(height: 14),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          key: const Key('account-form-loan-wizard'),
                          leading: const Icon(Icons.home_work_outlined),
                          title: '要按月自动记还款？',
                          subtitle: '用房贷/分期向导，一次设好这三样',
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: _openLoanWizard,
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

  /// 关掉本表单再开向导（同屏只留一层弹层）；跳转用 NavigatorState，
  /// 本表单 pop 之后 context 就没了。
  void _openLoanWizard() {
    final navigator = Navigator.of(context);
    Navigator.pop(context);
    Future.microtask(() {
      final ctx = navigator.context;
      if (!ctx.mounted) return;
      showLoanWizardSheet(ctx);
    });
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
          if (_isCreditCard) _creditLimitCtrl.text,
          _liabilityNoteCtrl.text,
        ].any((text) => text.trim().isNotEmpty) ||
        _repaymentDay != null ||
        (_isCreditCard && _statementDay != null) ||
        _repaymentAccountId != null ||
        _profile != null;
    if (!hasAny) return;
    final creditLimitText = _creditLimitCtrl.text.trim().replaceAll(',', '');
    await repo.upsertLiabilityProfile(
      accountId: accountId,
      type: _liabilityType,
      originalAmount: _parseDecimal(_liabilityOriginalCtrl.text),
      currentPrincipal: _parseDecimal(_liabilityPrincipalCtrl.text),
      interestRate: _parseDecimal(_liabilityRateCtrl.text),
      repaymentDay: _repaymentDay,
      repaymentAccountId: _repaymentAccountId,
      status: _liabilityStatus,
      note: _liabilityNoteCtrl.text,
      // 账期两字段只对信用卡有意义；类型改成别的负债时一并清空，
      // 不留一个「房贷带账单日」的假数据。
      statementDay: _isCreditCard ? _statementDay : null,
      creditLimit: _isCreditCard && creditLimitText.isNotEmpty
          ? Decimal.tryParse(creditLimitText)
          : null,
      // 本表单不管的字段原样透传，别抹掉借贷侧写入的数据。
      startDate: _profile?.startDate,
      endDate: _profile?.endDate,
      counterparty: _profile?.counterparty ?? '',
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
      if (_isCreditCard) _creditLimitCtrl.text,
    ];
    for (final field in fields) {
      final normalized = field.trim().replaceAll(',', '');
      if (normalized.isEmpty) continue;
      final value = Decimal.tryParse(normalized);
      if (value == null || value < Decimal.zero) return false;
    }
    return true;
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
