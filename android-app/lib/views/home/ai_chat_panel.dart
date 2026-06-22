import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/glass.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import 'record_extras_sheet.dart';

/// 打开「来记一笔吧」AI 聊天面板（就地弹出，替代旧的跳全屏方案）。
Future<void> showAiChatPanel(
  BuildContext context, {
  required VoidCallback onSwitchToManual,
  String? initialText,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '记账',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => AiChatPanel(
      onSwitchToManual: onSwitchToManual,
      initialText: initialText,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      // 背景高斯模糊（随动画渐入）+ 浮层上滑淡入。
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10 * anim.value,
          sigmaY: 10 * anim.value,
        ),
        child: FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// 「来记一笔吧」聊天面板：一句话 → AI 解析 → 记账确认卡（可保存/撤销）。
/// 语音用键盘自带听写打到输入框即可，不再内置录音识别。
class AiChatPanel extends StatefulWidget {
  final VoidCallback onSwitchToManual;

  /// 预填到输入框的文字，不自动发送，供校对再发。
  final String? initialText;

  const AiChatPanel({
    super.key,
    required this.onSwitchToManual,
    this.initialText,
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

  // 查账/建设性建议池（记账建议从历史账单分析得来，见 _pickSuggestions）。
  static const List<String> _queryPool = [
    '这个月花了多少',
    '最大一笔开销',
    '这周吃饭花了多少',
    '本月预算还剩多少',
    '今天花了多少',
    '这个月哪类花最多',
    '上个月花了多少',
    '本月比上月多吗',
  ];
  List<String> _picked = const [];
  bool _pickInit = false;

  /// 建议来源：从历史支出挑「常记分类(≥3 次)」生成记账建议（带中位金额），
  /// 规律不足就用查账类「建设性建议」补满 4 条。不推没记过的东西。
  List<String> _pickSuggestions(AppRepository repo) {
    final r = Random();
    final counts = <String, int>{};
    final amounts = <String, List<Decimal>>{};
    for (final t in repo.transactions) {
      if (t.txKind != TransactionKind.expense) continue;
      final name = t.categoryNameZh;
      if (name.isEmpty || name == '未分类') continue;
      counts[name] = (counts[name] ?? 0) + 1;
      (amounts[name] ??= <Decimal>[]).add(t.amount);
    }
    final frequent = counts.entries.where((e) => e.value >= 3).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final recs = <String>[];
    for (final e in frequent.take(4)) {
      final list = amounts[e.key]!..sort();
      var amt = list[list.length ~/ 2].toString();
      if (amt.endsWith('.00')) amt = amt.substring(0, amt.length - 3);
      recs.add('记一笔 ${e.key} $amt');
    }
    recs.shuffle(r);

    final qs = List<String>.from(_queryPool)..shuffle(r);
    final picked = <String>[...recs.take(2)];
    picked.addAll(qs.take(4 - picked.length));
    // 短的排前面 → 第一行短建议、第二行长建议
    return picked.take(4).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
  }

  @override
  void initState() {
    super.initState();
    final init = widget.initialText?.trim();
    if (init != null && init.isNotEmpty) {
      _ctrl.text = init;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pickInit) {
      _pickInit = true;
      _picked = _pickSuggestions(context.read<AppRepository>());
    }
  }

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

  // ── 发送：先判意图（查账 or 记账）再分流 ────────────────────────────────
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;

    _ctrl.clear();
    final isQuery = _looksLikeQuery(text);
    setState(() {
      _msgs.add(_UserMsg(text));
      _msgs.add(_ThinkingMsg());
      _busy = true;
    });
    _scrollToBottom();

    if (isQuery) {
      await _runQuery(text);
    } else {
      await _runRecord(text);
    }
  }

  /// 意图判断：能解析出金额 → 记账；否则含疑问词 → 查账。
  bool _looksLikeQuery(String t) {
    if (NaturalLanguageEntryParser.extractAmount(t) != null) return false;
    const markers = [
      '多少', '几', '吗', '?', '？', '排行', '最大', '最多', '最贵', '花了',
      '花销', '对比', '分析', '合理', '统计', '占比', '哪类', '哪个', '是不是',
      '怎么样', '超支', '剩'
    ];
    return markers.any(t.contains);
  }

  // ── 记账流 ──────────────────────────────────────────────────────────────
  Future<void> _runRecord(String text) async {
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
        hint = 'AI 没连上, 喵先用本地规则记了（单笔）';
      }
    } else {
      results = [NaturalLanguageEntryParser.parse(text)];
      hint = '还没配 AI key，喵先用本地规则记（单笔）';
    }

    final cats = results.map((e) => _matchCat(repo, e)).toList();

    if (!mounted) return;
    // 高置信(每笔>=0.9且金额有效) → 直接入库 + 撤销；否则弹确认卡
    final highConfidence = hint == null &&
        results.length <= 5 &&
        results.every((e) =>
            e.amount != null && e.amount! > Decimal.zero && e.confidence >= 0.9);
    _RecordMsg? autoMsg;
    setState(() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
      if (results.isEmpty) {
        _msgs.add(_InfoMsg('喵没看懂这句，换个说法试试？', error: true));
      } else if (!results
          .any((e) => e.amount != null && e.amount! > Decimal.zero)) {
        // 认出了内容但没金额 → 追问，而不是弹一张存不了的死卡
        _msgs.add(_InfoMsg('喵没认出金额～再说一句金额吧，比如「奶茶 18」'));
      } else {
        if (hint != null) _msgs.add(_InfoMsg(hint));
        final msg = _RecordMsg(entries: results, cats: cats);
        _msgs.add(msg);
        if (highConfidence) autoMsg = msg;
      }
      _busy = false;
    });
    // 高置信：自动保存（卡片随即进入已存/可撤销态）
    if (autoMsg != null) {
      await _save(autoMsg!);
      if (mounted) _snack('喵直接记好了，不对就点卡片上的撤销');
    }
    _scrollToBottom();
  }

  // ── 查账流 ──────────────────────────────────────────────────────────────
  Future<void> _runQuery(String text) async {
    final repo = context.read<AppRepository>();
    final key = repo.deepSeekApiKey;
    String answer;
    if (key == null || key.isEmpty) {
      answer = '查账要先配 AI key 哦～去「我的 → AI 记账设置」填一下，喵就能帮你分析啦';
    } else {
      try {
        answer = await LlmQuery.ask(
          question: text,
          apiKey: key,
          transactionsText: _buildTxnContext(repo),
        );
      } catch (_) {
        answer = '喵没连上 AI，待会儿再问问？';
      }
    }
    if (!mounted) return;
    setState(() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
      _msgs.add(_AnswerMsg(answer));
      _busy = false;
    });
    _scrollToBottom();
  }

  /// 把最近账目整理成给 LLM 的上下文（按日期倒序，最多 80 条）。
  String _buildTxnContext(AppRepository repo) {
    final txns = [...repo.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final sb = StringBuffer();
    sb.writeln('今天是 ${now.year}-${now.month}-${now.day}。');
    sb.writeln('账目数据（格式：日期|收支|分类|金额元|备注）：');
    for (final t in txns.take(80)) {
      final k = t.txKind == TransactionKind.income
          ? '收'
          : (t.txKind == TransactionKind.transfer ? '转' : '支');
      final d =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      sb.writeln(
          '$d|$k|${t.categoryNameZh}|${MoneyFormat.string(t.amount)}|${t.note}');
    }
    return sb.toString();
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
    int savedCount = 0;
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
      savedCount++;
    }
    if (savedCount == 0) {
      _snack('这几笔没认出金额，先补上金额再存～');
      return;
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

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
            // ── 上方展开区：建议 / 对话，点空白处收起 ──
            // 上方：建议(2×2) / 对话，浮在模糊背景上，点空白处收起
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: _msgs.isEmpty
                    ? SingleChildScrollView(
                        reverse: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 16, 10),
                          child: _SuggestionGrid(
                            items: _picked,
                            onTap: (s) => _send(s),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) => _buildMsg(_msgs[i]),
                      ),
              ),
            ),

            // 大白卡：发财猫 + 喵喵助手 + 输入框 + 工具行
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 头部：发财猫 + 喵喵助手 + 关闭
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                      child: Row(
                        children: [
                          const Mascot(mood: MascotMood.celebrate, size: 35),
                          const SizedBox(width: 8),
                          Text(
                            '喵喵助手',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          _CircleBtn(
                            icon: Icons.close,
                            onTap: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // 卡中卡：原输入框（浅底圆角框）包在白卡里
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _ctrl,
                              focusNode: _focus,
                              autofocus: true,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 17),
                              decoration: InputDecoration(
                                hintText: 'Chat with cat',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _CircleBtn(
                                  icon: Icons.add,
                                  onTap: () => showRecordExtrasSheet(context),
                                ),
                                const SizedBox(width: 8),
                                _Pill(
                                  isAi: true,
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onSwitchToManual();
                                  },
                                ),
                                const Spacer(),
                                _CircleBtn(
                                  icon: Icons.arrow_upward,
                                  filled: true,
                                  onTap: (hasText && !_busy)
                                      ? () => _send()
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildMsg(_Msg m) {
    if (m is _UserMsg) return _UserBubble(text: m.text);
    if (m is _ThinkingMsg) return const _ThinkingBubble();
    if (m is _InfoMsg) return _InfoBubble(text: m.text, error: m.error);
    if (m is _AnswerMsg) return _AnswerBubble(text: m.text);
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

class _AnswerMsg extends _Msg {
  final String text;
  _AnswerMsg(this.text);
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

// ── 查账回答气泡（喵助手回答，打字机流式）────────────────────────────────────
class _AnswerBubble extends StatefulWidget {
  final String text;
  const _AnswerBubble({required this.text});

  @override
  State<_AnswerBubble> createState() => _AnswerBubbleState();
}

class _AnswerBubbleState extends State<_AnswerBubble> {
  int _shown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_shown >= widget.text.length) {
        t.cancel();
        return;
      }
      setState(() {
        _shown = (_shown + 2).clamp(0, widget.text.length);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownText = widget.text.substring(0, _shown);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Mascot(mood: MascotMood.report, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: SelectableText(
                shownText,
                style: const TextStyle(fontSize: 15, height: 1.4),
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
          Divider(height: 16, color: scheme.outlineVariant.withValues(alpha: 0.6)),
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

/// 建议 2×2 网格：浮在模糊背景上，半透明白底胶囊，便于阅读。
class _SuggestionGrid extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onTap;

  const _SuggestionGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in items)
          PressableScale(
            onPressed: () => onTap(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              ),
              child: Text(
                s,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 小组件：胶囊 + 圆形按钮
// ─────────────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final bool isAi;
  final VoidCallback onTap;

  const _Pill({required this.isAi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: GlassSurface(
        radius: 17,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isAi ? Icons.auto_awesome : Icons.edit_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(isAi ? 'AI 记账' : '手动记账',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
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
      return PressableScale(
        onPressed: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? scheme.secondary : scheme.onSurface.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 20,
              color:
                  active ? scheme.onSecondary : scheme.onSurface.withValues(alpha: 0.38)),
        ),
      );
    }
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: GlassSurface(
          circle: true,
          child: Center(
            child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
