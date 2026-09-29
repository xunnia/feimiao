import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_clock.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/ledger/ledger_policy.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/glass_input.dart';
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

const double _searchBottomChromeHeight = 150.0;
const double _searchTopFilterHeight = 56.0;
const double _searchTopSummaryHeight = 92.0;

String normalizeSearchText(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune == 0x3000) {
      buffer.writeCharCode(0x20);
    } else if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().trim().toLowerCase();
}

List<String> moneySearchTexts(Decimal amount) => [
      MoneyFormat.string(amount),
      MoneyFormat.fixedString(amount),
      amount.toString(),
      amount.toStringAsFixed(2),
    ];

String moneyRangeLabel(Decimal? minAmount, Decimal? maxAmount) {
  if (minAmount != null && maxAmount != null) {
    return '${MoneyFormat.string(minAmount)}~${MoneyFormat.string(maxAmount)}';
  }
  if (minAmount != null) return '≥ ${MoneyFormat.string(minAmount)}';
  if (maxAmount != null) return '≤ ${MoneyFormat.string(maxAmount)}';
  return '金额';
}

/// 时间筛选胶囊文字：都在今年只写月/日，否则带年份（跨年区间分得清）。
String searchDateRangeLabel(DateTimeRange range, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final s = range.start, e = range.end;
  if (s.year == now.year && e.year == now.year) {
    return '${two(s.month)}/${two(s.day)}~${two(e.month)}/${two(e.day)}';
  }
  return '${s.year}/${two(s.month)}/${two(s.day)}~'
      '${e.year}/${two(e.month)}/${two(e.day)}';
}

