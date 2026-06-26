import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/mascot.dart';
import '../../widgets/tag_selector.dart';
import '../../widgets/transaction_actions.dart';
import 'edit_transaction_sheet.dart';

/// 流水明细页：按天分组 + 当日小计 + 左滑删除 + 「只看待报销」筛选 + 空状态。
class TransactionListView extends StatefulWidget {
  const TransactionListView({super.key});

  @override
  State<TransactionListView> createState() => _TransactionListViewState();
}

class _TransactionListViewState extends State<TransactionListView> {
  bool _onlyReimbursable = false;

  List<_DaySection> _groupByDay(List<TransactionEntity> transactions) {
    final map = <DateTime, List<TransactionEntity>>{};
    for (final t in transactions) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map.entries
        .map((e) => _DaySection(day: e.key, items: e.value))
        .toList()
      ..sort((a, b) => b.day.compareTo(a.day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('明细'),
        centerTitle: true,
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final all = repo.transactions;
          final pending =
              all.where((t) => t.reimbursable).toList(growable: false);
          final shown = _onlyReimbursable ? pending : all;

          return Column(
            children: [
              if (pending.isNotEmpty)
                _FilterBar(
                  onlyReimbursable: _onlyReimbursable,
                  pendingCount: pending.length,
                  pendingTotal: pending.fold(
                      Decimal.zero, (sum, t) => sum + t.amount),
                  onToggle: (v) => setState(() => _onlyReimbursable = v),
                ),
              Expanded(
                child: shown.isEmpty
                    ? _EmptyState(onlyReimbursable: _onlyReimbursable)
                    : _TransactionSectionList(
                        sections: _groupByDay(shown), repo: repo),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DaySection {
  final DateTime day;
  final List<TransactionEntity> items;
  const _DaySection({required this.day, required this.items});
}

class _FilterBar extends StatelessWidget {
  final bool onlyReimbursable;
  final int pendingCount;
  final Decimal pendingTotal;
  final ValueChanged<bool> onToggle;

  const _FilterBar({
    required this.onlyReimbursable,
    required this.pendingCount,
    required this.pendingTotal,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 6),
      child: Row(
        children: [
          FilterChip(
            label: const Text('只看待报销'),
            avatar: const Icon(Icons.receipt_long_outlined, size: 16),
            selected: onlyReimbursable,
            onSelected: onToggle,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const Spacer(),
          Text(
            '待报销 $pendingCount 笔 · 合计 ',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          Text(
            MoneyFormat.string(pendingTotal),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _TransactionSectionList extends StatelessWidget {
  final List<_DaySection> sections;
  final AppRepository repo;

  const _TransactionSectionList({required this.sections, required this.repo});

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    for (final section in sections) {
      items.add(section);
      items.addAll(section.items);
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _DaySection) {
          return _SectionHeader(section: item);
        } else if (item is TransactionEntity) {
          return _DismissibleRow(transaction: item);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final _DaySection section;

  const _SectionHeader({required this.section});

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (section.day == today) return '今天';
    if (section.day == yesterday) return '昨天';
    return '${section.day.month}月${section.day.day}日 ${_weekday(section.day.weekday)}';
  }

  String _weekday(int w) =>
      const ['一', '二', '三', '四', '五', '六', '日'][w - 1];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expenseItems =
        section.items.where((t) => t.txKind == TransactionKind.expense);
    String subtitle = '';
    if (expenseItems.isNotEmpty) {
      final total = expenseItems.fold(
        Decimal.zero,
        (sum, t) => sum + t.amount,
      );
      subtitle = '支出 ${MoneyFormat.string(total)}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      color: scheme.surface,
      child: Row(
        children: [
          Text(
            _dateLabel(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

class _DismissibleRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _DismissibleRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return TransactionSlidable(
      transaction: transaction,
      child: InkWell(
        onTap: () => showEditTransactionSheet(context, transaction),
        child: _TransactionRow(transaction: transaction),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _TransactionRow({required this.transaction});

  bool get _isTransfer => transaction.txKind == TransactionKind.transfer;

  String get _emoji {
    if (_isTransfer) return '🔁';
    final seed = CategorySeed.all
        .where((s) => s.key == transaction.categoryKey)
        .firstOrNull;
    return seed?.emoji ?? '🏷️';
  }

  String get _title {
    switch (transaction.txKind) {
      case TransactionKind.transfer:
        return '${transaction.accountName} → ${transaction.toAccountName}';
      default:
        final name = transaction.categoryNameZh;
        return name.isNotEmpty ? name : '未分类';
    }
  }

  // 退款冲账 = 负向支出：显示成「+¥x」铜金色，避免 --30 这种丑写法。
  bool get _isRefund =>
      transaction.txKind == TransactionKind.expense &&
      transaction.amount < Decimal.zero;

  String get _amountText {
    if (_isRefund) return '+${MoneyFormat.string(transaction.amount.abs())}';
    final text = MoneyFormat.string(transaction.amount);
    switch (transaction.txKind) {
      case TransactionKind.expense:
        return '-$text';
      case TransactionKind.income:
        return '+$text';
      case TransactionKind.transfer:
        return text;
    }
  }

  Color _amountColor(ColorScheme scheme) {
    if (_isRefund) return AppColors.income(scheme);
    switch (transaction.txKind) {
      case TransactionKind.expense:
        return AppColors.expense(scheme);
      case TransactionKind.income:
        return AppColors.income(scheme);
      case TransactionKind.transfer:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          CatIcon(
            categoryKey: _isTransfer ? 'transfer' : transaction.categoryKey,
            emoji: _emoji,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _title,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (transaction.reimbursable) const _ReimburseBadge(),
                  ],
                ),
                if (transaction.note.isNotEmpty)
                  Text(
                    transaction.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                InlineTagChips(tagIds: transaction.tagIds),
              ],
            ),
          ),
          Text(
            _amountText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _amountColor(scheme),
                  fontWeight: FontWeight.w600,
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

/// 「待报销」小标签。
class _ReimburseBadge extends StatelessWidget {
  const _ReimburseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '待报销',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool onlyReimbursable;

  const _EmptyState({this.onlyReimbursable = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Mascot(mood: MascotMood.empty, size: 72, animate: true),
          const SizedBox(height: 16),
          Text(onlyReimbursable ? '没有待报销的账目' : '还没有账目',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 8),
          Text(
            onlyReimbursable ? '记账时打开「待报销」开关，这里就会列出' : '去「记一笔」页开始记账吧',
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
