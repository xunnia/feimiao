import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';

/// 流水明细页：按天分组 + 当日小计 + 左滑删除 + 空状态。
/// 对应 iOS TransactionListView.swift。
class TransactionListView extends StatelessWidget {
  const TransactionListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('明细'),
        centerTitle: true,
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final transactions = repo.transactions;
          if (transactions.isEmpty) {
            return _EmptyState();
          }
          final sections = _groupByDay(transactions);
          return _TransactionSectionList(sections: sections, repo: repo);
        },
      ),
    );
  }

  /// 按日期（截断到天）分组，降序排列。
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
}

class _DaySection {
  final DateTime day;
  final List<TransactionEntity> items;
  const _DaySection({required this.day, required this.items});
}

// ---------------------------------------------------------------------------
// 带分组头的列表
// ---------------------------------------------------------------------------

class _TransactionSectionList extends StatelessWidget {
  final List<_DaySection> sections;
  final AppRepository repo;

  const _TransactionSectionList({required this.sections, required this.repo});

  @override
  Widget build(BuildContext context) {
    // 展平为带头部的扁平列表（方便 ListView.builder）
    // 元素类型：_DaySection（表头）或 TransactionEntity（行）
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
          return _DismissibleRow(
            transaction: item,
            onDelete: () => repo.deleteTransaction(item.id),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 分组表头
// ---------------------------------------------------------------------------

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
    // 当日支出合计
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

// ---------------------------------------------------------------------------
// 可左滑删除的交易行
// ---------------------------------------------------------------------------

class _DismissibleRow extends StatelessWidget {
  final TransactionEntity transaction;
  final VoidCallback onDelete;

  const _DismissibleRow({required this.transaction, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除这笔账？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: _TransactionRow(transaction: transaction),
    );
  }
}

// ---------------------------------------------------------------------------
// 交易行内容
// ---------------------------------------------------------------------------

class _TransactionRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _TransactionRow({required this.transaction});

  IconData get _icon {
    if (transaction.txKind == TransactionKind.transfer) {
      return Icons.swap_horiz;
    }
    final seed = CategorySeed.all
        .where((s) => s.key == transaction.categoryKey)
        .firstOrNull;
    return seed?.icon ?? Icons.label_outline;
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

  String get _amountText {
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
          // 分类图标圆形背景
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            child: Icon(_icon, size: 20, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          // 标题 + 备注
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: Theme.of(context).textTheme.bodyMedium,
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
              ],
            ),
          ),
          // 金额
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

// ---------------------------------------------------------------------------
// 空状态
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有账目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '去「记一笔」页开始记账吧',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
