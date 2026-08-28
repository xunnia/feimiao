import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/smart_tags.dart';
import '../../core/auto_record.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/transaction_time.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../common/app_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';

/// 「喵盯到几笔消费」确认表：本地解析后的候选，勾选要记的，一键全部记下。
/// 不静默直接入账，避免抓错/重复（退款、余额变动等）直接污染账本。
Future<List<String>?> showAutoRecordSheet(
    BuildContext context, List<AutoCandidate> items) {
  return showBlurSheet<List<String>>(
    context,
    radius: 28,
    child: _AutoRecordSheet(items: items),
  );
}

class _AutoRecordSheet extends StatefulWidget {
  final List<AutoCandidate> items;
  const _AutoRecordSheet({required this.items});

  @override
  State<_AutoRecordSheet> createState() => _AutoRecordSheetState();
}

class _AutoRecordSheetState extends State<_AutoRecordSheet> {
  late final List<bool> _checked = [
    for (final item in widget.items) !item.isRefund,
  ];
  bool _saving = false;

  int get _selectedCount => _checked.where((c) => c).length;

  List<String> get _sourceIds => [
        for (final item in widget.items) item.sourceId,
      ];

  void _dismiss() => Navigator.of(context).pop(_sourceIds);

  Future<void> _saveSelected() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<AppRepository>();
    final accountId = repo.transactionAccounts.firstOrNull?.id;
    if (accountId == null) {
      showAppToast(context, '请先在「资产管理」里加一个账户', icon: Icons.info_outline);
      setState(() => _saving = false);
      return;
    }
    var n = 0;
    try {
      for (var i = 0; i < widget.items.length; i++) {
        if (!_checked[i]) continue;
        final c = widget.items[i];
        if (c.isRefund) continue;
        final wantKey = c.categoryKey ??
            (c.kind == TransactionKind.income
                ? 'otherIncome'
                : CategorySeed.fallbackExpenseKey);
        int? catId;
        for (final x in repo.categories) {
          if (x.kind == c.kind && x.key == wantKey) {
            catId = x.id;
            break;
          }
        }
        await repo.addTransaction(
          kind: c.kind,
          amount: c.amount,
          categoryId: catId,
          accountId: accountId,
          note: c.text.length > 40 ? c.text.substring(0, 40) : c.text,
          date: c.time,
          timePrecision: TransactionTimePrecision.exact,
          reimbursable: SmartTags.isReimbursable(c.text),
          autoRecordSourceId: c.sourceId,
        );
        n++;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, '保存没有完成，请稍后重试', icon: Icons.info_outline);
      return;
    }
    if (!mounted) return;
    showAppToast(
      context,
      n == 0 ? '没有新增普通账单' : '喵帮你记下了 $n 笔～',
    );
    // 退款项只是提示、不会入账，这一批处理完也一起出队；
    // 否则它们永远不被 ack，每次回前台都重复弹同一批退款通知。
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: '喵盯到 ${widget.items.length} 笔可能的消费',
                subtitle: '勾掉不想记的，其余一键记下',
                onClose: _saving ? null : _dismiss,
                actionLabel: _saving ? '记账中…' : '记下 $_selectedCount 笔',
                onAction:
                    _saving || _selectedCount == 0 ? null : _saveSelected,
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _row(scheme, i),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppPillButton(
                    label: '忽略',
                    onPressed: _saving ? null : _dismiss,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ColorScheme scheme, int i) {
    final c = widget.items[i];
    final isIncome = c.kind == TransactionKind.income;
    final key = c.categoryKey;
    final catName = (key != null ? CategorySeed.byKey(key)?.nameZh : null) ??
        (isIncome ? '其他收入' : '其他');
    final emoji = CategorySeed.emojiOf(c.categoryKey); // emojiOf 接受可空
    return PressableScale(
      onPressed:
          c.isRefund ? null : () => setState(() => _checked[i] = !_checked[i]),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AppCheckmark(
              semanticLabel: c.isRefund ? null : '选择这笔账单',
              interactive: false,
              value: _checked[i],
              onChanged: null,
            ),
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.isRefund ? '退款到账 · ${c.app}' : '$catName · ${c.app}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    c.isRefund ? '需匹配原订单，请到喵助手登记' : c.text,
                    maxLines: c.isRefund ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (c.isRefund) ...[
                    const SizedBox(height: 2),
                    Text(
                      '退款通知仅提示，不会入账',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isIncome ? '+' : '-'}${MoneyFormat.string(c.amount)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Nunito',
                color: isIncome ? scheme.secondary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
