import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:provider/provider.dart';

import '../../build_info.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/merchant_category.dart';
import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/ai/smart_tags.dart';
import '../../core/meal_time.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/app_toast.dart';
import '../settings/ai_setting_view.dart';

/// AI 一句话记账页。
///
/// 配置了 DeepSeek API Key → 调 LLM，支持一句话拆多笔；
/// 未配置或调用失败 → 降级为本地单笔规则解析。
///
/// [initialText] 非空时，页面打开后自动填入输入框并触发解析
/// （从 RecordInputBar 的 AI 模式直接带文字跳过来时使用）。
class AiQuickEntryView extends StatefulWidget {
  final String? initialText;

  /// 文字来自截图 OCR 时置 true：解析走专门的截图提取提示词。
  final bool fromScreenshot;

  const AiQuickEntryView({
    super.key,
    this.initialText,
    this.fromScreenshot = false,
  });

  @override
  State<AiQuickEntryView> createState() => _AiQuickEntryViewState();
}

class _AiQuickEntryViewState extends State<AiQuickEntryView> {
  final TextEditingController _inputCtrl = TextEditingController();

  /// 解析结果（多笔）；null 表示尚未解析。
  List<ParsedEntry>? _entries;

  /// 对应每笔匹配到的分类实体列表，与 _entries 等长。
  List<CategoryEntity?> _matchedCats = [];

  bool _loading = false;
  bool _saving = false;

  /// 是否因降级（未配置 key 或 LLM 失败）而用了本地解析。
  bool _usedFallback = false;

