import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

class PhysicalAssetRefundAllocationTargetData {
  final int assetId;
  final String assetName;
  final int grossCents;
  final int totalAllocatedRefundCents;
  final int currentRefundAllocationCents;

  const PhysicalAssetRefundAllocationTargetData({
    required this.assetId,
    required this.assetName,
    required this.grossCents,
    required this.totalAllocatedRefundCents,
    this.currentRefundAllocationCents = 0,
  });

  int get allocationLimitCents =>
      grossCents - totalAllocatedRefundCents + currentRefundAllocationCents;
}

class PhysicalAssetRefundAllocationData {
  final int refundTransactionId;
  final int refundCents;
  final DateTime occurredAt;
  final String orderLabel;
  final List<PhysicalAssetRefundAllocationTargetData> targets;

  /// 本次退款最多能归到「订单未跟踪部分」的金额；0 = 不显示该选项。
  final int untrackedLimitCents;

  /// 本次退款当前已归到未跟踪部分的金额（重新分配时回显）。
  final int currentUntrackedCents;

  const PhysicalAssetRefundAllocationData({
    required this.refundTransactionId,
    required this.refundCents,
    required this.occurredAt,
    required this.orderLabel,
    required this.targets,
    this.untrackedLimitCents = 0,
    this.currentUntrackedCents = 0,
  });
}

typedef PhysicalAssetRefundAllocationLoader
    = Future<List<PhysicalAssetRefundAllocationData>> Function();
typedef PhysicalAssetRefundAllocationSubmitter = Future<void> Function(
  int refundTransactionId,
  Map<int, int> allocationsByAssetId,
  int untrackedCents,
);

Future<void> showPhysicalAssetRefundAllocationSheet(
  BuildContext context, {
  required PhysicalAssetRefundAllocationLoader load,
  required PhysicalAssetRefundAllocationSubmitter submit,
}) {
  return showBlurSheet<void>(
    context,
    child: PhysicalAssetRefundAllocationSheet(
      load: load,
      submit: submit,
    ),
  );
}

class PhysicalAssetRefundAllocationSheet extends StatefulWidget {
  final PhysicalAssetRefundAllocationLoader load;
  final PhysicalAssetRefundAllocationSubmitter submit;

  const PhysicalAssetRefundAllocationSheet({
    super.key,
    required this.load,
    required this.submit,
  });

  @override
  State<PhysicalAssetRefundAllocationSheet> createState() =>
      _PhysicalAssetRefundAllocationSheetState();
}

