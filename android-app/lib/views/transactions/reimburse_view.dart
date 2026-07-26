import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../widgets/app_buttons.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_card_display.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/mascot.dart';
import '../../widgets/refund_settlement_sheet.dart';

/// 待报销：所有标了「待报销」的支出集中在这，报销到账后一键销掉。
/// 闭环 = 记账时标待报销 → 这里看合计催报销 → 确认真实到账日和账户。
class ReimburseView extends StatelessWidget {
  const ReimburseView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final items = repo.reimbursableTransactions;
    final total = items.fold(
      Decimal.zero,
      (Decimal sum, item) => sum + repo.netAmountOf(item),
    );

    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('待报销'),
          centerTitle: true),
      body: items.isEmpty
          ? const AppEmptyState(
              mood: MascotMood.success,
              title: '没有待报销的账单',
              message: '都结清啦',
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
                  '报销到账后确认日期和收款账户，原支出会按实际报销额抵消。',
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
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
    final familyNet = repo.netAmountOf(tx);
    final displayMode =
        context.select<AppRepository, TransactionCardDisplayMode>(
            (value) => value.transactionCardDisplayMode);
    final cardText = resolveTransactionCardText(
      mode: displayMode,
      kind: tx.txKind,
      note: tx.note,
      categoryName: tx.categoryNameZh,
      accountName: tx.accountName,
      toAccountName: tx.toAccountName,
    );
    // 待报销行可能来自任意账本：按 tx.bookId 反查账本名，找不到再兜底当前账本。
    final bookName = repo.books
            .where((book) => book.id == tx.bookId)
            .firstOrNull
            ?.name ??
        repo.currentBook?.name;
    final detailText = joinTransactionCardDetails([
      transactionCardTimeLabel(
        tx.date,
        dateGrouped: false,
        precision: tx.timePrecision,
      ),
      bookName,
      cardText.secondary,
    ]);

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
                  cardText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  detailText,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            MoneyFormat.string(
              familyNet,
              currencyCode: tx.currencyCode,
            ),
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
              if (familyNet <= Decimal.zero) {
                showAppToast(context, '这笔账已没有待报销金额');
                return;
              }
              final result = await showRefundSettlementSheet(
                context,
                original: tx,
                initialAmount: familyNet,
                maxAmount: familyNet,
                amountEditable: false,
                title: '报销到账',
                confirmLabel: '确认到账',
              );
              if (result == null || !context.mounted) return;
              try {
                await repo.markReimbursed(
                  tx.id,
                  settledAt: result.settledAt,
                  settlementAccountId: result.settlementAccountId,
                );
              } on StateError catch (e) {
                // 仓储层的保护性拦截（如流水已关联资产等）要说给用户听，
                // 不能静默吞掉让「已报销」看起来没反应。
                if (context.mounted) {
                  showAppToast(context, e.message, icon: Icons.error_outline);
                }
                return;
              } catch (_) {
                if (context.mounted) {
                  showAppToast(context, '报销确认失败，请重试',
                      icon: Icons.error_outline);
                }
                return;
              }
              // 成功之后才给成功触感/提示，失败别装成功。
              Haptics.of(Haptic.success);
              if (context.mounted) {
                showAppToast(context, '已确认报销到账，原支出已抵消');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
