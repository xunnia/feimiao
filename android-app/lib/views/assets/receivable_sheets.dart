// 权益(应收)资产弹层：新建/编辑表单、收回、状态复核（从 accounts_view.dart 拆出）。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

String _receivableEconomicLabel(ReceivableEconomicStatus value) =>
    switch (value) {
      ReceivableEconomicStatus.active => '待收回',
      ReceivableEconomicStatus.partialRecovered => '部分收回',
      ReceivableEconomicStatus.recovered => '已收回',
      ReceivableEconomicStatus.lost => '已损失',
      ReceivableEconomicStatus.unknown => '暂不确定',
    };

IconData _receivableEconomicIcon(ReceivableEconomicStatus value) =>
    switch (value) {
      ReceivableEconomicStatus.active => Icons.schedule_outlined,
      ReceivableEconomicStatus.partialRecovered => Icons.pie_chart_outline,
      ReceivableEconomicStatus.recovered => Icons.check_circle_outline,
      ReceivableEconomicStatus.lost => Icons.money_off_outlined,
      ReceivableEconomicStatus.unknown => Icons.help_outline,
    };

class ReceivableReviewSheet extends StatefulWidget {
  final ReceivableAssetEntity asset;

  const ReceivableReviewSheet({super.key, required this.asset});

  @override
  State<ReceivableReviewSheet> createState() => _ReceivableReviewSheetState();
}

class _ReceivableReviewSheetState extends State<ReceivableReviewSheet> {
  late ReceivableEconomicStatus _economicStatus;
  late bool _includeInNetWorth;
  bool _saving = false;

  List<ReceivableEconomicStatus> get _allowedStatuses {
    if (widget.asset.remainingAmount <= Decimal.zero) {
      return const [
        ReceivableEconomicStatus.recovered,
        ReceivableEconomicStatus.lost,
        ReceivableEconomicStatus.unknown,
      ];
    }
    if (widget.asset.remainingAmount < widget.asset.originalAmount) {
      return const [
        ReceivableEconomicStatus.partialRecovered,
        ReceivableEconomicStatus.unknown,
      ];
    }
    return const [
      ReceivableEconomicStatus.active,
      ReceivableEconomicStatus.unknown,
    ];
  }

  bool get _canCountInNetWorth =>
      _economicStatus == ReceivableEconomicStatus.active ||
      _economicStatus == ReceivableEconomicStatus.partialRecovered;

