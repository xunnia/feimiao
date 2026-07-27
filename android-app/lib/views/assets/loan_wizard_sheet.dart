// 房贷/大额分期向导（A 批 A3）：一页设好「loan 账户 + 负债档案 + 每月自动还款」。
//
// 数据语义（跟 repo.createLoanWizardSetup 契约一致，别在 UI 里另编一套）：
// - 三件套在一次事务里建齐：贷款账户（余额 = -剩余本金，计入净资产）、
//   负债档案（利率只存档展示）、每月还款日自动转账（扣款账户 → 贷款账户）。
// - 不做本息拆分（那是独立批的范围）——向导文案不许承诺利息拆分。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'account_detail_page.dart';
import 'asset_form_kit.dart';

/// 打开向导弹层；创建成功后直接跳到新账户的详情页。
///
/// 用 [navigator]（而不是调用方自己的 context）做后续跳转，调用方可以在
/// 弹层打开前就 pop 掉自己（如「添加」弹层/账户表单里的入口）。
Future<void> showLoanWizardSheet(BuildContext context) async {
  final repo = context.read<AppRepository>();
  final navigator = Navigator.of(context);
  final accountId = await showBlurSheet<int>(
    context,
    child: const LoanWizardSheet(),
  );
  if (accountId == null) return;
  final account =
      repo.accounts.where((a) => a.id == accountId && !a.isDeleted).firstOrNull;
  if (account == null) return;
  navigator.push(
    AppPageRoute<void>(
      builder: (_) => AccountDetailPage(account: account),
    ),
  );
}

class LoanWizardSheet extends StatefulWidget {
  const LoanWizardSheet({super.key});

  @override
  State<LoanWizardSheet> createState() => _LoanWizardSheetState();
}

class _LoanWizardSheetState extends State<LoanWizardSheet> {
  static const _types = [
    LiabilityProfileType.mortgage,
    LiabilityProfileType.carLoan,
    LiabilityProfileType.consumerLoan,
  ];

