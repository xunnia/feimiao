import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/ai/chat_intent.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/merchant_category.dart';
import '../../core/ai/smart_tags.dart';
import '../../core/meal_time.dart';
import '../../core/spending_anomaly.dart';
import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/haptics.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/meow_insights.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import 'record_extras_sheet.dart';

/// 打开「来记一笔吧」AI 聊天面板（就地弹出，替代旧的跳全屏方案）。
Future<void> showAiChatPanel(
  BuildContext context, {
  required VoidCallback onSwitchToManual,
  String? initialText,
  bool fullScreen = false,
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
      fullScreen: fullScreen,
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

/// 会话历史（同一次 App 运行内复用：关闭再打开仍能看到过往对话）。
/// 跨重启由 chat_messages 表持久化，按「对话保存时长」设置自动清理超期。
final List<_Msg> _chatHistory = <_Msg>[];

/// 本次 App 运行是否已从数据库恢复过历史（只恢复一次，之后内存复用）。
bool _chatRestored = false;

/// 清空内存中的会话历史（设置页「清空对话」时同步调用，避免本次运行还残留）。
void clearChatHistoryMemory() => _chatHistory.clear();

// ─────────────────────────────────────────────────────────────────────────────
// Claude 风格操作图标：Lucide 线性图标（MIT 开源），细线 + 圆角描边。
// 用 flutter_svg 内嵌渲染，再用 colorFilter 着色；和 Material 图标完全不同的观感。
// ─────────────────────────────────────────────────────────────────────────────
const String _lucideHeader =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';
const String _icCopy =
    '$_lucideHeader<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>'
    '<path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
const String _icRetry =
    '$_lucideHeader<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>'
    '<path d="M3 3v5h5"/></svg>';
const String _icThumbUp =
    '$_lucideHeader<path d="M7 10v12"/>'
    '<path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/></svg>';
const String _icThumbDown =
    '$_lucideHeader<path d="M17 14V2"/>'
    '<path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3 3.88Z"/></svg>';
// 选中态：实心（fill）。
const String _lucideHeaderFill =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000" '
    'stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';
const String _icThumbUpFill =
    '$_lucideHeaderFill<path d="M7 10v12"/>'
    '<path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/></svg>';
const String _icThumbDownFill =
    '$_lucideHeaderFill<path d="M17 14V2"/>'
    '<path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3 3.88Z"/></svg>';

/// 「来记一笔吧」聊天面板：一句话 → AI 解析 → 记账确认卡（可保存/撤销）。
/// 语音用键盘自带听写打到输入框即可，不再内置录音识别。
class AiChatPanel extends StatefulWidget {
  final VoidCallback onSwitchToManual;

  /// 预填到输入框的文字，不自动发送，供校对再发。
  final String? initialText;

  /// 全屏模式（抽屉「喵助手」入口用）：铺满屏幕、方角、无拖拽条，靠关闭按钮退出。
  final bool fullScreen;

  const AiChatPanel({
    super.key,
    required this.onSwitchToManual,
    this.initialText,
    this.fullScreen = false,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = _chatHistory;
  bool _busy = false;

  // 对话态聊天窗高度占比（半屏 0.58 / 全屏 0.94），及拖拽中标记。
  double _heightFrac = 0.58;
  bool _dragging = false;
  // 本次打开是否已经发过消息：未发=建议页；发过=半屏对话窗(可下拉看历史)。
  bool _started = false;

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
    final nowHour = DateTime.now().hour;
    final counts = <String, int>{};
    final amounts = <String, List<Decimal>>{};
    for (final t in repo.transactions) {
      if (t.txKind != TransactionKind.expense) continue;
      final name = t.categoryNameZh;
      if (name.isEmpty || name == '未分类') continue;
      // 时段加权：在当前时段(±3 小时，含跨午夜)记过的分类权重更高。
      final dh = (t.date.hour - nowHour).abs();
      final w = (dh <= 3 || dh >= 21) ? 2 : 1;
      counts[name] = (counts[name] ?? 0) + w;
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
    _focus.addListener(_onFocusChanged);
    // 复用会话历史：清掉残留的"思考中"，滚到底显示最新。
    _msgs.removeWhere((m) => m is _ThinkingMsg);
    _busy = false;
    // 跨重启恢复：本次运行第一次打开时，从数据库读回历史对话。
    if (!_chatRestored) {
      _chatRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreHistory());
    }
    if (_msgs.isNotEmpty) _scrollToBottom();
  }

  /// 从数据库恢复历史对话（超期的已在 loadChatMessages 内清理）。
  Future<void> _restoreHistory() async {
    if (!mounted) return;
    final rows = await context.read<AppRepository>().loadChatMessages();
    if (!mounted || rows.isEmpty) return;
    final restored = <_Msg>[];
    for (final r in rows) {
      final role = (r['role'] as String?) ?? 'info';
      final text = (r['text'] as String?) ?? '';
      final question = (r['question'] as String?) ?? '';
      if (role == 'user') {
        restored.add(_UserMsg(text));
      } else if (role == 'answer') {
        restored.add(_AnswerMsg(text, question: question, shown: true));
      } else if (role == 'info_err') {
        restored.add(_InfoMsg(text, error: true));
      } else {
        restored.add(_InfoMsg(text));
      }
    }
    setState(() => _chatHistory.insertAll(0, restored));
    _scrollToBottom();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
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

    Haptics.light();
    final repo = context.read<AppRepository>();
    _ctrl.clear();
    _focus.unfocus();
    setState(() {
      _started = true;
      _msgs.add(_UserMsg(text));
      _msgs.add(_ThinkingMsg());
      _busy = true;
    });
    await repo.addChatMessage(role: 'user', text: text);
    _scrollToBottom();

    final key = repo.deepSeekApiKey;
    // 有 key：让大模型在同一次调用里判「记账/查账」并解析（意图判断最准，
    // 不再靠脆弱的关键词，"坐公交花了一块"这类不会再被误当查账）。
    if (key != null && key.isNotEmpty) {
      try {
        final res = await LlmEntryParser.parseWithLLM(
          text: text,
          apiKey: key,
          expenseCats: CategorySeed.expenses,
          incomeCats: CategorySeed.incomes,
        );
        if (res.intent == LlmIntent.query) {
          await _runQuery(text);
        } else {
          await _applyRecord(res.entries);
        }
        return;
      } catch (_) {
        // 调用失败 → 落到下面的离线兜底
      }
    }
    // 无 key / 调用失败：关键词判意图（ChatIntent）+ 本地规则兜底。
    if (_looksLikeQuery(text)) {
      await _runQuery(text);
    } else {
      final hint = (key == null || key.isEmpty)
          ? '还没配 AI key，喵先用本地规则记（单笔）'
          : 'AI 没连上, 喵先用本地规则记了（单笔）';
      await _applyRecord([NaturalLanguageEntryParser.parse(text)], hint: hint);
    }
  }

  /// 意图判断：是「记账」还是「查账」。逻辑见 [ChatIntent]（纯逻辑，有单测）。
  /// 记账优先——"花了/吃/打车 + 金额(含口语一块)"都算记账，只有真在问数据才查账。
  bool _looksLikeQuery(String t) => ChatIntent.isQuery(
        t,
        hasArabicAmount: NaturalLanguageEntryParser.extractAmount(t) != null,
      );

  // ── 记账流：给定解析结果，匹配分类 → 高置信自动入库/否则确认卡 ──────────────
  Future<void> _applyRecord(List<ParsedEntry> results, {String? hint}) async {
    final repo = context.read<AppRepository>();
    final cats = results.map((e) => _matchCat(repo, e)).toList();

    if (!mounted) return;
    // 高置信(每笔>=0.9且金额有效) → 直接入库 + 撤销；否则弹确认卡
    final highConfidence = hint == null &&
        results.length <= 5 &&
        results.every((e) =>
            e.amount != null && e.amount! > Decimal.zero && e.confidence >= 0.9);
    _RecordMsg? autoMsg;
    String persistText = '';
    String persistRole = 'info';
    setState(() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
      if (results.isEmpty) {
        _msgs.add(_InfoMsg('喵没看懂这句，换个说法试试？', error: true));
        persistText = '喵没看懂这句，换个说法试试？';
        persistRole = 'info_err';
      } else if (!results
          .any((e) => e.amount != null && e.amount! > Decimal.zero)) {
        // 认出了内容但没金额 → 追问，而不是弹一张存不了的死卡
        _msgs.add(_InfoMsg('喵没认出金额～再说一句金额吧，比如「奶茶 18」'));
        persistText = '喵没认出金额～再说一句金额吧，比如「奶茶 18」';
      } else {
        if (hint != null) _msgs.add(_InfoMsg(hint));
        final msg = _RecordMsg(entries: results, cats: cats);
        _msgs.add(msg);
        if (highConfidence) autoMsg = msg;
        final n = results.where((e) => e.amount != null).length;
        persistText = hint != null ? '$hint · 已记 $n 笔' : '已记 $n 笔';
      }
      _busy = false;
    });
    if (persistText.isNotEmpty) {
      await repo.addChatMessage(role: persistRole, text: persistText);
    }
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
    // 保留 markdown 原文，交给 _AnswerBubble 轻量渲染（**加粗** / 列表 / 标题）。
    if (!mounted) return;
    setState(() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
      _msgs.add(_AnswerMsg(answer, question: text));
      _busy = false;
    });
    await repo.addChatMessage(role: 'answer', text: answer, question: text);
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
    // 分类优先级:用户纠正记忆 > 商户/关键词词典 > 大模型猜测 > 兜底。
    // 记忆=最懂你;词典=高频商户确定性命中(瑞幸→饮料、滴滴→打车),比模型稳。
    final learned = repo.recallCategoryKey(e.note, e.kind);
    final dict = MerchantCategory.classify(e.note, e.kind);
    // 笼统餐饮按时段细化到早/午/晚餐（更聪明）。
    final wantKey =
        MealTime.refine(learned ?? dict ?? e.categoryKey, e.date, e.note);
    if (wantKey != null) {
      cat = repo.categories
          .where((c) => c.kind == e.kind && c.key == wantKey)
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
    // 入库前先算「异常提醒」（用当前历史，尚不含本次）：只提醒第一笔明显偏高的支出。
    String? anomalyNote;
    for (int i = 0; i < msg.entries.length; i++) {
      final e = msg.entries[i];
      final cat = msg.cats[i];
      if (e.amount == null ||
          e.amount! <= Decimal.zero ||
          e.kind != TransactionKind.expense ||
          cat == null) continue;
      final past = <Decimal>[];
      for (final t in repo.transactions) {
        if (t.txKind == TransactionKind.expense &&
            t.categoryNameZh == cat.nameZh &&
            t.amount > Decimal.zero) {
          past.add(t.amount);
        }
      }
      anomalyNote = SpendingAnomaly.note(past, e.amount!, cat.nameZh);
      if (anomalyNote != null) break;
    }

    // 按条目逐笔入库,记下每笔的 id(无金额的占位 null),用于之后按条目改分类。
    final ids = <int?>[];
    int savedCount = 0;
    for (int i = 0; i < msg.entries.length; i++) {
      final e = msg.entries[i];
      final amt = e.amount;
      if (amt == null || amt <= Decimal.zero) {
        ids.add(null);
        continue;
      }
      final id = await repo.addTransaction(
        kind: e.kind,
        amount: amt,
        categoryId: msg.cats[i]?.id,
        accountId: accountId,
        note: e.note,
        date: e.date,
        reimbursable: SmartTags.isReimbursable(e.note), // 出差/报销自动标待报销
      );
      ids.add(id);
      savedCount++;
    }
    if (savedCount == 0) {
      _snack('这几笔没认出金额，先补上金额再存～');
      return;
    }
    if (!mounted) return;
    // 记完反馈:取首笔的分类名,让猫说一句数据感言。
    final mainCat = msg.cats.firstWhere((c) => c != null, orElse: () => null);
    final feedback = MeowInsights.recordFeedback(repo, mainCat?.nameZh ?? '');
    Haptics.of(Haptic.success);
    setState(() {
      msg.saved = true;
      msg.txnIds = ids;
      msg.savedIds = ids.whereType<int>().toList();
      msg.savedFeedback = feedback;
      if (anomalyNote != null) _msgs.add(_InfoMsg(anomalyNote!));
    });
    if (anomalyNote != null) {
      await repo.addChatMessage(role: 'info', text: anomalyNote);
    }
  }

  /// 一键改分类：把第 [i] 笔改成 [newCat]，并记住这次纠正(下次自动用)；
  /// 若已入库则同步改库。
  Future<void> _pickCategory(_RecordMsg msg, int i, CategoryEntity newCat) async {
    final repo = context.read<AppRepository>();
    Haptics.light();
    // 学习:把"备注短语 → 分类"记下,下次同类自动命中
    final note = msg.entries[i].note;
    if (note.trim().isNotEmpty) {
      await repo.learnCategory(
        phrase: note,
        kind: newCat.kind,
        categoryKey: newCat.key,
      );
    }
    // 已入库 → 改库
    if (msg.saved && i < msg.txnIds.length && msg.txnIds[i] != null) {
      await repo.setTransactionCategory(msg.txnIds[i]!, newCat.id);
    }
    if (!mounted) return;
    setState(() => msg.cats[i] = newCat);
  }

  /// 给第 i 笔算几个候选分类(最常见的纠错):
  /// 子类→同父兄弟;大类→它的子类;无子类的(如收入)→同级其它大类。
  List<CategoryEntity> _catCandidates(AppRepository repo, _RecordMsg msg, int i) {
    final cur = msg.cats[i];
    final kind = msg.entries[i].kind;
    if (cur == null) return const [];
    final pid = cur.parentId;
    Iterable<CategoryEntity> sibs;
    if (pid != null) {
      sibs = repo.categories
          .where((c) => c.kind == kind && c.parentId == pid && c.id != cur.id);
    } else {
      final children =
          repo.categories.where((c) => c.kind == kind && c.parentId == cur.id);
      sibs = children.isNotEmpty
          ? children
          : repo.categories.where(
              (c) => c.kind == kind && c.parentId == null && c.id != cur.id);
    }
    return sibs.take(6).toList();
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // 全屏（抽屉「喵助手」入口）：一条独立的整屏不透明页，恒定铺满，状态栏也盖住。
    if (widget.fullScreen) return _fullScreenPage(context, bottomInset);
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: _started
              ? _chatMode(context)
              : _emptyMode(context),
        ),
      ),
    );
  }

  // 全屏聊天页：不透明 surface 铺满整屏（含状态栏），SafeArea 垫内容。
  // 顶部头部、中间内容（建议 or 对话）、底部输入；空态/对话态都恒定全屏。
  Widget _fullScreenPage(BuildContext context, double bottomInset) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              _header(context),
              Expanded(
                // 有历史就直接显示对话(滚到最新)；完全没记录才显示建议空状态。
                child: _msgs.isEmpty
                    ? SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _GreetingLine(),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.only(left: 0),
                                child: _SuggestionGrid(
                                    items: _picked, onTap: _fillInput),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) =>
                            _buildMsg(_msgs[i], isLast: i == _msgs.length - 1),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _inputBox(context, autofocus: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 点建议：把文字填进输入框（不直接发），让用户改了再发。
  void _fillInput(String s) {
    setState(() {
      _ctrl.text = s;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  // 空态：建议浮在模糊背景上 + 底部白卡输入。
  Widget _emptyMode(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: SingleChildScrollView(
              reverse: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 16, 10),
                child: _SuggestionGrid(items: _picked, onTap: _fillInput),
              ),
            ),
          ),
        ),
        _header(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _inputBox(context, autofocus: true),
        ),
      ],
    );
  }

  // 对话态：半屏/全屏可拖拽的白色聊天窗。
  Widget _chatMode(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (ctx, c) {
        final availH = c.maxHeight;
        // 聚焦(键盘弹起)时铺满键盘上方区域，避免溢出；否则用半/全屏档位。
        final focused = _focus.hasFocus;
        final frac = (focused ? 1.0 : _heightFrac).clamp(0.35, 1.0);
        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedContainer(
              duration: (_dragging || focused)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: availH * frac,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 24,
                      offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                children: [
                  _dragHandle(availH),
                  _header(context),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) =>
                          _buildMsg(_msgs[i], isLast: i == _msgs.length - 1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _inputBox(context, autofocus: false),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // 顶部横条：跟手缩放 + 松手吸附半/全屏 + 点击切换。
  Widget _dragHandle(double availH) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragging = true,
      onVerticalDragUpdate: (d) {
        setState(() {
          _heightFrac = (_heightFrac - d.delta.dy / availH).clamp(0.35, 0.96);
        });
      },
      onVerticalDragEnd: (_) {
        setState(() {
          _dragging = false;
          if (_heightFrac < 0.45) {
            Navigator.pop(context);
            return;
          }
          _heightFrac = _heightFrac < 0.74 ? 0.58 : 0.94;
        });
      },
      onTap: () =>
          setState(() => _heightFrac = _heightFrac > 0.74 ? 0.58 : 0.94),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // 头部：发财猫 + 喵喵助手 + 关闭。
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 4),
      child: Row(
        children: [
          const Mascot(mood: MascotMood.celebrate, size: 35, animate: true),
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
    );
  }

  // 卡中卡输入框：浅底圆角框 + 工具行。
  // 输入框：与首页那条完全统一（玻璃圆角卡 + 细黑边）。
  Widget _inputBox(BuildContext context, {required bool autofocus}) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 2)),
        ],
      ),
      child: GlassSurface(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: autofocus,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w300),
            decoration: InputDecoration(
              hintText: 'Chat with cat',
              hintStyle: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
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
          const SizedBox(height: 4),
          Row(
            children: [
              _CircleBtn(
                icon: Icons.add,
                onTap: () => showRecordExtrasSheet(context),
              ),
              const SizedBox(width: 6),
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
                onTap: (hasText && !_busy) ? () => _send() : null,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _regenerate(_AnswerMsg m) {
    if (_busy || m.question.isEmpty) return;
    setState(() {
      _msgs.remove(m);
      _msgs.add(_ThinkingMsg());
      _busy = true;
    });
    _scrollToBottom();
    _runQuery(m.question);
  }

  Widget _buildMsg(_Msg m, {bool isLast = false}) {
    if (m is _UserMsg) return _UserBubble(text: m.text);
    if (m is _ThinkingMsg) return const _ThinkingBubble();
    if (m is _InfoMsg) return _InfoBubble(text: m.text, error: m.error);
    if (m is _AnswerMsg) {
      return _AnswerBubble(
        text: m.text,
        animate: !m.shown,
        onShown: () => m.shown = true,
        onRegenerate: m.question.isEmpty ? null : () => _regenerate(m),
        // 猫只出现在最后一条回复下（对齐 Claude），历史回复不重复放猫。
        showMascot: isLast,
      );
    }
    if (m is _RecordMsg) {
      final repo = context.read<AppRepository>();
      return _RecordBubble(
        msg: m,
        onSave: () => _save(m),
        onUndo: () => _undo(m),
        candidatesFor: (i) => _catCandidates(repo, m, i),
        onPickCat: (i, cat) => _pickCategory(m, i, cat),
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
  final String question;
  bool shown;
  _AnswerMsg(this.text, {this.question = '', this.shown = false});
}

class _RecordMsg extends _Msg {
  final List<ParsedEntry> entries;
  final List<CategoryEntity?> cats;
  bool saved;
  List<int> savedIds;
  List<int?> txnIds; // 已入库时,每个条目对应的记录 id(无金额为 null);供按条目改分类
  String savedFeedback; // 记完后猫给的一句数据反馈
  _RecordMsg({
    required this.entries,
    required this.cats,
    this.saved = false,
    this.savedIds = const [],
    this.txnIds = const [],
    this.savedFeedback = '',
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
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w300)),
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
          const Mascot(mood: MascotMood.thinking, size: 28, animate: true),
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
  final bool animate;
  final VoidCallback? onShown;
  final VoidCallback? onRegenerate;

  /// 是否在操作图标下放猫：只有列表最后一条回复为 true（对齐 Claude）。
  final bool showMascot;

  const _AnswerBubble({
    required this.text,
    this.animate = true,
    this.onShown,
    this.onRegenerate,
    this.showMascot = false,
  });

  @override
  State<_AnswerBubble> createState() => _AnswerBubbleState();
}

class _AnswerBubbleState extends State<_AnswerBubble> {
  int _shown = 0;
  bool _liked = false;
  bool _disliked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _shown = widget.text.length;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_shown >= widget.text.length) {
        t.cancel();
        widget.onShown?.call();
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

  // 按回答语气挑一只猫。
  MascotMood _moodFor(String t) {
    if (t.contains('超支') || t.contains('超了') || t.contains('超出')) {
      return MascotMood.overspend;
    }
    if (t.contains('管住') || t.contains('继续保持') || t.contains('省钱')) {
      return MascotMood.celebrate;
    }
    return MascotMood.report;
  }

  // Claude 风格操作图标：Lucide 线性 SVG + 着色（选中态用主色）。
  Widget _action(String svg, VoidCallback onTap, {bool active = false}) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: SvgPicture.string(
          svg,
          width: 17,
          height: 17,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }

  // 轻量 markdown → 富文本：处理 **加粗**、行首 - / * 列表、# 标题；保留可选中。
  List<InlineSpan> _mdSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (int li = 0; li < lines.length; li++) {
      var line = lines[li].replaceAll('__', '');
      var headerBold = false;
      final h = RegExp(r'^#{1,6}\s*').firstMatch(line);
      if (h != null) {
        line = line.substring(h.end);
        headerBold = true;
      }
      final b = RegExp(r'^\s*[-*]\s+').firstMatch(line);
      if (b != null) line = '•  ${line.substring(b.end)}';
      final parts = line.split('**');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isEmpty) continue;
        final bold = headerBold || i.isOdd;
        spans.add(TextSpan(
          text: parts[i],
          style: bold ? base.copyWith(fontWeight: FontWeight.w600) : null,
        ));
      }
      if (li != lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownText = widget.text.substring(0, _shown);
    final done = _shown >= widget.text.length;
    // 对齐 Claude：正文 w400、加粗 w600，反差一档，别太夸张。
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 回答正文：全宽、无气泡（对标 Claude），轻量 markdown 渲染。
          SelectableText.rich(
            TextSpan(style: baseStyle, children: _mdSpans(shownText, baseStyle)),
          ),
          if (done) ...[
            const SizedBox(height: 4),
            // 操作图标行（对标 Claude：裸图标、细线、浅灰）。
            Row(
              children: [
                _action(_icCopy, () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                }),
                _action(
                  _liked ? _icThumbUpFill : _icThumbUp,
                  () => setState(() {
                    _liked = !_liked;
                    if (_liked) _disliked = false;
                  }),
                  active: _liked,
                ),
                _action(
                  _disliked ? _icThumbDownFill : _icThumbDown,
                  () => setState(() {
                    _disliked = !_disliked;
                    if (_disliked) _liked = false;
                  }),
                  active: _disliked,
                ),
                if (widget.onRegenerate != null)
                  _action(_icRetry, widget.onRegenerate!),
              ],
            ),
            if (widget.showMascot) ...[
              const SizedBox(height: 2),
              // 猫在操作图标下方、左侧；只跟着最后一条回复走。
              Mascot(mood: _moodFor(widget.text), size: 52, animate: true),
            ],
          ],
        ],
      ),
    );
  }
}

