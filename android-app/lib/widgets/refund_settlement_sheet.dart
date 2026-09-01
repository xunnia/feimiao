import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/account/account_movement_projection.dart';
import '../core/money_format.dart';
import '../data/app_repository.dart';
import '../theme/app_tokens.dart';
import '../views/common/app_sheet.dart';
import 'app_buttons.dart';
import 'app_date_picker.dart';
import 'app_picker_field.dart';
import 'app_toast.dart';
import 'ios_dialogs.dart';
import 'ios_form.dart';
import 'ios_menu.dart';
import 'settings_ui.dart';

class RefundSettlementResult {
  final Decimal amount;
  final DateTime settledAt;
  final int settlementAccountId;

  const RefundSettlementResult({
    required this.amount,
    required this.settledAt,
    required this.settlementAccountId,
  });
}

Future<RefundSettlementResult?> showRefundSettlementSheet(
  BuildContext context, {
  required TransactionEntity original,
  required Decimal initialAmount,
  required Decimal maxAmount,
  bool amountEditable = true,
  String title = '退款',
  String confirmLabel = '确认退款',
  List<TransactionEntity> existingRefunds = const [],
  Future<void> Function(TransactionEntity refund)? onDeleteRefund,
  Future<void> Function(
    TransactionEntity refund,
    DateTime settledAt,
    int settlementAccountId,
  )? onConfirmSettlement,
}) {
  return showBlurSheet<RefundSettlementResult>(
    context,
    child: RefundSettlementSheet(
      original: original,
      initialAmount: initialAmount,
      maxAmount: maxAmount,
      amountEditable: amountEditable,
      title: title,
      confirmLabel: confirmLabel,
      initialSettledAt: AppClock.now,
      existingRefunds: existingRefunds,
      onDeleteRefund: onDeleteRefund,
      onConfirmSettlement: onConfirmSettlement,
    ),
  );
}

class RefundSettlementSheet extends StatefulWidget {
  final TransactionEntity original;
  final Decimal initialAmount;
  final Decimal maxAmount;
  final bool amountEditable;
  final String title;
  final String confirmLabel;
  final DateTime? initialSettledAt;
  final int? initialSettlementAccountId;
  final List<TransactionEntity> existingRefunds;
  final Future<void> Function(TransactionEntity refund)? onDeleteRefund;
  final Future<void> Function(
    TransactionEntity refund,
    DateTime settledAt,
    int settlementAccountId,
  )? onConfirmSettlement;

  const RefundSettlementSheet({
    super.key,
    required this.original,
    required this.initialAmount,
    required this.maxAmount,
    this.amountEditable = true,
    this.title = '退款',
    this.confirmLabel = '确认退款',
    this.initialSettledAt,
    this.initialSettlementAccountId,
    this.existingRefunds = const [],
    this.onDeleteRefund,
    this.onConfirmSettlement,
  });

  @override
  State<RefundSettlementSheet> createState() => _RefundSettlementSheetState();
}

class _RefundSettlementSheetState extends State<RefundSettlementSheet> {
  late final TextEditingController _amountController;
  late Decimal _maxAmount;
  late List<TransactionEntity> _refunds;
  DateTime? _settledAt;
  int? _accountId;
  bool _amountEdited = false;
  bool _deletingRefund = false;

