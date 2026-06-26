import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/mascot.dart';
import '../transactions/edit_transaction_sheet.dart';

/// 明细搜索：关键词(分类/备注/金额) + 类型/时间/账户/标签/金额区间 筛选。
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _ctrl = TextEditingController();
  String _q = '';

  TransactionKind? _kind;
  DateTimeRange? _range;
  int? _accountId;
  int? _tagId;
  Decimal? _minAmt;
  Decimal? _maxAmt;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasFilter =>
      _kind != null ||
      _range != null ||
      _accountId != null ||
      _tagId != null ||
      _minAmt != null ||
      _maxAmt != null;

  String _two(int n) => n.toString().padLeft(2, '0');

  bool _pass(TransactionEntity t, String q) {
    if (q.isNotEmpty) {
      final hit = t.categoryNameZh.contains(q) ||
          t.note.contains(q) ||
          MoneyFormat.string(t.amount).contains(q);
      if (!hit) return false;
    }
    if (_kind != null && t.txKind != _kind) return false;
    if (_range != null) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final s = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final e = DateTime(_range!.end.year, _range!.end.month, _range!.end.day);
      if (d.isBefore(s) || d.isAfter(e)) return false;
    }
    if (_accountId != null && t.accountId != _accountId) return false;
    if (_tagId != null && !t.tagIds.contains(_tagId)) return false;
    final abs = t.amount.abs();
    if (_minAmt != null && abs < _minAmt!) return false;
    if (_maxAmt != null && abs > _maxAmt!) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final q = _q.trim();
    final active = q.isNotEmpty || _hasFilter;
    final results = !active
        ? const <TransactionEntity>[]
        : repo.transactions.where((t) => _pass(t, q)).toList();

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
          if (q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _filterBar(scheme, repo),
        ),
      ),
      body: !active
          ? _hint(scheme, '输入关键词或选筛选条件', MascotMood.idle)
          : results.isEmpty
              ? _hint(scheme, '没找到符合条件的账单', MascotMood.empty)
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  itemBuilder: (_, i) => _row(context, results[i], scheme),
                ),
    );
  }

  Widget _filterBar(ColorScheme scheme, AppRepository repo) {
    final accName =
        repo.accounts.where((a) => a.id == _accountId).firstOrNull?.name;
    final tagName = repo.tags.where((t) => t.id == _tagId).firstOrNull?.name;
    String? amtLabel;
    if (_minAmt != null || _maxAmt != null) {
      amtLabel = '¥${_minAmt ?? 0}~${_maxAmt != null ? '$_maxAmt' : ''}';
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(
            scheme,
            _kind == null
                ? '类型'
                : (_kind == TransactionKind.expense
                    ? '支出'
                    : _kind == TransactionKind.income
                        ? '收入'
                        : '转账'),
            _kind != null,
            _pickKind,
          ),
          _chip(
            scheme,
            _range == null
                ? '时间'
                : '${_two(_range!.start.month)}/${_two(_range!.start.day)}~${_two(_range!.end.month)}/${_two(_range!.end.day)}',
            _range != null,
            _pickRange,
          ),
          _chip(scheme, accName ?? '账户', _accountId != null,
              () => _pickAccount(repo)),
          _chip(scheme, tagName ?? '标签', _tagId != null, () => _pickTag(repo)),
          _chip(scheme, amtLabel ?? '金额',
              _minAmt != null || _maxAmt != null, _pickAmount),
          if (_hasFilter)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton(
                onPressed: () => setState(() {
                  _kind = null;
                  _range = null;
                  _accountId = null;
                  _tagId = null;
                  _minAmt = null;
                  _maxAmt = null;
                }),
                child: const Text('清除'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(
      ColorScheme scheme, String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: ActionChip(
        label: Text(label),
        avatar: Icon(Icons.expand_more,
            size: 16,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
        backgroundColor:
            active ? scheme.primary : scheme.surfaceContainerHighest,
        labelStyle: TextStyle(
          color: active ? scheme.onPrimary : scheme.onSurface,
          fontSize: 13,
        ),
        side: BorderSide.none,
        onPressed: onTap,
      ),
    );
  }

  Future<void> _pickKind() async {
    final v = await _sheet<TransactionKind?>('类型', [
      (null, '全部'),
      (TransactionKind.expense, '支出'),
      (TransactionKind.income, '收入'),
      (TransactionKind.transfer, '转账'),
    ]);
    if (v.$1) setState(() => _kind = v.$2);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (r != null) setState(() => _range = r);
  }

  Future<void> _pickAccount(AppRepository repo) async {
    final v = await _sheet<int?>('账户', [
      (null, '全部'),
      for (final a in repo.accounts) (a.id, a.name),
    ]);
    if (v.$1) setState(() => _accountId = v.$2);
  }

  Future<void> _pickTag(AppRepository repo) async {
    final v = await _sheet<int?>('标签', [
      (null, '全部'),
      for (final t in repo.tags) (t.id, t.name),
    ]);
    if (v.$1) setState(() => _tagId = v.$2);
  }

  /// 通用单选底部表，返回 (是否选了, 选中值)。
  Future<(bool, T)> _sheet<T>(String title, List<(T, String)> options) async {
    T? chosen;
    var picked = false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text(title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$2),
                onTap: () {
                  chosen = o.$1;
                  picked = true;
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
    return (picked, chosen as T);
  }

  Future<void> _pickAmount() async {
    final minC = TextEditingController(
        text: _minAmt != null ? _minAmt.toString() : '');
    final maxC = TextEditingController(
        text: _maxAmt != null ? _maxAmt.toString() : '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('金额区间',
                textAlign: TextAlign.center,
                style: Theme.of(ctx)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minC,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '最低', prefixText: '¥ '),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('~'),
                ),
                Expanded(
                  child: TextField(
                    controller: maxC,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '最高', prefixText: '¥ '),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                setState(() {
                  _minAmt = Decimal.tryParse(minC.text.trim());
                  _maxAmt = Decimal.tryParse(maxC.text.trim());
                });
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(ColorScheme scheme, String text, MascotMood mood) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Mascot(mood: mood, size: 72, animate: true),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );

  Widget _row(BuildContext context, TransactionEntity t, ColorScheme scheme) {
    final income = t.txKind == TransactionKind.income;
    // 退款冲账 = 负向支出：显示成「+¥x」铜金色。
    final isRefund =
        t.txKind == TransactionKind.expense && t.amount.toDouble() < 0;
    final amt = isRefund
        ? '+${MoneyFormat.string(t.amount.abs())}'
        : '${income ? '+' : '-'}${MoneyFormat.string(t.amount)}';
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
          fontWeight: FontWeight.w600,
          fontFamily: 'Nunito',
          color: (income || isRefund) ? scheme.secondary : scheme.onSurface,
        ),
      ),
      onTap: () => showEditTransactionSheet(context, t),
    );
  }
}