class _PhysicalAssetRefundAllocationSheetState
    extends State<PhysicalAssetRefundAllocationSheet> {
  late Future<List<PhysicalAssetRefundAllocationData>> _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.load();
  }

  void _reload() {
    setState(() => _pending = widget.load());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '分配退款',
              subtitle: '把每笔退款分到对应物品，购置成本才会准确更新。',
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: FutureBuilder<List<PhysicalAssetRefundAllocationData>>(
                future: _pending,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _RefundAllocationMessage(
                      icon: Icons.sync_problem_outlined,
                      title: '暂时无法读取退款',
                      message: '关闭后重试，原账单与物品金额不会改变。',
                      actionLabel: '重试',
                      onAction: _reload,
                    );
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const _RefundAllocationMessage(
                      mood: MascotMood.success,
                      title: '退款都已分配',
                      message: '关联物品的净购置成本已经更新。',
                    );
                  }
                  return ListView.separated(
                    key: const Key('asset-refund-allocation-list'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _RefundAllocationCard(
                      key: ValueKey(
                        'asset-refund-${items[index].refundTransactionId}',
                      ),
                      data: items[index],
                      submit: widget.submit,
                      onCompleted: _reload,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundAllocationCard extends StatefulWidget {
  final PhysicalAssetRefundAllocationData data;
  final PhysicalAssetRefundAllocationSubmitter submit;
  final VoidCallback onCompleted;

  const _RefundAllocationCard({
    super.key,
    required this.data,
    required this.submit,
    required this.onCompleted,
  });

  @override
  State<_RefundAllocationCard> createState() => _RefundAllocationCardState();
}

class _RefundAllocationCardState extends State<_RefundAllocationCard> {
  late final Map<int, TextEditingController> _controllers;
  late final TextEditingController _untrackedController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final target in widget.data.targets)
        target.assetId: TextEditingController(
          text: target.currentRefundAllocationCents == 0
              ? ''
              : _plainAmount(target.currentRefundAllocationCents),
        ),
    };
    _untrackedController = TextEditingController(
      text: widget.data.currentUntrackedCents == 0
          ? ''
          : _plainAmount(widget.data.currentUntrackedCents),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _untrackedController.dispose();
    super.dispose();
  }

  Map<int, int>? get _allocations {
    final values = <int, int>{};
    for (final target in widget.data.targets) {
      final raw = _controllers[target.assetId]?.text.trim() ?? '';
      if (raw.isEmpty) {
        values[target.assetId] = 0;
        continue;
      }
      final amount = Decimal.tryParse(raw.replaceAll(',', ''));
      if (amount == null || amount < Decimal.zero) return null;
      final cents = decimalToBudgetCents(amount);
      if (cents > target.allocationLimitCents) return null;
      values[target.assetId] = cents;
    }
    return values;
  }

  /// 归到「订单未跟踪部分」的金额；非法或超上限返回 null。
  int? get _untrackedCents {
    if (widget.data.untrackedLimitCents <= 0) return 0;
    final raw = _untrackedController.text.trim();
    if (raw.isEmpty) return 0;
    final amount = Decimal.tryParse(raw.replaceAll(',', ''));
    if (amount == null || amount < Decimal.zero) return null;
    final cents = decimalToBudgetCents(amount);
    if (cents > widget.data.untrackedLimitCents) return null;
    return cents;
  }

  int? get _totalCents {
    final allocations = _allocations;
    final untracked = _untrackedCents;
    if (allocations == null || untracked == null) return null;
    return allocations.values.fold<int>(untracked, (sum, cents) => sum + cents);
  }

  bool get _canSubmit =>
      !_saving && _totalCents != null && _totalCents == widget.data.refundCents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _totalCents;
    final remaining = total == null ? null : widget.data.refundCents - total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.data.orderLabel.trim().isEmpty
                          ? '关联订单退款'
                          : widget.data.orderLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle(scheme),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _dateText(widget.data.occurredAt),
                      style: AppType.secondary(scheme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _money(widget.data.refundCents),
                style: AppType.rowTitle(scheme).copyWith(
                  fontFamily: 'Nunito',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < widget.data.targets.length; i++) ...[
            if (i > 0) const SizedBox(height: 13),
            _buildTargetField(context, widget.data.targets[i]),
          ],
          if (widget.data.untrackedLimitCents > 0) ...[
            const SizedBox(height: 13),
            _buildUntrackedField(context),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.iconCircleFill(scheme),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _summaryText(total, remaining),
                    key: Key(
                      'asset-refund-summary-${widget.data.refundTransactionId}',
                    ),
                    style: AppType.secondary(scheme),
                  ),
                ),
                const SizedBox(width: 8),
                AppPillButton(
                  key: Key(
                    'asset-refund-submit-${widget.data.refundTransactionId}',
                  ),
                  label: _saving ? '提交中' : '确认分配',
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetField(
    BuildContext context,
    PhysicalAssetRefundAllocationTargetData target,
  ) {
    return AppLabeledField(
      label: target.assetName,
      helperText:
          '本次最多 ${_money(target.allocationLimitCents)} · 累计已退 ${_money(target.totalAllocatedRefundCents)}',
      child: TextField(
        key: Key(
          'asset-refund-input-${widget.data.refundTransactionId}-${target.assetId}',
        ),
        controller: _controllers[target.assetId],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: moneyInputFormatters(),
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: iosInputDecoration(context, hint: '0.00', prefix: '¥ '),
      ),
    );
  }

  Widget _buildUntrackedField(BuildContext context) {
    return AppLabeledField(
      label: '不属于已跟踪物品',
      helperText:
          '订单里没入库的部分（本次最多 ${_money(widget.data.untrackedLimitCents)}），不影响任何物品的购置成本',
      child: TextField(
        key: Key(
          'asset-refund-untracked-${widget.data.refundTransactionId}',
        ),
        controller: _untrackedController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: moneyInputFormatters(),
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: iosInputDecoration(context, hint: '0.00', prefix: '¥ '),
      ),
    );
  }

  String _summaryText(int? total, int? remaining) {
    if (total == null) return '请检查金额，每件不能超过可分配上限';
    if (remaining == 0) return '合计 ${_money(total)}，可以确认';
    if (remaining! > 0) return '还需分配 ${_money(remaining)}';
    return '已超出 ${_money(-remaining)}';
  }

  Future<void> _submit() async {
    final allocations = _allocations;
    final untracked = _untrackedCents;
    if (allocations == null || untracked == null || !_canSubmit) return;
    setState(() => _saving = true);
    try {
      await widget.submit(
        widget.data.refundTransactionId,
        allocations,
        untracked,
      );
      if (!mounted) return;
      showAppToast(context, '退款已分配，物品购置成本已更新');
      widget.onCompleted();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, '分配没有保存，请检查金额后重试');
    }
  }
}

class _RefundAllocationMessage extends StatelessWidget {
  final IconData? icon;
  final MascotMood? mood;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _RefundAllocationMessage({
    this.icon,
    this.mood,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert(icon != null || mood != null, '空态/异常态必须给图标或猫其一');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 空态/完成态用猫（守「空状态只放猫」标准）；
            // 加载失败等异常态仍用图标，别拿猫报错误。
            if (mood != null)
              Mascot(mood: mood!, size: 72, animate: true)
            else
              Icon(icon, size: 38, color: AppTextColor.secondary(scheme)),
            const SizedBox(height: 12),
            Text(title, style: AppType.rowTitle(scheme)),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.secondary(scheme),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              AppPillButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

String _money(int cents) => MoneyFormat.string(
      budgetDecimalFromCents(cents) ?? Decimal.zero,
    );

String _plainAmount(int cents) {
  final amount = budgetDecimalFromCents(cents) ?? Decimal.zero;
  return amount.toString();
}

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
