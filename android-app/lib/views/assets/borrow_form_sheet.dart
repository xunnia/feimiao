// 记一笔借入（A 批 A2 借贷按人）：对象姓名+金额必填，入账账户/还款日/备注可选。
//
// 数据语义（跟 repo.addPersonalBorrow 契约一致，别在 UI 里另编一套）：
// - 保存会创建一个「借入·对象名」贷款账户 + personalBorrow 负债档案；
// - 选了入账账户：另记一笔转账（借入账户 → 入账账户），钱的去向有账可查；
//   没选：借入账户期初余额直接记 -金额，不编造到账流水。
// - 还款日是一次性到期日（进「最近要还」，逾期会标出来）。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

class BorrowFormSheet extends StatefulWidget {
  const BorrowFormSheet({super.key});

  @override
  State<BorrowFormSheet> createState() => _BorrowFormSheetState();
}

class _BorrowFormSheetState extends State<BorrowFormSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int? _toAccountId;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Decimal? get _amount {
    final normalized = _amountCtrl.text.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    final value = Decimal.tryParse(normalized);
    if (value == null || value <= Decimal.zero) return null;
    return value;
  }

  /// 可当入账账户的：未删未归档的 CNY 账户（贷款/信用卡也允许——
  /// 借钱还卡是真实场景）。
  List<AccountEntity> _targetAccounts(AppRepository repo) => repo.accounts
      .where((a) => !a.isDeleted && !a.isArchived && a.currencyCode == 'CNY')
      .toList();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final canSave =
        !_saving && _nameCtrl.text.trim().isNotEmpty && _amount != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: '记一笔借入',
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          actionKey: const Key('borrow-save'),
          onAction: canSave ? _save : null,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppLabeledField(
                  label: '对象姓名',
                  child: TextField(
                    key: const Key('borrow-counterparty'),
                    controller: _nameCtrl,
                    autofocus: true,
                    decoration: iosInputDecoration(context, hint: '例如 张三'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '借入金额',
                  child: TextField(
                    key: const Key('borrow-amount'),
                    controller: _amountCtrl,
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
                  label: '入账账户（可选）',
                  child: AssetAccountDropdown(
                    value: _toAccountId,
                    accounts: _targetAccounts(repo),
                    hint: '钱进了哪个账户',
                    allowNone: true,
                    noneLabel: '不记入账',
                    onChanged: (value) => setState(() => _toAccountId = value),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '还款日（可选）',
                  child: AssetNullableDateField(
                    fieldKey: const Key('borrow-due-date'),
                    value: _dueDate,
                    emptyText: '约定哪天还',
                    onTap: _pickDueDate,
                    onClear: _dueDate == null
                        ? null
                        : () => setState(() => _dueDate = null),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '备注（可选）',
                  child: TextField(
                    controller: _noteCtrl,
                    decoration:
                        iosInputDecoration(context, hint: '例如 应急周转'),
                  ),
                ),
                const SizedBox(height: 12),
                const AssetHintBox(
                  text: '保存后会新建一个「借入·对象名」贷款账户表示这笔欠款；'
                      '选了入账账户会同时记一笔转入。还款走「借贷往来」或'
                      '「最近要还」里的还款。',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final selected = await showAppDatePicker(
      context,
      initial: _dueDate ?? now,
      first: DateTime(now.year - 1),
      last: DateTime(now.year + 10, 12, 31),
      title: '还款日',
    );
    if (selected != null && mounted) {
      setState(() => _dueDate = selected);
    }
  }

  Future<void> _save() async {
    final amount = _amount;
    if (amount == null || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().addPersonalBorrow(
            counterparty: _nameCtrl.text,
            amount: amount,
            toAccountId: _toAccountId,
            dueDate: _dueDate,
            note: _noteCtrl.text,
          );
      if (!mounted) return;
      // showAppToast 走 rootOverlay，pop 前调用能存活到弹层关闭后。
      showAppToast(context, '已记借入', mascot: MascotMood.success);
      Navigator.pop(context);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      showAppToast(context, '${error.message}', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