// ── 喵助手打开时主动说的一句洞察 ──────────────────────────────────────────────
class _GreetingLine extends StatelessWidget {
  const _GreetingLine();

  @override
  Widget build(BuildContext context) {
    final g = MeowInsights.greeting(context.read<AppRepository>());
    if (g == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text(
      g,
      style: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
    );
  }
}

// ── 记账确认卡 ───────────────────────────────────────────────────────────────
class _RecordBubble extends StatelessWidget {
  final _RecordMsg msg;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final List<CategoryEntity> Function(int index) candidatesFor;
  final void Function(int index, CategoryEntity cat) onPickCat;

  const _RecordBubble({
    required this.msg,
    required this.onSave,
    required this.onUndo,
    required this.candidatesFor,
    required this.onPickCat,
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
                  size: 28,
                  animate: true),
              const SizedBox(width: 8),
              Text(
                msg.saved
                    ? (msg.savedFeedback.isNotEmpty
                        ? msg.savedFeedback
                        : '记好啦！')
                    : (n > 1 ? '帮你拆成 $n 笔：' : '看看对不对：'),
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card(scheme),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < msg.entries.length; i++)
                  _EntryRow(
                    entry: msg.entries[i],
                    cat: msg.cats[i],
                    showDivider: i > 0,
                    candidates: candidatesFor(i),
                    onPickCat: (c) => onPickCat(i, c),
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
                              fontWeight: FontWeight.w500)),
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
  final List<CategoryEntity> candidates;
  final ValueChanged<CategoryEntity> onPickCat;