  LiabilityProfileType _type = LiabilityProfileType.mortgage;
  late final TextEditingController _nameCtrl;
  final _totalCtrl = TextEditingController();
  final _principalCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  int? _repaymentDay;
  int? _fromAccountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _type.label);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _totalCtrl.dispose();
    _principalCtrl.dispose();
    _rateCtrl.dispose();
    _monthlyCtrl.dispose();
    super.dispose();
  }

  Decimal? _positiveOf(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    final value = Decimal.tryParse(normalized);
    if (value == null || value <= Decimal.zero) return null;
    return value;
  }

  Decimal? get _total => _positiveOf(_totalCtrl.text);

  /// 剩余本金：留空 = 与总额相同（向导文案如实写出这条默认）。
  Decimal? get _principal =>
      _principalCtrl.text.trim().isEmpty ? _total : _positiveOf(_principalCtrl.text);

  Decimal? get _monthly => _positiveOf(_monthlyCtrl.text);

  /// 年利率可选：空 = 不填；填了必须是非负数字。
  bool get _rateValid {
    final normalized = _rateCtrl.text.trim().replaceAll(',', '');
    if (normalized.isEmpty) return true;
    final value = Decimal.tryParse(normalized);
    return value != null && value >= Decimal.zero;
  }

  Decimal? get _rate {
    final normalized = _rateCtrl.text.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    return Decimal.tryParse(normalized);
  }

  bool get _valid =>
      !_saving &&
      _nameCtrl.text.trim().isNotEmpty &&
      _total != null &&
      _principal != null &&
      _rateValid &&
      _monthly != null &&
      _repaymentDay != null &&
      _fromAccountId != null;

  /// 首次自动记账日期预览（与 repo 的取值规则一致：今天起最近的还款日，
  /// 含今天，短月夹到月末）。
  DateTime? get _firstDuePreview {
    final day = _repaymentDay;
    if (day == null) return null;
    final now = DateTime.now();
    DateTime clampToMonth(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day < lastDay ? day : lastDay);
    }

    final today = DateTime(now.year, now.month, now.day);
    final thisMonth = clampToMonth(now.year, now.month);
    if (!thisMonth.isBefore(today)) return thisMonth;
    final nextYear = now.month == 12 ? now.year + 1 : now.year;
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    return clampToMonth(nextYear, nextMonth);
  }

  void _onTypeChanged(LiabilityProfileType next) {
    setState(() {
      // 名称还是上一个类型的默认名（用户没改过）时，跟着换默认名。
      if (_nameCtrl.text.trim() == _type.label ||
          _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = next.label;
      }
      _type = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final accounts = repo.transactionAccounts;
    final firstDue = _firstDuePreview;
    final screenH = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '房贷/分期向导',
            subtitle: '一次设好账户、档案和每月自动还款',
            onClose: () => Navigator.pop(context),
            actionLabel: '创建',
            actionKey: const Key('loan-wizard-create'),
            onAction: _valid ? _save : null,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLabeledField(
                    label: '贷款类型',
                    child: AssetEnumDropdown<LiabilityProfileType>(
                      value: _type,
                      values: _types,
                      labelOf: (value) => value.label,
                      hint: '选择类型',
                      onChanged: _onTypeChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '名称',
                    child: TextField(
                      key: const Key('loan-wizard-name'),
                      controller: _nameCtrl,
                      decoration:
                          iosInputDecoration(context, hint: '例如 房贷'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '贷款总额',
                    child: TextField(
                      key: const Key('loan-wizard-total'),
                      controller: _totalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(
                        context,
                        prefix: '¥ ',
                        hint: '例如 1000000',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '剩余本金',
                    child: TextField(
                      key: const Key('loan-wizard-principal'),
                      controller: _principalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(
                        context,
                        prefix: '¥ ',
                        hint: '不填 = 与总额相同',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '年利率 %（可选，仅展示）',
                    child: TextField(
                      controller: _rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: iosInputDecoration(context, hint: '例如 3.1'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '每月还款额',
                    child: TextField(
                      key: const Key('loan-wizard-monthly'),
                      controller: _monthlyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(
                        context,
                        prefix: '¥ ',
                        hint: '例如 5000',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '每月还款日',
                    child: AppPickerField(
                      key: const Key('loan-wizard-repayment-day'),
                      text: _repaymentDay == null ? null : '每月 $_repaymentDay 日',
                      hint: '选择每月还款日',
                      onTap: (menuCtx) => showPickerMenu(menuCtx, [
                        for (var day = 1; day <= 31; day++)
                          IosMenuItem(
                            label: '$day 日',
                            icon: Icons.today_outlined,
                            selected: day == _repaymentDay,
                            onTap: () =>
                                setState(() => _repaymentDay = day),
                          ),
                      ]),
                    ),
                  ),
                  if (firstDue != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '首次自动记账：${assetDateText(firstDue)}',
                      style: AppType.caption(scheme),
                    ),
                  ],
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '扣款账户',
                    child: AssetAccountDropdown(
                      value: _fromAccountId,
                      accounts: accounts,
                      hint: '每月从哪个账户扣月供',
                      onChanged: (value) =>
                          setState(() => _fromAccountId = value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AssetHintBox(
                    text: '创建后：新建贷款账户（余额 = -剩余本金，计入净资产）'
                        '和负债档案；每月还款日自动从扣款账户转一笔月供到贷款'
                        '账户。年利率仅作展示，不做本息拆分；提前还款走'
                        '「最近要还」里的还款。',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    try {
      final result = await context.read<AppRepository>().createLoanWizardSetup(
            type: _type,
            name: _nameCtrl.text,
            totalAmount: _total!,
            remainingPrincipal: _principal!,
            annualRate: _rate,
            monthlyPayment: _monthly!,
            repaymentDay: _repaymentDay!,
            fromAccountId: _fromAccountId!,
          );
      if (!mounted) return;
      // showAppToast 走 rootOverlay，pop 前调用能存活到弹层关闭后。
      showAppToast(
        context,
        '已建好，每月 $_repaymentDay 日自动记还款',
        mascot: MascotMood.success,
      );
      Navigator.pop(context, result.accountId);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      showAppToast(context, '${error.message}', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