  @override
  void initState() {
    super.initState();
    final initialAmountText = _trimDecimal(widget.initialAmount);
    _amountController = TextEditingController(text: initialAmountText);
    if (widget.amountEditable) {
      _amountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialAmountText.length,
      );
    }
    _maxAmount = widget.maxAmount;
    _refunds = List.of(widget.existingRefunds);
    _settledAt = widget.initialSettledAt;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_accountId != null) return;
    final repo = context.read<AppRepository>();
    final accounts = _eligibleAccounts(repo);
    final preferred = widget.initialSettlementAccountId ??
        widget.original.settlementAccountId ??
        widget.original.accountId;
    _accountId = accounts.any((account) => account.id == preferred)
        ? preferred
        : accounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Decimal? get _amount => Decimal.tryParse(_amountController.text.trim());

  bool get _valid {
    final amount = _amount;
    return amount != null &&
        amount > Decimal.zero &&
        amount <= _maxAmount &&
        _settledAt != null &&
        _accountId != null;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final accounts = _eligibleAccounts(repo);
    final selectedAccount =
        accounts.where((account) => account.id == _accountId).firstOrNull;
    final amount = _amount;
    final amountError = amount == null || amount <= Decimal.zero
        ? '请输入大于 0 的金额'
        : amount > _maxAmount
            ? '最多可处理 ${MoneyFormat.string(_maxAmount, currencyCode: widget.original.currencyCode)}'
            : null;

    return ConstrainedBox(
      key: const Key('refund-settlement-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: widget.title,
            subtitle: '退款冲减原消费周期，到账日期和账户用于还原真实资金变化。',
            onClose: () => Navigator.pop(context),
            actionLabel: _maxAmount > Decimal.zero ? widget.confirmLabel : null,
            onAction: _valid ? _submit : null,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_refunds.isNotEmpty) ...[
                    Text('退款记录', style: AppType.sectionLabel(scheme)),
                    const SizedBox(height: 6),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        for (final refund in _refunds)
                          SettingsRow(
                            title: MoneyFormat.string(
                              refund.amount.abs(),
                              currencyCode: refund.currencyCode,
                            ),
                            subtitle: _refundSubtitle(repo, refund),
                            trailing: widget.onDeleteRefund == null &&
                                    widget.onConfirmSettlement == null
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.onConfirmSettlement != null)
                                        Tooltip(
                                          message: '确认到账信息',
                                          child: AppCircleButton(
                                            icon: Icons.edit_outlined,
                                            iconSize: 16,
                                            size: 30,
                                            onPressed: _deletingRefund
                                                ? null
                                                : () => _editSettlement(refund),
                                          ),
                                        ),
                                      if (widget.onDeleteRefund != null) ...[
                                        const SizedBox(width: 6),
                                        Tooltip(
                                          message: '撤销退款',
                                          child: AppCircleButton(
                                            icon: Icons.close,
                                            iconSize: 16,
                                            size: 30,
                                            onPressed: _deletingRefund
                                                ? null
                                                : () => _deleteRefund(refund),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  AppLabeledField(
                    label: widget.title == '报销到账' ? '报销金额' : '退款金额',
                    helperText: widget.amountEditable ? amountError : null,
                    child: widget.amountEditable
                        ? TextField(
                            key: const Key('refund-settlement-amount'),
                            controller: _amountController,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: moneyInputFormatters(),
                            style: AppType.body(scheme).copyWith(
                              fontFamily: 'Nunito',
                            ),
                            decoration: iosInputDecoration(
                              context,
                              prefix:
                                  '${MoneyFormat.symbol(widget.original.currencyCode)} ',
                              hint: '0.00',
                            ),
                            onChanged: (_) => setState(() {
                              _amountEdited = true;
                            }),
                          )
                        : AppReadOnlyField(
                            key: const Key('refund-settlement-amount'),
                            text: MoneyFormat.string(
                              widget.initialAmount,
                              currencyCode: widget.original.currencyCode,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '到账日期',
                    child: AppPickerField(
                      key: const Key('refund-settlement-date'),
                      text: _settledAt == null ? null : _dateLabel(_settledAt!),
                      hint: '选择到账日期',
                      trailingIcon: Icons.calendar_today_outlined,
                      onTap: (_) => _pickDate(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '到账账户',
                    helperText: accounts.isEmpty
                        ? '请先添加一个 ${widget.original.currencyCode} 账户'
                        : null,
                    child: AppPickerField(
                      key: const Key('refund-settlement-account'),
                      text: selectedAccount?.name,
                      hint: '选择到账账户',
                      trailingIcon: Icons.account_balance_wallet_outlined,
                      onTap: accounts.isEmpty
                          ? null
                          : (menuCtx) => showPickerMenu(
                                menuCtx,
                                [
                                  for (final account in accounts)
                                    IosMenuItem(
                                      label: account.name,
                                      icon:
                                          Icons.account_balance_wallet_outlined,
                                      selected: account.id == _accountId,
                                      onTap: () => setState(
                                        () => _accountId = account.id,
                                      ),
                                    ),
                                ],
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AccountEntity> _eligibleAccounts(AppRepository repo) => repo.accounts
      .where(
        (account) =>
            !account.isDeleted &&
            account.currencyCode == widget.original.currencyCode,
      )
      .toList();

  String _refundSubtitle(AppRepository repo, TransactionEntity refund) {
    final date = refund.settledAt;
    final account = repo.accounts
        .where((item) => item.id == refund.settlementAccountId)
        .firstOrNull;
    final dateText =
        date == null || refund.settlementQuality == SettlementQuality.unknown
            ? '到账日待确认'
            : _dateLabel(date);
    final accountText =
        refund.settlementAccountQuality == SettlementQuality.unknown ||
                refund.settlementAccountId == null
            ? '到账账户待确认'
            : account?.name ?? '原账户已删除';
    return '$dateText · $accountText';
  }

  Future<void> _editSettlement(TransactionEntity refund) async {
    final result = await showBlurSheet<RefundSettlementResult>(
      context,
      child: RefundSettlementSheet(
        original: refund,
        initialAmount: refund.amount.abs(),
        maxAmount: refund.amount.abs(),
        amountEditable: false,
        title: '确认到账信息',
        confirmLabel: '保存',
        initialSettledAt: refund.settlementQuality == SettlementQuality.unknown
            ? null
            : refund.settledAt,
        initialSettlementAccountId: refund.settlementAccountId,
      ),
    );
    if (result == null || widget.onConfirmSettlement == null) return;
    try {
      await widget.onConfirmSettlement!(
        refund,
        result.settledAt,
        result.settlementAccountId,
      );
    } on StateError catch (e) {
      // 「已被锚点余额核对吸收」这类保护性拦截：把话术说给用户，
      // 并保持退款记录原样，别让弹层看起来像保存成功。
      if (mounted) showAppToast(context, e.message, icon: Icons.error_outline);
      return;
    } catch (_) {
      if (mounted) {
        showAppToast(context, '到账信息保存失败，请重试', icon: Icons.error_outline);
      }
      return;
    }
    if (!mounted) return;
    final updated = context
        .read<AppRepository>()
        .refundsOf(widget.original.id)
        .where((item) => item.id == refund.id)
        .firstOrNull;
    if (updated == null) return;
    setState(() {
      final index = _refunds.indexWhere((item) => item.id == refund.id);
      if (index >= 0) _refunds[index] = updated;
    });
  }

  Future<void> _deleteRefund(TransactionEntity refund) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销这笔退款',
      message: '撤销后原订单的可退金额会恢复。',
      confirmText: '撤销',
    );
    if (!confirmed || widget.onDeleteRefund == null) return;
    setState(() => _deletingRefund = true);
    try {
      await widget.onDeleteRefund!(refund);
      if (!mounted) return;
      setState(() {
        _refunds.removeWhere((item) => item.id == refund.id);
        _maxAmount += refund.amount.abs();
        if (!_amountEdited) {
          _amountController.text = _trimDecimal(_maxAmount);
        }
      });
    } on StateError catch (e) {
      // 仓储层的保护性拦截（如「这笔退款已经用于确认物品退货…」）：
      // 说给用户听，且不把退款从列表里移掉，别让撤销看起来成功了。
      if (mounted) showAppToast(context, e.message, icon: Icons.error_outline);
    } catch (_) {
      if (mounted) {
        showAppToast(context, '撤销退款失败，请重试', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _deletingRefund = false);
    }
  }

  Future<void> _pickDate() async {
    final now = AppClock.now;
    final selected = await showAppDatePicker(
      context,
      initial: _settledAt ?? now,
      first: widget.original.date.isAfter(now) ? null : widget.original.date,
      last: now,
      title: '到账日期',
    );
    if (selected != null && mounted) setState(() => _settledAt = selected);
  }

  void _submit() {
    if (!_valid) return;
    Navigator.pop(
      context,
      RefundSettlementResult(
        amount: _amount!,
        settledAt: _settledAt!,
        settlementAccountId: _accountId!,
      ),
    );
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _trimDecimal(Decimal amount) {
  var text = amount.toString();
  if (text.endsWith('.00')) text = text.substring(0, text.length - 3);
  return text;
}
