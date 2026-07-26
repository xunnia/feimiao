import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../core/models/transaction_kind.dart';
import '../data/app_repository.dart';
import '../views/transactions/edit_transaction_sheet.dart';
import 'app_toast.dart';
import 'refund_settlement_sheet.dart';
import 'slidable_tracker.dart';

const Color _kEdit = Color(0xFF7D8B9B); // 蓝灰毛
const Color _kRefund = Color(0xFFF2B23C); // 铜金眼
const Color _kDelete = Color(0xFFE0552B); // 警示红

/// 单笔账目的左滑操作：编辑 / 退款 / 删除(纯文字,无图标)。
/// 点「删除」后,这排按钮**原地**变成一条长红「删除这笔」确认条;
/// 划走(不确认)即取消。退款走冲账(方案1)。
class TransactionSlidable extends StatefulWidget {
  final TransactionEntity transaction;
  final Widget child;

  const TransactionSlidable({
    super.key,
    required this.transaction,
    required this.child,
  });

  @override
  State<TransactionSlidable> createState() => _TransactionSlidableState();
}

class _TransactionSlidableState extends State<TransactionSlidable> {
  bool _confirming = false;

  @override
  void didUpdateWidget(TransactionSlidable old) {
    super.didUpdateWidget(old);
    // 列表因退款/改动重建时，清掉可能残留的「删除这笔」确认态——
    // 否则下次左滑这一行会直接冒出红色删除确认条（用户 0703 反馈）。
    if (_confirming) _confirming = false;
  }

  // 仅对「正向支出」给退款入口(收入/转账/退款冲账本身都不给)。
  bool get _canRefund =>
      widget.transaction.txKind == TransactionKind.expense &&
      widget.transaction.amount > Decimal.zero;

  @override
  Widget build(BuildContext context) {
    // 确认态和普通态保持同一宽度,避免切换时跳动。
    // 操作区整体改短;按钮↔确认条之间淡入淡出,不再瞬间跳。
    final extent = _canRefund ? 0.58 : 0.4;
    return Slidable(
      key: ValueKey('tx_${widget.transaction.id}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: extent,
        children: [
          CustomSlidableAction(
            autoClose: false,
            onPressed: (_) {}, // 按钮各自处理点击(内层 GestureDetector)
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            child: Builder(
              builder: (paneCtx) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child:
                    _confirming ? _confirmBar(paneCtx) : _buttonsRow(paneCtx),
              ),
            ),
          ),
        ],
      ),
      // 观察面板开合，登记到全局 SlidableTracker（右滑开抽屉手势据此让位）。
      child: _PaneWatcher(
        trackKey: 'tx_${widget.transaction.id}',
        child: widget.child,
      ),
    );
  }

  Widget _buttonsRow(BuildContext paneCtx) {
    return Row(
      key: const ValueKey('btns'),
      children: [
        _seg('编辑', _kEdit, () {
          Slidable.of(paneCtx)?.close();
          showEditTransactionSheet(paneCtx, widget.transaction);
        }),
        if (_canRefund)
          _seg('退款', _kRefund, () {
            Slidable.of(paneCtx)?.close();
            showRefundSheet(paneCtx, widget.transaction);
          }),
        _seg('删除', _kDelete, () => _startConfirm(paneCtx)),
      ],
    );
  }

  Widget _confirmBar(BuildContext paneCtx) {
    return GestureDetector(
      key: const ValueKey('confirm'),
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        Haptics.of(Haptic.warning);
        try {
          await context
              .read<AppRepository>()
              .deleteTransaction(widget.transaction.id);
        } on StateError catch (e) {
          // 仓储层的保护性拦截（如「这笔退款已经用于确认物品退货…」）
          // 要说给用户听，不能静默吞掉让删除看起来没反应。
          if (!mounted) return;
          showAppToast(context, e.message, icon: Icons.error_outline);
        } catch (_) {
          if (!mounted) return;
          showAppToast(context, '删除失败，请重试', icon: Icons.error_outline);
        }
      },
      child: Container(
        color: _kDelete,
        alignment: Alignment.center,
        child: const Text('删除这笔',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _seg(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: color,
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }

  // 进入"红色确认条"态;面板划回收起时自动取消确认。
  void _startConfirm(BuildContext paneCtx) {
    Haptics.selection();
    final ctrl = Slidable.of(paneCtx);
    setState(() => _confirming = true);
    if (ctrl != null) {
      void listener() {
        if (ctrl.actionPaneType.value == ActionPaneType.none) {
          ctrl.actionPaneType.removeListener(listener);
          if (mounted) setState(() => _confirming = false);
        }
      }

      ctrl.actionPaneType.addListener(listener);
    }
  }
}

/// 挂在 Slidable 内部，把操作面板的开合状态登记到 [SlidableTracker]。
class _PaneWatcher extends StatefulWidget {
  final Object trackKey;
  final Widget child;

  const _PaneWatcher({required this.trackKey, required this.child});

  @override
  State<_PaneWatcher> createState() => _PaneWatcherState();
}

class _PaneWatcherState extends State<_PaneWatcher> {
  SlidableController? _ctl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctl = Slidable.of(context);
    if (!identical(ctl, _ctl)) {
      _ctl?.actionPaneType.removeListener(_onPaneChanged);
      _ctl = ctl;
      _ctl?.actionPaneType.addListener(_onPaneChanged);
    }
  }

  void _onPaneChanged() {
    final ctl = _ctl;
    if (ctl == null) return;
    SlidableTracker.setOpen(
        widget.trackKey, ctl.actionPaneType.value != ActionPaneType.none);
  }

  @override
  void dispose() {
    _ctl?.actionPaneType.removeListener(_onPaneChanged);
    SlidableTracker.setOpen(widget.trackKey, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 手工退款与 AI 退款共用同一套结算确认，避免消费归属和真实到账混用。
Future<void> showRefundSheet(BuildContext context, TransactionEntity tx) async {
  final repo = context.read<AppRepository>();
  final refunds = repo.refundsOf(tx.id);
  final remaining = tx.amount - repo.refundedAmountOf(tx.id);
  final result = await showRefundSettlementSheet(
    context,
    original: tx,
    initialAmount: remaining,
    maxAmount: remaining,
    existingRefunds: refunds,
    onDeleteRefund: (refund) => repo.deleteTransaction(refund.id),
    onConfirmSettlement: (refund, settledAt, settlementAccountId) =>
        repo.confirmTransactionSettlement(
      refund.id,
      settledAt: settledAt,
      settlementAccountId: settlementAccountId,
    ),
  );
  if (result == null) return;
  Haptics.of(Haptic.success);
  await repo.refundTransaction(
    tx,
    result.amount,
    settledAt: result.settledAt,
    settlementAccountId: result.settlementAccountId,
  );
}