  /// 降级原因提示文字。
  String _fallbackHint = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText;
    if (initial != null && initial.isNotEmpty) {
      _inputCtrl.text = initial;
      // 延后一帧，等 context 就绪后自动触发解析
      WidgetsBinding.instance.addPostFrameCallback((_) => _doParse());
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 解析
  // ---------------------------------------------------------------------------

  Future<void> _doParse() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final repo = context.read<AppRepository>();
    setState(() {
      _loading = true;
      _entries = null;
      _matchedCats = [];
      _usedFallback = false;
      _fallbackHint = '';
    });

    try {
      final apiKey = repo.deepSeekApiKey;
      List<ParsedEntry> results;
      bool usedFallback = false;
      String fallbackHint = '';

      if (apiKey != null && apiKey.isNotEmpty) {
        // 尝试 LLM 解析
        try {
          results = (await LlmEntryParser.parseWithLLM(
            text: text,
            apiKey: apiKey,
            expenseCats: CategorySeed.expenses,
            incomeCats: CategorySeed.incomes,
            fromScreenshot: widget.fromScreenshot,
          ))
              .entries;
        } on LlmParseException catch (e) {
          // LLM 失败 → 降级
          results = [NaturalLanguageEntryParser.parse(text)];
          usedFallback = true;
          fallbackHint = 'AI 解析失败（${e.message}），已用本地简易解析（单笔）';
        } catch (e) {
          results = [NaturalLanguageEntryParser.parse(text)];
          usedFallback = true;
          fallbackHint = 'AI 调用出错，已用本地简易解析（单笔）';
        }
      } else {
        // 未配置 key → 降级
        results = [NaturalLanguageEntryParser.parse(text)];
        usedFallback = true;
        fallbackHint = '未配置 AI 或解析失败，已用本地简易解析（单笔）';
      }

      // 为每笔结果匹配分类实体：用户记忆 > 商户/关键词词典 > 大模型 > 兜底。
      final matched = results.map((entry) {
        CategoryEntity? cat;
        final learned = repo.recallCategoryKey(entry.note, entry.kind);
        final dict = MerchantCategory.classify(entry.note, entry.kind);
        final wantKey = MealTime.refine(
            learned ?? dict ?? entry.categoryKey, entry.date, entry.note);
        if (wantKey != null) {
          cat = repo.categories
              .where((c) => c.kind == entry.kind && c.key == wantKey)
              .firstOrNull;
        }
        // 未匹配 → 兜底 other / otherIncome
        cat ??= repo.categories
            .where((c) =>
                c.kind == entry.kind &&
                (c.key == CategorySeed.fallbackExpenseKey ||
                    c.key == 'otherIncome'))
            .firstOrNull;
        return cat;
      }).toList();

      if (mounted) {
        setState(() {
          _entries = results;
          _matchedCats = matched;
          _usedFallback = usedFallback;
          _fallbackHint = fallbackHint;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 批量保存
  // ---------------------------------------------------------------------------

  Future<void> _saveAll() async {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;

    final repo = context.read<AppRepository>();
    final accountId = repo.accounts.firstOrNull?.id;
    if (accountId == null) return;

    setState(() => _saving = true);
    try {
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final amount = e.amount;
        if (amount == null || amount <= Decimal.zero) continue;
        await repo.addTransaction(
          kind: e.kind,
          amount: amount,
          categoryId: _matchedCats[i]?.id,
          accountId: accountId,
          note: e.note,
          date: e.date,
          reimbursable: SmartTags.isReimbursable(e.note),
        );
      }
      if (mounted) {
        showAppToast(context, '已保存 ${entries.length} 笔账目');
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 是否有至少一笔有效金额
  // ---------------------------------------------------------------------------

  bool get _hasValidEntry =>
      _entries?.any((e) =>
              e.amount != null && e.amount! > Decimal.zero) ??
          false;

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final hasKey =
        (repo.deepSeekApiKey ?? '').isNotEmpty;
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        centerTitle: true,
        actions: [
          // 快捷跳转 AI 设置
          if (!hasKey)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                    builder: (_) => const AiSettingView()),
              ),
              child: const Text('配置'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 说明文字
              Row(
                children: [
                  Icon(
                    hasKey
                        ? Icons.smart_toy_outlined
                        : Icons.auto_awesome_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasKey
                          ? '用一句话描述多笔记录，AI 自动拆分 · $kBuildTag'
                          : '用一句话描述这笔记录，本地即刻解析 · $kBuildTag',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 输入框
              TextField(
                controller: _inputCtrl,
                maxLines: 3,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _doParse(),
                decoration: InputDecoration(
                  hintText: hasKey
                      ? '例如：昨天买了20块肉、30的衣服、前天交房租1500'
                      : '例如：昨天打车23块、工资发了8500',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                onChanged: (_) {
                  if (_entries != null) {
                    setState(() {
                      _entries = null;
                      _matchedCats = [];
                      _usedFallback = false;
                      _fallbackHint = '';
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // 解析按钮
              FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_loading ? '解析中…' : '解析'),
                onPressed: (_inputCtrl.text.trim().isEmpty || _loading)
                    ? null
                    : _doParse,
              ),

              // 降级提示
              if (_usedFallback && _fallbackHint.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 16, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fallbackHint,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 结果列表
              if (entries != null) ...[
                const SizedBox(height: 20),
                ...List.generate(entries.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EntryCard(
                      entry: entries[i],
                      matchedCategory: _matchedCats[i],
                      index: i + 1,
                      total: entries.length,
                    ),
                  );
                }),
                const SizedBox(height: 8),

                // 全部保存按钮
                FilledButton(
                  onPressed: (!_hasValidEntry || _saving) ? null : _saveAll,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          entries.length > 1
                              ? '全部保存（${entries.length} 笔）'
                              : '保存这笔',
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 单笔结果卡片
// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  final ParsedEntry entry;
  final CategoryEntity? matchedCategory;
  final int index;
  final int total;

  const _EntryCard({
    required this.entry,
    required this.matchedCategory,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.kind == TransactionKind.income;
    final kindLabel = isIncome ? '收入' : '支出';
    final kindColor =
        isIncome ? scheme.primary : scheme.onSurface;

    final amountText = entry.amount != null
        ? MoneyFormat.string(entry.amount!)
        : '（未识别金额）';

    final categoryName =
        matchedCategory?.nameZh ?? (isIncome ? '其他收入' : '其他支出');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDay = DateTime(
        entry.date.year, entry.date.month, entry.date.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateLabel = entryDay == today
        ? '今天'
        : entryDay == yesterday
            ? '昨天'
            : '${entry.date.month}月${entry.date.day}日';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 序号（多笔时显示）+ 收/支 + 金额
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (total > 1) ...[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$index',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: scheme.onSecondaryContainer,
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kindColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    kindLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                          color: kindColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    amountText,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Nunito',
                          color: entry.amount == null
                              ? scheme.error
                              : scheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 分类 + 日期 + 备注
            _InfoRow(
              icon: Icons.label_outline,
              label: '分类',
              value: categoryName,
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: '日期',
              value: dateLabel,
            ),
            if (entry.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.notes_outlined,
                label: '备注',
                value: entry.note,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label：',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