/// 金额区间：最低填得比最高还大时自动对调，免得一条都筛不出来。
(Decimal?, Decimal?) normalizeAmountRange(Decimal? min, Decimal? max) {
  if (min != null && max != null && min > max) return (max, min);
  return (min, max);
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _ctrl = TextEditingController();
  String _q = '';
  Timer? _debounce;

  // 过滤结果缓存：每次击键防抖300ms后重算，避免 build 内全表扫描
  List<TransactionEntity> _results = const [];
  List<TxSection> _sections = const [];
  Map<int, Decimal> _refundTotals = const {};
  int? _lastFilterRevision;
  String? _lastFilterKey;

  TransactionKind? _kind;
  DateTimeRange? _range;
  int? _accountId;
  int? _tagId;
  Decimal? _minAmt;
  Decimal? _maxAmt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // repo 数据变化（新增/删除账单）时立即重算
    _runFilter();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool get _active => _q.trim().isNotEmpty || _hasFilter;

  bool get _hasFilter =>
      _kind != null ||
      _range != null ||
      _accountId != null ||
      _tagId != null ||
      _minAmt != null ||
      _maxAmt != null;

  void _scheduleFilter() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runFilter);
  }

  void _runFilter() {
    if (!mounted) return;
    final active = _active;
    final filterKey = _filterKey();
    // Keep the empty state usable even when this reusable view is embedded
    // without a repository provider; only an active search needs the ledger.
    if (!active) {
      if (_lastFilterRevision == null && _lastFilterKey == filterKey) return;
      _lastFilterRevision = null;
      _lastFilterKey = filterKey;
      if (_results.isNotEmpty || _sections.isNotEmpty) {
        setState(() {
          _results = const [];
          _sections = const [];
          _refundTotals = const {};
        });
      }
      return;
    }
    final repo = context.read<AppRepository>();
    if (_lastFilterRevision == repo.dataRevision &&
        _lastFilterKey == filterKey) {
      return;
    }
    _lastFilterRevision = repo.dataRevision;
    _lastFilterKey = filterKey;
    final q = _q.trim();
    final all = repo.transactions;
    final rt = LedgerPolicy.refundTotals(all);
    final normalizedQuery = normalizeSearchText(q);
    final r = repo.visibleTransactionsRef
        .where((t) => _pass(t, normalizedQuery, rt))
        .toList();
    final secs = groupTxnsByDay(r);
    setState(() {
      _results = r;
      _sections = secs;
      _refundTotals = rt;
    });
  }

  String _filterKey() {
    final range = _range;
    return [
      _q.trim(),
      _kind?.name ?? '',
      range == null ? '' : range.start.millisecondsSinceEpoch.toString(),
      range == null ? '' : range.end.millisecondsSinceEpoch.toString(),
      _accountId?.toString() ?? '',
      _tagId?.toString() ?? '',
      _minAmt?.toString() ?? '',
      _maxAmt?.toString() ?? '',
    ].join('|');
  }

  bool _pass(
    TransactionEntity t,
    String normalizedQuery,
    Map<int, Decimal> refundTotals,
  ) {
    final userAmount = LedgerPolicy.userAmountWith(t, refundTotals);
    if (normalizedQuery.isNotEmpty) {
      bool contains(String value) =>
          normalizeSearchText(value).contains(normalizedQuery);
      // 分类名空时按列表里显示的「未分类」参与匹配，搜「未分类」才搜得到。
      final catName = t.categoryNameZh.isNotEmpty
          ? t.categoryNameZh
          : (t.txKind == TransactionKind.transfer ? '转账' : '未分类');
      final hit = contains(catName) ||
          contains(t.note) ||
          contains(t.accountName) ||
          contains(t.toAccountName) ||
          contains(t.categoryKey) ||
          moneySearchTexts(t.amount).any(contains) ||
          moneySearchTexts(userAmount).any(contains);
      if (!hit) return false;
    }
    if (_kind != null && t.txKind != _kind) return false;
    if (_range != null) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final s =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final e = DateTime(_range!.end.year, _range!.end.month, _range!.end.day);
      if (d.isBefore(s) || d.isAfter(e)) return false;
    }
    if (_accountId != null && t.accountId != _accountId) return false;
    if (_tagId != null && !t.tagIds.contains(_tagId)) return false;
    final abs = userAmount == Decimal.zero ? t.amount.abs() : userAmount.abs();
    if (_minAmt != null && abs < _minAmt!) return false;
    if (_maxAmt != null && abs > _maxAmt!) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final showSummary = _active && _results.isNotEmpty;
    final topChromeHeight =
        _searchTopFilterHeight + (showSummary ? _searchTopSummaryHeight : 0);
    // 正文从状态栏+标题栏下方开始；虚化层按它在整屏的位置取渐变色，
    // 和透明标题栏后面的背景无缝接上。
    final media = MediaQuery.of(context);
    final screenH = media.size.height <= 0 ? 1.0 : media.size.height;
    final bodyTop = media.padding.top + kToolbarHeight;
    final topSpan = _FadeSpan(
      bodyTop / screenH,
      (bodyTop + topChromeHeight + 32) / screenH,
    );
    final bottomSpan = _FadeSpan(
      (screenH - _searchBottomChromeHeight) / screenH,
      1.0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('搜索'),
        centerTitle: true,
      ),
      // 输入框像主页一样浮在内容上方，后面用底部虚化渐隐过渡，避免一刀切。
      body: Stack(
        children: [
          Positioned.fill(
            child: !_active
                ? Padding(
                    padding: EdgeInsets.only(
                      top: topChromeHeight,
                      bottom: _searchBottomChromeHeight,
                    ),
                    child: _hint(scheme, '输入关键词或选筛选条件', MascotMood.idle),
                  )
                : _results.isEmpty
                    ? Padding(
                        padding: EdgeInsets.only(
                          top: topChromeHeight,
                          bottom: _searchBottomChromeHeight,
                        ),
                        child: _hint(scheme, '没找到符合条件的账单', MascotMood.empty),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          top: topChromeHeight + 8,
                          bottom: _searchBottomChromeHeight,
                        ),
                        itemCount: _sections.length,
                        itemBuilder: (_, i) => TxDayCard(section: _sections[i]),
                      ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: topChromeHeight + 32,
            child: IgnorePointer(
              child: _SearchTopFrostedFade(
                key: const ValueKey('search-top-fade'),
                span: topSpan,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _filterBar(scheme, repo),
                if (showSummary)
                  _summaryCard(scheme, repo, _results, _refundTotals),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _searchBottomChromeHeight,
            child: IgnorePointer(
              child: _SearchBottomFrostedFade(
                key: const ValueKey('search-bottom-fade'),
                span: bottomSpan,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _searchInputBar(scheme, _q),
          ),
        ],
      ),
    );
  }

  /// 顶部统计卡：支出/收入 金额 + 笔数（对齐咔皮）。
  Widget _summaryCard(
    ColorScheme scheme,
    AppRepository repo,
    List<TransactionEntity> rows,
    Map<int, Decimal> refundTotals,
  ) {
    var exp = Decimal.zero, inc = Decimal.zero, xfer = Decimal.zero;
    var expN = 0, incN = 0, xferN = 0;
    for (final t in rows) {
      // 转账不进收支（口径标准 §转账），单独数笔数、合计转出金额；
      // 否则筛「转账」时顶部只剩两个 0。
      if (t.txKind == TransactionKind.transfer) {
        if (!LedgerPolicy.includeInUserTotals(t)) continue;
        xfer += t.amount.abs();
        xferN++;
        continue;
      }
      final amount = LedgerPolicy.userAmountWith(t, refundTotals);
      if (amount == Decimal.zero) continue;
      // 笔数只数净额为正的家族（口径标准 §7.1）：legacy 独立负支出会冲减
      // 合计，但它不是一笔正支出，不能占笔数。
      if (t.txKind == TransactionKind.expense) {
        exp += amount;
        if (amount > Decimal.zero) expN++;
      } else if (t.txKind == TransactionKind.income) {
        inc += amount;
        if (amount > Decimal.zero) incN++;
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Nunito',
                      color: color)),
            ],
          ),
        );
    final divider = Padding(
      padding: const EdgeInsets.only(right: 16),
      child:
          Container(width: 0.5, height: 32, color: AppColors.hairline(scheme)),
    );
    return Padding(
      key: const ValueKey('search-summary'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AppGlassInputShell(
        radius: 18,
        blur: 8,
        opacity: 0.52,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 只筛转账时收支两栏必为 0，干脆只显示转账栏。
            if (_kind != TransactionKind.transfer) ...[
              col('支出', expN, exp, scheme.onSurface),
              divider,
              col('收入', incN, inc, AppColors.income(scheme)),
            ],
            if (xferN > 0 || _kind == TransactionKind.transfer) ...[
              if (_kind != TransactionKind.transfer) divider,
              col('转账', xferN, xfer, scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }

  /// 底部搜索输入框：沿用主页 RecordInputBar 的玻璃卡片语言。
  Widget _searchInputBar(ColorScheme scheme, String q) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: AppGlassInputShell(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: (v) {
                    setState(() => _q = v);
                    _scheduleFilter();
                  },
                  textInputAction: TextInputAction.search,
                  cursorColor: scheme.primary,
                  style: TextStyle(
                    fontSize: 17,
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    hintText: '搜账单 / 备注 / 金额',
                    hintStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w300,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  _SearchSubmitButton(
                    enabled: q.isNotEmpty || _hasFilter,
                    onPressed: () => FocusScope.of(context).unfocus(),
                  ),
                ],
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
    final amtLabel = moneyRangeLabel(_minAmt, _maxAmt);
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
                : searchDateRangeLabel(_range!, AppClock.now),
            _range != null,
            _pickRange,
          ),
          _chip(scheme, accName ?? '账户', _accountId != null,
              (ctx) => _pickAccount(ctx, repo)),
          _chip(scheme, tagName ?? '标签', _tagId != null,
              (ctx) => _pickTag(ctx, repo)),
          _chip(scheme, amtLabel, _minAmt != null || _maxAmt != null,
              _pickAmount),
          if (_hasFilter)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppPillButton(
                label: '清除',
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _kind = null;
                    _range = null;
                    _accountId = null;
                    _tagId = null;
                    _minAmt = null;
                    _maxAmt = null;
                  });
                  _runFilter();
                },
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pickKind(BuildContext anchor) {
    FocusScope.of(context).unfocus();
    showIosMenu(anchor, [
      for (final o in const [
        (null, '全部'),
        (TransactionKind.expense, '支出'),
        (TransactionKind.income, '收入'),
        (TransactionKind.transfer, '转账'),
      ])
        IosMenuItem(
          label: o.$2,
          lineIcon: AppLineIcons.receipt,
          selected: _kind == o.$1,
          onTap: () {
            setState(() => _kind = o.$1);
            _runFilter();
          },
        ),
    ]);
  }

  Future<void> _pickRange(BuildContext _) async {
    final hadFocus = FocusManager.instance.primaryFocus != null;
    FocusScope.of(context).unfocus();
    if (hadFocus) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
    }
    final today = AppClock.now;
    final r = await showAppDateRangePicker(
      context,
      initial: _range,
      defaultStart: today,
      defaultEnd: today,
      first: DateTime(2015),
      last: DateTime(2100),
    );
    if (r != null) {
      setState(() => _range = r);
      _runFilter();
    }
  }

  void _pickAccount(BuildContext anchor, AppRepository repo) {
    FocusScope.of(context).unfocus();
    showIosMenu(anchor, [
      IosMenuItem(
        label: '全部',
        lineIcon: AppLineIcons.wallet,
        selected: _accountId == null,
        onTap: () {
          setState(() => _accountId = null);
          _runFilter();
        },
      ),
      for (final a in repo.accounts)
        IosMenuItem(
          label: a.name,
          lineIcon: AppLineIcons.wallet,
          selected: a.id == _accountId,
          onTap: () {
            setState(() => _accountId = a.id);
            _runFilter();
          },
        ),
    ]);
  }

  void _pickTag(BuildContext anchor, AppRepository repo) {
    FocusScope.of(context).unfocus();
    showIosMenu(anchor, [
      IosMenuItem(
        label: '全部',
        lineIcon: AppLineIcons.tag,
        selected: _tagId == null,
        onTap: () {
          setState(() => _tagId = null);
          _runFilter();
        },
      ),
      for (final t in repo.tags)
        IosMenuItem(
          label: t.name,
          lineIcon: AppLineIcons.tag,
          selected: t.id == _tagId,
          onTap: () {
            setState(() => _tagId = t.id);
            _runFilter();
          },
        ),
    ]);
  }

  Future<void> _pickAmount(BuildContext _) async {
    FocusScope.of(context).unfocus();
    final minC =
        TextEditingController(text: _minAmt != null ? _minAmt.toString() : '');
    final maxC =
        TextEditingController(text: _maxAmt != null ? _maxAmt.toString() : '');
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
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: moneyInputFormatters(),
                        decoration:
                            iosInputDecoration(ctx, hint: '最低', prefix: '¥ '),
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
                        inputFormatters: moneyInputFormatters(),
                        decoration:
                            iosInputDecoration(ctx, hint: '最高', prefix: '¥ '),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                PressableScale(
                  onPressed: () {
                    final (lo, hi) = normalizeAmountRange(
                      Decimal.tryParse(minC.text.trim()),
                      Decimal.tryParse(maxC.text.trim()),
                    );
                    setState(() {
                      _minAmt = lo;
                      _maxAmt = hi;
                    });
                    _runFilter();
                    FocusScope.of(context).unfocus();
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

/// 虚化层在屏幕上的纵向范围（0=屏顶、1=屏底），用来从页面渐变取同位置的色。
class _FadeSpan {
  final double start;
  final double end;

  const _FadeSpan(this.start, this.end);

  Color at(Brightness b, double f) =>
      AppColors.pageBgAt(b, start + (end - start) * f);
}

class _SearchTopFrostedFade extends StatelessWidget {
  final _FadeSpan span;

  const _SearchTopFrostedFade({super.key, required this.span});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.58, 1.0],
        ).createShader(bounds),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  span.at(b, 0.0).withValues(alpha: 0.96),
                  span.at(b, 0.62).withValues(alpha: 0.68),
                  span.at(b, 1.0).withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.62, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _SearchBottomFrostedFade extends StatelessWidget {
  final _FadeSpan span;

  const _SearchBottomFrostedFade({super.key, required this.span});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
          ],
          stops: [0.0, 0.42, 1.0],
        ).createShader(bounds),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  span.at(b, 0.0).withValues(alpha: 0.0),
                  span.at(b, 0.58).withValues(alpha: 0.72),
                  span.at(b, 1.0).withValues(alpha: 0.96),
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _SearchSubmitButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SearchSubmitButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: enabled ? onPressed : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? scheme.secondary
              : scheme.onSurface.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border:
              enabled ? null : Border.all(color: AppColors.hairline(scheme)),
        ),
        child: Icon(
          Icons.arrow_upward,
          size: 18,
          color: enabled
              ? scheme.onSecondary
              : scheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
    );
  }
}
