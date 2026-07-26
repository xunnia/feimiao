import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/transaction_actions.dart';
import '../../widgets/transaction_day_list.dart';
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
        leading: const AppBackButton(),
        title: const Text('明细'),
        centerTitle: true,
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final all = repo.visibleTransactions;
          // 待报销列表以 repo 为单一真源，别在页面里自己 filter——
          // 否则这里的「N 笔」和待报销页的会对不上（口径标准 §7.1）。
          final pending = repo.reimbursableTransactions;
          final shown = _onlyReimbursable ? pending : all;

          return Column(
            children: [
              if (pending.isNotEmpty)
                _FilterBar(
                  onlyReimbursable: _onlyReimbursable,
                  pendingCount: pending.length,
                  pendingTotal: pending.fold(
                    Decimal.zero,
                    (sum, t) => sum + repo.netAmountOf(t),
                  ),
                  onToggle: (v) => setState(() => _onlyReimbursable = v),
                ),
              Expanded(
                child: shown.isEmpty
                    ? _EmptyState(onlyReimbursable: _onlyReimbursable)
                    : _TransactionSectionList(sections: _groupByDay(shown)),
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

  const _TransactionSectionList({required this.sections});

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
          return TxDaySectionHeader(
            section: TxSection(day: item.day, items: item.items),
          );
        } else if (item is TransactionEntity) {
          return _DismissibleRow(transaction: item);
        }
        return const SizedBox.shrink();
      },
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
        child: TxRow(transaction: transaction),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool onlyReimbursable;

  const _EmptyState({this.onlyReimbursable = false});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: onlyReimbursable ? '没有待报销的账目' : '还没有账目',
      message: onlyReimbursable ? '记账时打开「待报销」开关，这里就会列出' : '去「记一笔」页开始记账吧',
    );
  }
}
