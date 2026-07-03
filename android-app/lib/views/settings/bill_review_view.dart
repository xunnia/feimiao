import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/bill_categorizer.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/haptics.dart';
import '../../core/import/bill_import.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';

/// 导入复核页（智能分类第3/4层）：每行先自动归类，剩余未归类的**按商户分组**，
/// 用户点一次就给整组归类（顺便喂学习），或一次 AI 批量归类。确认后才入库。
class BillReviewView extends StatefulWidget {
  final List<ImportedBillRow> rows;
  final String source;
  final int skipped;

  const BillReviewView({
    super.key,
    required this.rows,
    required this.source,
    required this.skipped,
  });

  @override
  State<BillReviewView> createState() => _BillReviewViewState();
}

/// 未归类的商户分组（同一归一化商户的所有行共用一个分类）。
class _Group {
  final String merchant; // 归一化后的商户主体（展示 + 学习键）
  final TransactionKind kind;
  final List<ImportedBillRow> rows = [];
  String sampleProduct;
  String? categoryKey; // 用户/AI 指定的分类

  _Group(this.merchant, this.kind, this.sampleProduct);

  Decimal get total =>
      rows.fold(Decimal.zero, (a, r) => a + r.amount);
}

class _BillReviewViewState extends State<BillReviewView> {
  // 已自动归类的行 →(row, key)；未归类的按商户分组。
  final _autoRows = <(ImportedBillRow, String)>[];
  final _groups = <String, _Group>{};
  final _refunds = <ImportedBillRow>[];
  bool _aiBusy = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _precategorize();
  }

  void _precategorize() {
    final repo = context.read<AppRepository>();
    for (final r in widget.rows) {
      if (r.isRefund) {
        _refunds.add(r);
        continue;
      }
      // 1) 用户学习记忆 → 2) 分类器
      final learned = repo.recallCategoryKey(
          '${r.merchant} ${r.product} ${r.note}', r.kind);
      final key = learned ??
          BillCategorizer.classify(
            merchant: r.merchant,
            product: r.product,
            note: '${r.category} ${r.note}',
            kind: r.kind,
          ).key;
      if (key != null && repo.categories.any((c) => c.key == key)) {
        _autoRows.add((r, key));
      } else {
        final m = BillCategorizer.normalizeMerchant(r.merchant);
        final gkey = '${r.kind.name}|${m.isEmpty ? r.note : m}';
        final g = _groups.putIfAbsent(
            gkey, () => _Group(m.isEmpty ? r.note : m, r.kind, r.product));
        g.rows.add(r);
        if (g.sampleProduct.isEmpty) g.sampleProduct = r.product;
      }
    }
  }

  List<_Group> get _pending =>
      _groups.values.where((g) => g.categoryKey == null).toList()
        ..sort((a, b) => b.rows.length.compareTo(a.rows.length));

  List<_Group> get _sortedGroups => _groups.values.toList()
    ..sort((a, b) => b.rows.length.compareTo(a.rows.length));

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final hasKey = (repo.deepSeekApiKey ?? '').isNotEmpty;
    final groups = _sortedGroups;
    final pendingCount = _pending.length;

    return Scaffold(
      appBar: AppBar(title: const Text('导入复核'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                Text(
                  '识别为「${widget.source}」，共 ${widget.rows.length} 笔。'
                  '已自动归类 ${_autoRows.length} 笔'
                  '${_refunds.isNotEmpty ? '、退款 ${_refunds.length} 笔挂回原单' : ''}。'
                  '${groups.isEmpty ? '' : '\n下面 ${groups.length} 个商户请确认分类（点一次归一整组）：'}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.5),
                ),
                const SizedBox(height: 10),
                for (final g in groups) _groupCard(g, repo, scheme),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text('全部自动归类完成，直接导入即可喵',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          // 底部操作栏
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  if (pendingCount > 0)
                    Expanded(
                      child: PressableScale(
                        onPressed: (_aiBusy || !hasKey)
                            ? null
                            : () => _aiClassify(repo),
                        child: Opacity(
                          opacity: (_aiBusy || !hasKey) ? 0.4 : 1,
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.card(scheme),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.5)),
                            ),
                            child: _aiBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(
                                    hasKey
                                        ? 'AI 归类剩 $pendingCount 个'
                                        : '需先配 AI key',
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.primary)),
                          ),
                        ),
                      ),
                    ),
                  if (pendingCount > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PressableScale(
                      onPressed: _importing ? null : () => _commit(repo),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: _importing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: scheme.surface))
                            : Text('导入 ${_autoRows.length + _groupRowCount} 笔',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.surface)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _groupRowCount =>
      _groups.values.fold(0, (a, g) => a + g.rows.length);

  Widget _groupCard(_Group g, AppRepository repo, ColorScheme scheme) {
    final cat =
        g.categoryKey == null ? null : repo.categories.where((c) => c.key == g.categoryKey).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: g.categoryKey == null
                ? AppColors.warning.withValues(alpha: 0.4)
                : AppColors.hairline(scheme)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.merchant.isEmpty ? '（无商户名）' : g.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
                Text(
                  '${g.rows.length} 笔 · ${MoneyFormat.string(g.total)}',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Builder(
            builder: (chipCtx) => PressableScale(
              onPressed: () => _pickCategory(chipCtx, g, repo),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: g.categoryKey == null
                      ? AppColors.warning.withValues(alpha: 0.12)
                      : scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cat != null) ...[
                      CatIcon(
                          categoryKey: cat.key,
                          emoji: CategorySeed.emojiOf(cat.key),
                          size: 16),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      cat?.nameZh ?? '待分类',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: g.categoryKey == null
                            ? AppColors.warning
                            : scheme.primary,
                      ),
                    ),
                    Icon(Icons.expand_more,
                        size: 15,
                        color: g.categoryKey == null
                            ? AppColors.warning
                            : scheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pickCategory(BuildContext anchor, _Group g, AppRepository repo) {
    final tops = repo.categoriesForKindRanked(g.kind);
    showIosMenu(anchor, [
      for (final c in tops)
        IosMenuItem(
          label: '${CategorySeed.emojiOf(c.key)} ${c.nameZh}',
          icon: c.key == g.categoryKey
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() => g.categoryKey = c.key),
        ),
    ]);
  }

  Future<void> _aiClassify(AppRepository repo) async {
    final key = repo.deepSeekApiKey;
    if (key == null || key.isEmpty) return;
    final pending = _pending;
    if (pending.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final map = await LlmEntryParser.classifyMerchants(
        items: [
          for (final g in pending) (merchant: g.merchant, sample: g.sampleProduct)
        ],
        expenseCats: repo.llmCategoryOptions(TransactionKind.expense),
        apiKey: key,
      );
      var n = 0;
      for (final g in pending) {
        final k = map[g.merchant];
        if (k != null && repo.categories.any((c) => c.key == k)) {
          g.categoryKey = k;
          n++;
        }
      }
      if (mounted) {
        Haptics.of(Haptic.success);
        showAppToast(context, 'AI 归好了 $n 个商户');
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'AI 归类失败，手动点也行喵',
            icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _commit(AppRepository repo) async {
    final accountId = repo.accounts.firstOrNull?.id;
    if (accountId == null) {
      showAppToast(context, '请先在「资产管理」里加一个账户',
          icon: Icons.info_outline);
      return;
    }
    setState(() => _importing = true);

    int? idOf(String? key, TransactionKind k) => key == null
        ? null
        : repo.categories
            .where((c) => c.key == key && c.kind == k)
            .firstOrNull
            ?.id;

    final orderToId = <String, int>{};
    var count = 0;

    Future<void> insert(ImportedBillRow r, String? key) async {
      final id = await repo.addTransaction(
        kind: r.kind,
        amount: r.amount,
        categoryId: idOf(key, r.kind),
        accountId: accountId,
        note: r.note,
        date: r.date,
      );
      if (r.orderNo.isNotEmpty) orderToId[r.orderNo] = id;
      count++;
    }

    // 自动归类的行。
    for (final (r, key) in _autoRows) {
      await insert(r, key);
    }
    // 分组行：用组分类；并把用户/AI 的选择喂给学习（决定性商户才学）。
    for (final g in _groups.values) {
      final learnKey = BillCategorizer.learnKeyFor(g.merchant);
      if (g.categoryKey != null && learnKey != null) {
        await repo.learnCategory(
            phrase: learnKey, kind: g.kind, categoryKey: g.categoryKey!);
      }
      for (final r in g.rows) {
        await insert(r, g.categoryKey);
      }
    }
    // 退款挂回原单（商户订单号一致）。
    for (final r in _refunds) {
      final origId = orderToId[r.orderNo];
      if (origId == null) continue;
      final orig = repo.transactions.where((t) => t.id == origId).firstOrNull;
      if (orig != null) await repo.refundTransaction(orig, r.amount);
    }

    if (mounted) {
      Haptics.of(Haptic.success);
      Navigator.pop(context, count);
    }
  }
}
