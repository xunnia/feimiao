import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';

/// AI 一句话记账页。
/// 输入自然语言文本 → 本地解析 → 预览结果卡片 → 一键保存。
class AiQuickEntryView extends StatefulWidget {
  const AiQuickEntryView({super.key});

  @override
  State<AiQuickEntryView> createState() => _AiQuickEntryViewState();
}

class _AiQuickEntryViewState extends State<AiQuickEntryView> {
  final TextEditingController _inputCtrl = TextEditingController();

  /// 当前解析结果，null 表示尚未解析。
  ParsedEntry? _parsed;

  /// 解析后匹配到的数据库分类实体（可为 null，此时降级为"其他"）。
  CategoryEntity? _matchedCategory;

  bool _saving = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 解析

  void _doParse() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final result = NaturalLanguageEntryParser.parse(text);
    final repo = context.read<AppRepository>();

    // 用 categoryKey 在 repository 分类里查找，找不到则用"其他"兜底
    CategoryEntity? matched;
    if (result.categoryKey != null) {
      matched = repo.categories
          .where((c) => c.kind == result.kind && c.key == result.categoryKey)
          .firstOrNull;
    }
    // 仍为 null 则取对应收/支方向的 other / otherIncome
    matched ??= repo.categories
        .where((c) =>
            c.kind == result.kind &&
            (c.key == CategorySeed.fallbackExpenseKey || c.key == 'otherIncome'))
        .firstOrNull;

    setState(() {
      _parsed = result;
      _matchedCategory = matched;
    });
  }

  // ---------------------------------------------------------------------------
  // 保存

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final amount = parsed.amount;
    if (amount == null || amount <= Decimal.zero) return;

    final repo = context.read<AppRepository>();
    final accountId = repo.accounts.firstOrNull?.id;
    if (accountId == null) return;

    setState(() => _saving = true);
    try {
      await repo.addTransaction(
        kind: parsed.kind,
        amount: amount,
        categoryId: _matchedCategory?.id,
        accountId: accountId,
        note: parsed.note,
        date: parsed.date,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('AI 记账成功'),
              ],
            ),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        centerTitle: true,
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
                  Icon(Icons.auto_awesome_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '用一句话描述这笔记录，本地即刻解析',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
                  hintText: '例如：昨天打车23块、工资发了8500',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.5),
                ),
                onChanged: (_) {
                  // 输入变化时清空旧结果，需重新解析
                  if (_parsed != null) setState(() => _parsed = null);
                },
              ),
              const SizedBox(height: 12),

              // 解析按钮
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('解析'),
                onPressed: _inputCtrl.text.trim().isEmpty ? null : _doParse,
              ),

              // 结果卡片
              if (_parsed != null) ...[
                const SizedBox(height: 20),
                _ParseResultCard(
                  parsed: _parsed!,
                  matchedCategory: _matchedCategory,
                ),
                const SizedBox(height: 16),

                // 保存按钮
                FilledButton(
                  onPressed: (_parsed?.amount == null ||
                              (_parsed?.amount ?? Decimal.zero) <=
                                  Decimal.zero ||
                              _saving)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存这笔'),
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
// 解析结果卡片
// ---------------------------------------------------------------------------

class _ParseResultCard extends StatelessWidget {
  final ParsedEntry parsed;
  final CategoryEntity? matchedCategory;

  const _ParseResultCard({
    required this.parsed,
    required this.matchedCategory,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = parsed.kind == TransactionKind.income;
    final kindLabel = isIncome ? '收入' : '支出';
    final kindColor = isIncome
        ? Theme.of(context).colorScheme.primary
        : scheme.onSurface;

    final amountText = parsed.amount != null
        ? MoneyFormat.string(parsed.amount!)
        : '（未识别金额）';

    final categoryName =
        matchedCategory?.nameZh ?? (isIncome ? '其他收入' : '其他支出');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parsedDay = DateTime(
        parsed.date.year, parsed.date.month, parsed.date.day);
    final dateLabel = parsedDay == today
        ? '今天'
        : parsedDay == today.subtract(const Duration(days: 1))
            ? '昨天'
            : '${parsed.date.month}月${parsed.date.day}日';

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
            // 收/支 + 金额
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kindColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    kindLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: kindColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amountText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: parsed.amount == null
                            ? scheme.error
                            : scheme.onSurface,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 分类 + 日期
            _InfoRow(
              icon: Icons.label_outline,
              label: '分类',
              value: categoryName,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: '日期',
              value: dateLabel,
            ),
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
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label：',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