  @override
  void initState() {
    super.initState();
    final allowed = _allowedStatuses;
    _economicStatus = allowed.contains(widget.asset.economicStatus)
        ? widget.asset.economicStatus
        : allowed.first;
    _includeInNetWorth = _canCountInNetWorth && widget.asset.includeInNetWorth;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '确认权益状态',
            subtitle: '请根据剩余金额确认这项权益现在的真实状态。',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: _saving ? null : _save,
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              SettingsRow(
                title: '经济状态',
                subtitle:
                    '剩余 ${MoneyFormat.string(widget.asset.remainingAmount, currencyCode: widget.asset.currencyCode)}',
                trailing: AssetMenuFilterButton<ReceivableEconomicStatus>(
                  value: _economicStatus,
                  values: _allowedStatuses,
                  labelOf: _receivableEconomicLabel,
                  iconOf: _receivableEconomicIcon,
                  onChanged: (value) => setState(() {
                    _economicStatus = value;
                    if (!_canCountInNetWorth) _includeInNetWorth = false;
                  }),
                ),
              ),
              SettingsRow(
                title: '计入净资产',
                subtitle:
                    _canCountInNetWorth ? '按剩余金额进入人民币净资产合计' : '已结束或暂不确定的权益不能计入',
                trailing: AppSwitch(
                  value: _includeInNetWorth,
                  onChanged: _canCountInNetWorth
                      ? (value) => setState(() => _includeInNetWorth = value)
                      : null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: Text(
              '确认不会生成收支或到账流水，归档状态也会保持不变。',
              style: AppType.caption(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().confirmReceivableAssetState(
            widget.asset.id,
            economicStatus: _economicStatus,
            includeInNetWorth: _includeInNetWorth,
          );
      if (!mounted) return;
      showAppToast(context, '已确认「${widget.asset.name}」');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class ReceivableAssetFormSheet extends StatefulWidget {
  final ReceivableAssetEntity? asset;

  const ReceivableAssetFormSheet({super.key, this.asset});

  @override
  State<ReceivableAssetFormSheet> createState() =>
      _ReceivableAssetFormSheetState();
}

class _ReceivableAssetFormSheetState extends State<ReceivableAssetFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _originalCtrl;
  late final TextEditingController _remainingCtrl;
  late final TextEditingController _counterpartyCtrl;
  late final TextEditingController _noteCtrl;
  late ReceivableAssetType _type;
  late ReceivableAssetStatus _status;
  late bool _includeInNetWorth;
  bool _saving = false;

  bool get _editing => widget.asset != null;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _nameCtrl = TextEditingController(text: asset?.name ?? '');
    _originalCtrl =
        TextEditingController(text: asset?.originalAmount.toString() ?? '');
    _remainingCtrl =
        TextEditingController(text: asset?.remainingAmount.toString() ?? '');
    _counterpartyCtrl = TextEditingController(text: asset?.counterparty ?? '');
    _noteCtrl = TextEditingController(text: asset?.note ?? '');
    _type = asset?.type ?? ReceivableAssetType.rentalDeposit;
    _status = asset?.status ?? ReceivableAssetStatus.active;
    _includeInNetWorth = asset?.includeInNetWorth ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _originalCtrl.dispose();
    _remainingCtrl.dispose();
    _counterpartyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final original = parseAssetDecimalInput(_originalCtrl.text);
    final remaining = parseAssetDecimalInput(_remainingCtrl.text);
    final valid = _nameCtrl.text.trim().isNotEmpty &&
        assetDecimalInputValid(_originalCtrl.text, required: true) &&
        assetDecimalInputValid(_remainingCtrl.text, required: true) &&
        original >= Decimal.zero &&
        remaining >= Decimal.zero &&
        remaining <= original;
    final screenH = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: _editing ? '编辑权益资产' : '添加权益资产',
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
                      label: '权益名称',
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        decoration:
                            iosInputDecoration(context, hint: '例如 房租押金'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '权益类型',
                      child: AssetEnumDropdown<ReceivableAssetType>(
                        value: _type,
                        values: ReceivableAssetType.values,
                        labelOf: (value) => value.label,
                        hint: '选择类型',
                        onChanged: (value) => setState(() => _type = value),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '原始金额',
                      child: TextField(
                        controller: _originalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: moneyInputFormatters(),
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: '例如 2000',
                        ),
                        onChanged: (_) {
                          if (!_editing) {
                            _remainingCtrl.text = _originalCtrl.text;
                          }
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '剩余可收回金额',
                      child: TextField(
                        controller: _remainingCtrl,
                        readOnly: _editing,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: moneyInputFormatters(),
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: '例如 2000',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppLabeledField(
                      label: '对方/机构（可选）',
                      child: TextField(
                        controller: _counterpartyCtrl,
                        decoration:
                            iosInputDecoration(context, hint: '例如 房东、健身房'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_editing) ...[
                      const AssetHintBox(
                        text: '剩余金额和状态请通过收回、损失、归档或恢复操作修改。',
                      ),
                      const SizedBox(height: 14),
                    ],
                    AppLabeledField(
                      label: '备注（可选）',
                      child: TextField(
                        controller: _noteCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration:
                            iosInputDecoration(context, hint: '押金合同、约定日期等'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          title: '计入净资产',
                          subtitle: '关闭后仍保留权益记录，但不进入净资产合计',
                          trailing: AppSwitch(
                            value: _includeInNetWorth,
                            onChanged: (v) =>
                                setState(() => _includeInNetWorth = v),
                          ),
                        ),
                      ],
                    ),
                    if (remaining > original) ...[
                      const SizedBox(height: 12),
                      const AssetHintBox(text: '剩余可收回金额不能超过原始金额。'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final repo = context.read<AppRepository>();
      final original = parseAssetDecimalInput(_originalCtrl.text);
      final remaining = parseAssetDecimalInput(_remainingCtrl.text);
      if (_editing) {
        await repo.updateReceivableAsset(
          id: widget.asset!.id,
          name: _nameCtrl.text,
          type: _type,
          originalAmount: original,
          remainingAmount: remaining,
          status: _status,
          counterparty: _counterpartyCtrl.text,
          includeInNetWorth: _includeInNetWorth,
          note: _noteCtrl.text,
        );
      } else {
        await repo.addReceivableAsset(
          name: _nameCtrl.text,
          type: _type,
          originalAmount: original,
          remainingAmount: remaining,
          counterparty: _counterpartyCtrl.text,
          includeInNetWorth: _includeInNetWorth,
          note: _noteCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }
}

class ReceivableRecoverySheet extends StatefulWidget {
  final ReceivableAssetEntity asset;

  const ReceivableRecoverySheet({super.key, required this.asset});

  @override
  State<ReceivableRecoverySheet> createState() =>
      _ReceivableRecoverySheetState();
}

class _ReceivableRecoverySheetState extends State<ReceivableRecoverySheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  int? _accountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.asset.remainingAmount.toString());
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    _accountId ??= repo.accounts.firstOrNull?.id;
    final amount = parseAssetDecimalInput(_amountCtrl.text);
    final valid = assetDecimalInputValid(_amountCtrl.text, required: true) &&
        amount > Decimal.zero &&
        amount <= widget.asset.remainingAmount &&
        _accountId != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '收回权益',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppLabeledField(
                  label: '收回金额',
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(
                      context,
                      prefix: '¥ ',
                      hint: '例如 500',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '到账账户',
                  child: AssetAccountDropdown(
                    value: _accountId,
                    accounts: repo.accounts,
                    hint: '选择到账账户',
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '备注（可选）',
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: iosInputDecoration(context, hint: '例如 退租结清'),
                  ),
                ),
                const SizedBox(height: 12),
                const AssetHintBox(
                  text: '收回会增加到账账户余额，并减少权益资产剩余金额；这不是普通收入，不会进入收入统计。',
                ),
              ],
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
      await context.read<AppRepository>().recoverReceivableAsset(
            id: widget.asset.id,
            amount: parseAssetDecimalInput(_amountCtrl.text),
            targetAccountId: _accountId,
            note: _noteCtrl.text,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }
}
