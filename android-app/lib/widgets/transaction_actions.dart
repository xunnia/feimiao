import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../core/models/transaction_kind.dart';
import '../data/app_repository.dart';
import '../theme/app_colors.dart';
import '../views/transactions/edit_transaction_sheet.dart';
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
                child: _confirming
                    ? _confirmBar(paneCtx)
                    : _buttonsRow(paneCtx),
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
        await context
            .read<AppRepository>()
            .deleteTransaction(widget.transaction.id);
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

/// 退款弹层：显示原价/已退/净额 + 已退明细（图三的「退款记录」）；
/// 新退款默认填「剩余可退」，上限也是剩余，退不了超过原价。
Future<void> showRefundSheet(
    BuildContext context, TransactionEntity tx) async {
  final repo = context.read<AppRepository>();
  final full = tx.amount;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      final gold = AppColors.income(scheme);
      // 每次重建都读最新已退（多次退款后剩余会变）。
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final refunds = repo.refundsOf(tx.id);
          final refunded = repo.refundedAmountOf(tx.id);
          final remaining = full - refunded;
          final ctrl = _refundCtrl ??=
              TextEditingController(text: _trim(remaining));
          final parsed = Decimal.tryParse(ctrl.text.trim());
          final valid = parsed != null &&
              parsed > Decimal.zero &&
              parsed <= remaining;
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            scheme.onSurfaceVariant.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('退款',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(
                    '${tx.categoryNameZh.isNotEmpty ? tx.categoryNameZh : '这笔'}'
                    ' 原支出 ¥${_trim(full)}'
                    '${refunded > Decimal.zero ? ' · 已退 ¥${_trim(refunded)} · 剩 ¥${_trim(remaining)}' : ''}',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  // ── 已退明细（退款记录）──
                  if (refunds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('退款记录',
                          style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(height: 4),
                    for (final r in refunds)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')} ${r.date.hour.toString().padLeft(2, '0')}:${r.date.minute.toString().padLeft(2, '0')}',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                            Text('+${_trim(r.amount.abs())}',
                                style: TextStyle(
                                    color: gold,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Nunito')),
                            // 单笔退款可撤销（记错了）。
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.close,
                                  size: 16, color: scheme.onSurfaceVariant),
                              onPressed: () async {
                                await repo.deleteTransaction(r.id);
                                ctrl.text = _trim(full - repo.refundedAmountOf(tx.id));
                                setLocal(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 16),
                  ],
                  if (remaining > Decimal.zero) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      autofocus: refunds.isEmpty,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: '本次退款金额',
                        prefixText: '¥ ',
                        helperText: '默认剩余可退 ¥${_trim(remaining)}，可改小',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: valid
                            ? () async {
                                Navigator.pop(ctx);
                                Haptics.of(Haptic.success);
                                await repo.refundTransaction(tx, parsed);
                              }
                            : null,
                        child: Text(valid && parsed == remaining
                            ? '全部退回'
                            : '确认退款'),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('已全额退完',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  _refundCtrl?.dispose();
  _refundCtrl = null;
}

/// 退款弹层的输入控制器（弹层生命周期内复用，关闭时释放）。
TextEditingController? _refundCtrl;

String _trim(Decimal d) {
  var s = d.toString();
  if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
  return s;
}
