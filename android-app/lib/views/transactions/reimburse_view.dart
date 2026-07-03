import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/mascot.dart';

/// 待报销：所有标了「待报销」的支出集中在这，报销到账后一键销掉。
/// 闭环 = 记账时标待报销 → 这里看合计催报销 → 到账标已报销（+提醒记收入）。
class ReimburseView extends StatelessWidget {
  const ReimburseView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final items = repo.reimbursableTransactions;
    final total =
        items.fold(Decimal.zero, (Decimal a, t) => a + t.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('待报销'), centerTitle: true),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(mood: MascotMood.success, size: 140),
                  const SizedBox(height: 12),
                  Text(
                    '没有待报销的账单，都结清啦',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                // 合计卡
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(scheme),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${items.length} 笔待报销',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(
                        MoneyFormat.string(total),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Nunito',
                          color: AppColors.income(scheme),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '报销到账后点「已报销」销掉；到账的钱记得记一笔收入喵',
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card(scheme),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 0.5,
                              indent: 14,
                              color: AppColors.hairline(scheme)),
                        _ReimburseRow(tx: items[i], repo: repo),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReimburseRow extends StatelessWidget {
  final TransactionEntity tx;
  final AppRepository repo;

  const _ReimburseRow({required this.tx, required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = tx.date;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          CatIcon(
            categoryKey: tx.categoryKey,
            emoji: CategorySeed.emojiOf(tx.categoryKey),
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.note.isNotEmpty ? tx.note : tx.categoryNameZh,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '${d.year}/${d.month}/${d.day} · ${tx.categoryNameZh}',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            MoneyFormat.string(tx.amount),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFamily: 'Nunito',
            ),
          ),
          const SizedBox(width: 10),
          // 已报销：白底描边小胶囊（轻操作，不喧哗）
          GestureDetector(
            onTap: () async {
              final ok = await showConfirmDialog(
                context,
                title: '这笔已经报销到账了？',
                message:
                    '「${tx.note.isNotEmpty ? tx.note : tx.categoryNameZh} ${MoneyFormat.string(tx.amount)}」将从待报销里销掉。',
                confirmText: '已报销',
              );
              if (ok && context.mounted) {
                Haptics.of(Haptic.success);
                await repo.markReimbursed(tx.id);
                if (context.mounted) {
                  showAppToast(context, '已销掉，记得记一笔到账收入喵');
                }
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.card(scheme),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: AppColors.hairline(scheme, strength: 1.3)),
              ),
              child: Text(
                '已报销',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
