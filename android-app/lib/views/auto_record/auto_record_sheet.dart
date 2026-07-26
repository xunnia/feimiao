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
import '../../widgets/app_toast.dart';

/// 「喵盯到几笔消费」确认表：本地解析后的候选，勾选要记的，一键全部记下。
/// 不静默直接入账，避免抓错/重复（退款、余额变动等）直接污染账本。
Future<List<String>?> showAutoRecordSheet(
    BuildContext context, List<AutoCandidate> items) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    // 候选多时弹层会撑很高，顶部让出状态栏。
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AutoRecordSheet(items: items),
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
    Navigator.of(context).pop([
      for (final item in widget.items) item.sourceId,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.appBg(scheme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('喵盯到 ${widget.items.length} 笔可能的消费',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('勾掉不想记的，其余一键记下',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _row(scheme, i),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop([
                            for (final item in widget.items) item.sourceId,
                          ]),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.56),
                      width: 0.7,
                    ),
                    minimumSize: const Size.fromHeight(40),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  child: const Text('忽略'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed:
                      (_saving || _selectedCount == 0) ? null : _saveSelected,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                    minimumSize: const Size.fromHeight(40),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Text(_saving ? '记账中…' : '记下这 $_selectedCount 笔'),
                ),
              ),
            ],
          ),
        ],
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
    return InkWell(
      onTap:
          c.isRefund ? null : () => setState(() => _checked[i] = !_checked[i]),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _checked[i],
              onChanged: c.isRefund
                  ? null
                  : (v) => setState(() => _checked[i] = v ?? false),
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
