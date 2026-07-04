import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/transaction_day_list.dart';
import '../common/app_sheet.dart';

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
      // 分类名空时按列表里显示的「未分类」参与匹配，搜「未分类」才搜得到。
      final catName = t.categoryNameZh.isNotEmpty
          ? t.categoryNameZh
          : (t.txKind == TransactionKind.transfer ? '转账' : '未分类');
      final hit = catName.contains(q) ||
          t.note.contains(q) ||
          t.accountName.contains(q) ||
          MoneyFormat.string(t.amount).contains(q) ||
          t.amount.toString().contains(q);
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
        : repo.visibleTransactions.where((t) => _pass(t, q)).toList();

    final sections = groupTxnsByDay(results);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      // 输入框在底部（对齐主页、好点到）；结果用主页同款账单行按天分组。
      body: Column(
        children: [
          _filterBar(scheme, repo),
          // 统计卡：搜索/筛选结果的支出、收入金额与笔数（搜索的价值在这）。
          if (active && results.isNotEmpty) _summaryCard(scheme, results),
          Expanded(
            child: !active
                ? _hint(scheme, '输入关键词或选筛选条件', MascotMood.idle)
                : results.isEmpty
                    ? _hint(scheme, '没找到符合条件的账单', MascotMood.empty)
                    : ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        children: [
                          for (final s in sections) TxDayCard(section: s),
                        ],
                      ),
          ),
          _searchInputBar(scheme, q),
        ],
      ),
    );
  }

  /// 顶部统计卡：支出/收入 金额 + 笔数（对齐咔皮）。
  Widget _summaryCard(ColorScheme scheme, List<TransactionEntity> rows) {
    var exp = Decimal.zero, inc = Decimal.zero;
    var expN = 0, incN = 0;
    for (final t in rows) {
      if (t.txKind == TransactionKind.expense) {
        exp += t.amount;
        expN++;
      } else if (t.txKind == TransactionKind.income) {
        inc += t.amount;
        incN++;
      }
    }
    Widget col(String label, int n, Decimal amt, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('共$n笔',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(MoneyFormat.string(amt),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Nunito',
                      color: color)),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Row(
        children: [
          col('支出', expN, exp, scheme.onSurface),
          Container(width: 0.5, height: 32, color: AppColors.hairline(scheme)),
          const SizedBox(width: 16),
          col('收入', incN, inc, AppColors.income(scheme)),
        ],
      ),
    );
  }

  /// 底部搜索输入框（对齐主页输入框：圆角白卡 + 轻阴影，跟键盘上移）。
  Widget _searchInputBar(ColorScheme scheme, String q) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.hairline(scheme)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 19, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    hintText: '搜账单 / 备注 / 金额',
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (q.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _ctrl.clear();
                    setState(() => _q = '');
                  },
                  child: Icon(Icons.cancel,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
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
              (ctx) => _pickAccount(ctx, repo)),
          _chip(scheme, tagName ?? '标签', _tagId != null,
              (ctx) => _pickTag(ctx, repo)),
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

  Widget _chip(ColorScheme scheme, String label, bool active,
      void Function(BuildContext) onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Builder(
        builder: (chipCtx) => PressableScale(
          onPressed: () => onTap(chipCtx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 激活=主色浅底+主色描边；未选=白底+发丝边（对齐全局胶囊）。
              color: active
                  ? scheme.primary.withValues(alpha: 0.12)
                  : AppColors.card(scheme),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? scheme.primary.withValues(alpha: 0.5)
                    : AppColors.hairline(scheme),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.expand_more,
                    size: 15,
                    color: active ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: active ? scheme.primary : scheme.onSurface,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pickKind(BuildContext anchor) {
    showIosMenu(anchor, [
      for (final o in const [
        (null, '全部'),
        (TransactionKind.expense, '支出'),
        (TransactionKind.income, '收入'),
        (TransactionKind.transfer, '转账'),
      ])
        IosMenuItem(
          label: o.$2,
          icon: _kind == o.$1
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => _kind = o.$1),
        ),
    ]);
  }

  Future<void> _pickRange(BuildContext _) async {
    final r = await showAppDateRangePicker(
      context,
      initial: _range,
      first: DateTime(2015),
      last: DateTime(2100),
    );
    if (r != null) setState(() => _range = r);
  }

  void _pickAccount(BuildContext anchor, AppRepository repo) {
    showIosMenu(anchor, [
      IosMenuItem(
        label: '全部',
        icon: _accountId == null
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
        onTap: () => setState(() => _accountId = null),
      ),
      for (final a in repo.accounts)
        IosMenuItem(
          label: a.name,
          icon: a.id == _accountId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => _accountId = a.id),
        ),
    ]);
  }

  void _pickTag(BuildContext anchor, AppRepository repo) {
    showIosMenu(anchor, [
      IosMenuItem(
        label: '全部',
        icon: _tagId == null
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
        onTap: () => setState(() => _tagId = null),
      ),
      for (final t in repo.tags)
        IosMenuItem(
          label: t.name,
          icon: t.id == _tagId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => _tagId = t.id),
        ),
    ]);
  }

  Future<void> _pickAmount(BuildContext _) async {
    final minC = TextEditingController(
        text: _minAmt != null ? _minAmt.toString() : '');
    final maxC = TextEditingController(
        text: _maxAmt != null ? _maxAmt.toString() : '');
    await showBlurSheet<void>(
      context,
      child: Builder(
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('金额区间',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: iosInputDecoration(ctx,
                            hint: '最低', prefix: '¥ '),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('~',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: maxC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: iosInputDecoration(ctx,
                            hint: '最高', prefix: '¥ '),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                PressableScale(
                  onPressed: () {
                    setState(() {
                      _minAmt = Decimal.tryParse(minC.text.trim());
                      _maxAmt = Decimal.tryParse(maxC.text.trim());
                    });
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.onSurface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('确定',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: scheme.surface)),
                  ),
                ),
              ],
            ),
          );
        },
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

}
