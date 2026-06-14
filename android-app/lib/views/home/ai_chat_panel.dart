import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/mascot.dart';
import 'voice_input_sheet.dart';

/// 打开「来记一笔吧」AI 聊天面板（就地弹出，替代旧的跳全屏方案）。
Future<void> showAiChatPanel(
  BuildContext context, {
  required bool speechAvailable,
  required VoidCallback onSwitchToManual,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => AiChatPanel(
      speechAvailable: speechAvailable,
      onSwitchToManual: onSwitchToManual,
    ),
  );
}

/// 「来记一笔吧」聊天面板：一句话 → AI 解析 → 记账确认卡（可保存/撤销）。
/// M3a：记账聊天 + 保存/撤销。查账问答 / 语音校对 / 流式 留 M3b。
class AiChatPanel extends StatefulWidget {
  final bool speechAvailable;
  final VoidCallback onSwitchToManual;

  const AiChatPanel({
    super.key,
    required this.speechAvailable,
    required this.onSwitchToManual,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  static const List<String> _suggestions = [
    '早餐 15',
    '打车 23',
    '买菜 30 块',
    '工资 8500',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  // ── 发送：解析这句话并加一条记账确认卡 ──────────────────────────────────
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;

    _ctrl.clear();
    setState(() {
      _msgs.add(_UserMsg(text));
      _msgs.add(_ThinkingMsg());
      _busy = true;
    });
    _scrollToBottom();

    final repo = context.read<AppRepository>();
    List<ParsedEntry> results = [];
    String? hint;

    final key = repo.deepSeekApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        results = await LlmEntryParser.parseWithLLM(
          text: text,
          apiKey: key,
          expenseCats: CategorySeed.expenses,
          incomeCats: CategorySeed.incomes,
        );
      } catch (_) {
        results = [NaturalLanguageEntryParser.parse(text)];
        hint = 'AI 没连上，喵先用本地规则记了（单笔）';
      }
    } else {
      results = [NaturalLanguageEntryParser.parse(text)];
      hint = '还没配 AI key，喵先用本地规则记（单笔）';
    }

    final cats = results.map((e) => _matchCat(repo, e)).toList();

    if (!mounted) return;
    setState(() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
      if (results.isEmpty) {
        _msgs.add(_InfoMsg('喵没看懂这句，换个说法试试？', error: true));
      } else {
        if (hint != null) _msgs.add(_InfoMsg(hint));
        _msgs.add(_RecordMsg(entries: results, cats: cats));
      }
      _busy = false;
    });
    _scrollToBottom();
  }

  CategoryEntity? _matchCat(AppRepository repo, ParsedEntry e) {
    CategoryEntity? cat;
    if (e.categoryKey != null) {
      cat = repo.categories
          .where((c) => c.kind == e.kind && c.key == e.categoryKey)
          .firstOrNull;
    }
    cat ??= repo.categories
        .where((c) =>
            c.kind == e.kind &&
            (c.key == CategorySeed.fallbackExpenseKey || c.key == 'otherIncome'))
        .firstOrNull;
    return cat;
  }

  // ── 保存这张卡里的账目 ──────────────────────────────────────────────────
  Future<void> _save(_RecordMsg msg) async {
    final repo = context.read<AppRepository>();
    final accountId = repo.accounts.firstOrNull?.id;
    if (accountId == null) {
      _snack('请先在「资产管理」里加一个账户');
      return;
    }
    final before = repo.transactions.map((t) => t.id).toSet();
    for (int i = 0; i < msg.entries.length; i++) {
      final e = msg.entries[i];
      final amt = e.amount;
      if (amt == null || amt <= Decimal.zero) continue;
      await repo.addTransaction(
        kind: e.kind,
        amount: amt,
        categoryId: msg.cats[i]?.id,
        accountId: accountId,
        note: e.note,
        date: e.date,
      );
    }
    final after = repo.transactions.map((t) => t.id).toSet();
    if (!mounted) return;
    setState(() {
      msg.saved = true;
      msg.savedIds = after.difference(before).toList();
    });
  }

  // ── 撤销：删掉刚才保存的那几笔 ─────────────────────────────────────────
  Future<void> _undo(_RecordMsg msg) async {
    final repo = context.read<AppRepository>();
    for (final id in msg.savedIds) {
      await repo.deleteTransaction(id);
    }
    if (!mounted) return;
    setState(() {
      msg.saved = false;
      msg.savedIds = [];
    });
  }

  void _onMicTap() {
    if (!widget.speechAvailable) {
      _snack('该设备不支持语音识别');
      return;
    }
    _focus.unfocus();
    showVoiceInputSheet(context);
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：猫 + 来记一笔吧 + 手动记账 + 关闭 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
              child: Row(
                children: [
                  const Mascot(mood: MascotMood.idle, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    '来记一笔吧',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  _Pill(
                    icon: Icons.swap_horiz,
                    label: '手动记账',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSwitchToManual();
                    },
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── 聊天流 / 空态气泡 ──
            if (_msgs.isEmpty)
              _EmptyHint(
                suggestions: _suggestions,
                onTapSuggestion: (s) => _send(s),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screenH * 0.46),
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) => _buildMsg(_msgs[i]),
                ),
              ),

            // ── 输入行 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '记一笔，如「午餐 32」',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: scheme.onSurfaceVariant.withOpacity(0.55),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(icon: Icons.mic, onTap: _onMicTap),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.arrow_upward,
                    filled: true,
                    onTap: (hasText && !_busy) ? () => _send() : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMsg(_Msg m) {
    if (m is _UserMsg) return _UserBubble(text: m.text);
    if (m is _ThinkingMsg) return const _ThinkingBubble();
    if (m is _InfoMsg) return _InfoBubble(text: m.text, error: m.error);
    if (m is _RecordMsg) {
      return _RecordBubble(
        msg: m,
        onSave: () => _save(m),
        onUndo: () => _undo(m),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 消息模型
// ─────────────────────────────────────────────────────────────────────────────

abstract class _Msg {}

class _UserMsg extends _Msg {
  final String text;
  _UserMsg(this.text);
}

class _ThinkingMsg extends _Msg {}

class _InfoMsg extends _Msg {
  final String text;
  final bool error;
  _InfoMsg(this.text, {this.error = false});
}

class _RecordMsg extends _Msg {
  final List<ParsedEntry> entries;
  final List<CategoryEntity?> cats;
  bool saved;
  List<int> savedIds;
  _RecordMsg({
    required this.entries,
    required this.cats,
    this.saved = false,
    this.savedIds = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 消息气泡
// ─────────────────────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Mascot(mood: MascotMood.thinking, size: 28),
          const SizedBox(width: 8),
          Text('喵在想…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

class _InfoBubble extends StatelessWidget {
  final String text;
  final bool error;
  const _InfoBubble({required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Mascot(
              mood: error ? MascotMood.empty : MascotMood.idle, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: error ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 记账确认卡 ───────────────────────────────────────────────────────────────
class _RecordBubble extends StatelessWidget {
  final _RecordMsg msg;
  final VoidCallback onSave;
  final VoidCallback onUndo;

  const _RecordBubble({
    required this.msg,
    required this.onSave,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = msg.entries.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Mascot(
                  mood: msg.saved ? MascotMood.success : MascotMood.idle,
                  size: 28),
              const SizedBox(width: 8),
              Text(
                msg.saved ? '记好啦！' : (n > 1 ? '帮你拆成 $n 笔：' : '看看对不对：'),
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < msg.entries.length; i++)
                  _EntryRow(
                    entry: msg.entries[i],
                    cat: msg.cats[i],
                    showDivider: i > 0,
                  ),
                const SizedBox(height: 10),
                if (!msg.saved)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onSave,
                      child: Text(n > 1 ? '记下这 $n 笔' : '记下'),
                    ),
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text('已记下',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: onUndo,
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('撤销'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final ParsedEntry entry;
  final CategoryEntity? cat;
  final bool showDivider;

  const _EntryRow({
    required this.entry,
    required this.cat,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.kind == TransactionKind.income;
    final catName = cat?.nameZh ?? (isIncome ? '其他收入' : '其他支出');
    final amountText = entry.amount != null
        ? '${isIncome ? '+' : '-'}${MoneyFormat.string(entry.amount!)}'
        : '未识别金额';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(entry.date.year, entry.date.month, entry.date.day);
    final dateLabel = d == today
        ? '今天'
        : d == today.subtract(const Duration(days: 1))
            ? '昨天'
            : '${entry.date.month}月${entry.date.day}日';

    return Column(
      children: [
        if (showDivider)
          Divider(height: 16, color: scheme.outlineVariant.withOpacity(0.6)),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$catName · $dateLabel',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  if (entry.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: entry.amount == null
                    ? scheme.error
                    : (isIncome ? scheme.secondary : scheme.onSurface),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 空态：猜你想问气泡
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTapSuggestion;

  const _EmptyHint({required this.suggestions, required this.onTapSuggestion});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('试试这样说：',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                GestureDetector(
                  onTap: () => onTapSuggestion(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(s, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 小组件：胶囊 + 圆形按钮
// ─────────────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Pill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _CircleBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (filled) {
      final active = onTap != null;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? scheme.secondary : scheme.onSurface.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 20,
              color:
                  active ? scheme.onSecondary : scheme.onSurface.withOpacity(0.38)),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
