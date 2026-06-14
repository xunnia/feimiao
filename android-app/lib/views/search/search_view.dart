import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/mascot.dart';
import '../transactions/edit_transaction_sheet.dart';

/// 明细搜索：按 分类名 / 备注 / 金额 关键词过滤当前账本的账单。
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final q = _q.trim();
    final results = q.isEmpty
        ? const <TransactionEntity>[]
        : repo.transactions.where((t) {
            return t.categoryNameZh.contains(q) ||
                t.note.contains(q) ||
                MoneyFormat.string(t.amount).contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            hintText: '搜账单 / 备注 / 金额',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
        ],
      ),
      body: q.isEmpty
          ? _hint(scheme, '输入关键词找账单', MascotMood.idle)
          : results.isEmpty
              ? _hint(scheme, '没找到「$q」相关的账单', MascotMood.empty)
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: scheme.outlineVariant.withOpacity(0.4),
                  ),
                  itemBuilder: (_, i) => _row(context, results[i], scheme),
                ),
    );
  }

  Widget _hint(ColorScheme scheme, String text, MascotMood mood) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Mascot(mood: mood, size: 72),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );

  Widget _row(BuildContext context, TransactionEntity t, ColorScheme scheme) {
    final income = t.txKind == TransactionKind.income;
    final amt = '${income ? '+' : '-'}${MoneyFormat.string(t.amount)}';
    final dateStr = '${t.date.year}-${t.date.month}-${t.date.day}';
    return ListTile(
      title: Text(
        t.categoryNameZh.isNotEmpty ? t.categoryNameZh : '未分类',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        t.note.isNotEmpty ? '$dateStr · ${t.note}' : dateStr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        amt,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: income ? scheme.secondary : scheme.onSurface,
        ),
      ),
      onTap: () => showEditTransactionSheet(context, t),
    );
  }
}