  const _EntryRow({
    required this.entry,
    required this.cat,
    required this.showDivider,
    this.candidates = const [],
    required this.onPickCat,
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
                fontWeight: FontWeight.w600,
                fontFamily: 'Nunito',
                color: entry.amount == null
                    ? scheme.error
                    : (isIncome ? scheme.secondary : scheme.onSurface),
              ),
            ),
          ],
        ),
        // 一键改分类:同大类兄弟子类候选,点一下即改并被学走(下次自动用)。
        if (candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 5),
                    child: Text('改成',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
                  for (final c in candidates)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _CatChip(cat: c, onTap: () => onPickCat(c)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 改分类小芯片：emoji + 名称，点一下切到该分类。
class _CatChip extends StatelessWidget {
  final CategoryEntity cat;
  final VoidCallback onTap;
  const _CatChip({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Text(
          '${CategorySeed.emojiOf(cat.key)} ${cat.nameZh}',
          style: TextStyle(fontSize: 12, color: scheme.onSurface),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 空态：猜你想问气泡
// ─────────────────────────────────────────────────────────────────────────────

/// 建议 2×2 网格：浮在模糊背景上，与底部输入框同款玻璃透明底胶囊。
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
            child: GlassSurface(
              radius: 16,
              blur: 0, // 面板背景已经模糊过，无需叠加
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
        radius: 15,
        blur: 0, // 面板背景已经模糊过，无需叠加
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: SizedBox(
          height: 31,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isAi ? Icons.auto_awesome : Icons.edit_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(isAi ? 'AI 记账' : '手动记账',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? scheme.secondary : scheme.onSurface.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 18,
              color:
                  active ? scheme.onSecondary : scheme.onSurface.withValues(alpha: 0.38)),
        ),
      );
    }
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: GlassSurface(
          circle: true,
          blur: 0, // 面板背景已经模糊过，无需叠加
          child: Center(
            child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
