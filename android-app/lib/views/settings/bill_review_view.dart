import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/bill_categorizer.dart';
import '../../widgets/app_buttons.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/haptics.dart';
import '../../core/import/bill_import.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../common/category_picker_sheet.dart';
import 'ai_privacy_consent.dart';

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

  Decimal get total => rows.fold(Decimal.zero, (a, r) => a + r.amount);
}

class _BillReviewViewState extends State<BillReviewView> {
  // 已自动归类的行 →(row, key)；未归类的按商户分组。
  final _autoRows = <(ImportedBillRow, String)>[];
  final _groups = <String, _Group>{};
  final _refunds = <ImportedBillRow>[];
  int? _selectedAccountId;
  bool _aiBusy = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _precategorize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedAccountId ??=
        context.read<AppRepository>().transactionAccounts.firstOrNull?.id;
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
    final hasKey = repo.hasAiApiKey;
    final groups = _sortedGroups;
    final pendingCount = _pending.length;

    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('导入复核'),
          centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                _summaryCard(scheme, groups.length),
                const SizedBox(height: 12),
                _accountPicker(repo),
                const SizedBox(height: 12),
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
          _bottomBar(repo, scheme, pendingCount, hasKey),
        ],
      ),
    );
  }

  int get _groupRowCount => _groups.values.fold(0, (a, g) => a + g.rows.length);

  Widget _accountPicker(AppRepository repo) {
    final selected = repo.transactionAccounts
            .where((account) => account.id == _selectedAccountId)
            .firstOrNull ??
        repo.transactionAccounts.firstOrNull;
    return Builder(
      builder: (anchorContext) => SettingsGroup(
        margin: EdgeInsets.zero,
        children: [
          SettingsRow(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: '入账账户',
            subtitle: '导入的收支和匹配退款会作用于这个账户',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    selected?.name ?? '请先新增账户',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.trailingValue(
                      Theme.of(context).colorScheme,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: repo.transactionAccounts.isEmpty
                ? null
                : () => showIosMenu(
                      anchorContext,
                      [
                        for (final account in repo.transactionAccounts)
                          IosMenuItem(
                            label: account.name,
                            icon: account.id == selected?.id
                                ? Icons.check
                                : Icons.account_balance_wallet_outlined,
                            onTap: () => setState(
                              () => _selectedAccountId = account.id,
                            ),
                          ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(ColorScheme scheme, int groupCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline(scheme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '识别为「${widget.source}」',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _TinyBadge(label: '${widget.rows.length} 笔'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.check_circle_outline,
                label: '自动归类 ${_autoRows.length}',
                color: scheme.primary,
              ),
              _InfoPill(
                icon: Icons.pending_actions_outlined,
                label: '待确认 $groupCount',
                color: groupCount == 0 ? scheme.primary : AppColors.warning,
              ),
              if (_refunds.isNotEmpty)
                _InfoPill(
                  icon: Icons.keyboard_return,
                  label: '退款 ${_refunds.length}',
                  color: AppColors.income(scheme),
                ),
            ],
          ),
          if (groupCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '点分类胶囊即可给同一商户整组归类；建议优先处理笔数和金额大的商户。',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(
    AppRepository repo,
    ColorScheme scheme,
    int pendingCount,
    bool hasKey,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (pendingCount > 0) ...[
              Expanded(
                child: _ActionPill(
                  label: hasKey ? 'AI 归类 $pendingCount' : '配置 AI key',
                  busy: _aiBusy,
                  enabled: !_aiBusy && hasKey,
                  onTap: () => _aiClassify(repo),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: _ActionPill(
                label: '导入 ${_autoRows.length + _groupRowCount} 笔',
                busy: _importing,
                enabled: !_importing,
                onTap: () => _commit(repo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(_Group g, AppRepository repo, ColorScheme scheme) {
    final cat = g.categoryKey == null
        ? null
        : repo.categories.where((c) => c.key == g.categoryKey).firstOrNull;
    final pending = cat == null;
    final title = g.merchant.isEmpty ? '（无商户名）' : g.merchant;
    final sample = g.sampleProduct.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      color: AppColors.card(scheme),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => _pickCategory(context, g, repo),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              CatIcon(
                categoryKey: cat?.key ?? '',
                emoji: cat == null ? '🏷️' : CategorySeed.emojiOf(cat.key),
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppTextColor.primary(scheme),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${g.rows.length} 笔',
                        if (sample.isNotEmpty) sample,
                        g.kind == TransactionKind.income ? '收入' : '支出',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MoneyFormat.string(g.total),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: g.kind == TransactionKind.income
                          ? AppColors.income(scheme)
                          : scheme.onSurface,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CategoryPill(
                    category: cat,
                    pending: pending,
                    onTap: () => _pickCategory(context, g, repo),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory(
      BuildContext anchor, _Group g, AppRepository repo) async {
    final selected = g.categoryKey == null
        ? null
        : repo.categories.where((c) => c.key == g.categoryKey).firstOrNull;
    final picked = await showCategoryPickerSheet(
      anchor,
      kind: g.kind,
      selectedId: selected?.id,
      title: g.kind == TransactionKind.income ? '选择收入分类' : '选择支出分类',
      subtitle: g.merchant.isEmpty ? '未命名商户' : g.merchant,
    );
    if (picked != null && mounted) {
      setState(() => g.categoryKey = picked.key);
    }
  }

  Future<void> _aiClassify(AppRepository repo) async {
    final aiConfig = repo.aiProviderConfigFor(AiTaskType.recordParse);
    if (!aiConfig.hasKey) return;
    final pending = _pending;
    if (pending.isEmpty) return;
    final consented = await ensureAiPrivacyConsent(context);
    if (!consented) return;
    setState(() => _aiBusy = true);
    try {
      var n = 0;
      for (final kind in [TransactionKind.expense, TransactionKind.income]) {
        final kindGroups = pending.where((g) => g.kind == kind).toList();
        for (var start = 0; start < kindGroups.length; start += 25) {
          final end =
              start + 25 > kindGroups.length ? kindGroups.length : start + 25;
          final batch = kindGroups.sublist(start, end);
          final map = await LlmEntryParser.classifyMerchants(
            items: [
              for (final g in batch)
                (merchant: g.merchant, sample: g.sampleProduct)
            ],
            categories: repo.llmCategoryOptions(kind),
            kind: kind,
            config: aiConfig,
          );
          for (final g in batch) {
            final k = map[g.merchant];
            if (k != null &&
                repo.categories.any((c) => c.kind == g.kind && c.key == k)) {
              g.categoryKey = k;
              n++;
            }
          }
          if (mounted) setState(() {});
        }
      }
      if (mounted) {
        Haptics.of(Haptic.success);
        showAppToast(context, 'AI 归好了 $n 个商户');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'AI 归类失败：$e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _commit(AppRepository repo) async {
    final accountId = repo.transactionAccounts
            .where((account) => account.id == _selectedAccountId)
            .firstOrNull
            ?.id ??
        repo.transactionAccounts.firstOrNull?.id;
    if (accountId == null) {
      showAppToast(context, '请先在「资产管理」里加一个账户', icon: Icons.info_outline);
      return;
    }
    setState(() => _importing = true);

    final importRows = <({ImportedBillRow row, String? categoryKey})>[
      for (final (r, key) in _autoRows) (row: r, categoryKey: key),
    ];

    // 分组行：用组分类；并把用户/AI 的选择喂给学习（决定性商户才学）。
    for (final g in _groups.values) {
      final learnKey = BillCategorizer.learnKeyFor(g.merchant);
      if (g.categoryKey != null && learnKey != null) {
        await repo.learnCategory(
            phrase: learnKey, kind: g.kind, categoryKey: g.categoryKey!);
      }
      for (final r in g.rows) {
        importRows.add((row: r, categoryKey: g.categoryKey));
      }
    }

    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: importRows,
      refunds: _refunds,
    );

    if (mounted) {
      Haptics.of(Haptic.success);
      final skipped = result.skippedDuplicates > 0
          ? '，跳过重复 ${result.skippedDuplicates} 笔'
          : '';
      final refunds =
          result.refundsAttached > 0 ? '，挂回退款 ${result.refundsAttached} 笔' : '';
      final unresolved = result.unresolvedRefunds > 0
          ? '，${result.unresolvedRefunds} 笔退款未匹配，未导入'
          : '';
      showAppToast(
        context,
        '已导入 ${result.inserted} 笔$refunds$skipped$unresolved',
      );
      Navigator.pop(context, result.inserted);
    }
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;

  const _TinyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = AppColors.card(scheme);
    final fg = scheme.onSurface;
    return PressableScale(
      onPressed: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.42,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: AppColors.hairline(scheme, strength: 1.4)),
          ),
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final CategoryEntity? category;
  final bool pending;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.category,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = pending ? AppColors.warning : scheme.primary;
    return PressableScale(
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 128),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: pending ? 0.11 : 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category != null) ...[
              CatIcon(
                categoryKey: category!.key,
                emoji: CategorySeed.emojiOf(category!.key),
                size: 16,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                category?.nameZh ?? '待分类',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
