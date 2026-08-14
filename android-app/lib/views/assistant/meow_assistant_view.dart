import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';

import '../../core/ai/llm_query.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/glass_input.dart';
import '../../widgets/mascot.dart';
import '../home/record_extras_sheet.dart';
import '../settings/ai_privacy_consent.dart';

/// 喵助手页：进入自动生成本月消费分析报告，可继续对话追问。
/// 复用 DeepSeek（LlmQuery）+ 当前账本的账目上下文。
class MeowAssistantView extends StatefulWidget {
  const MeowAssistantView({super.key});

  @override
  State<MeowAssistantView> createState() => _MeowAssistantViewState();
}

class _Msg {
  final bool user;
  final String text;
  _Msg(this.user, this.text);
}

class _MeowAssistantViewState extends State<MeowAssistantView> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoReport());
  }

  @override
  void dispose() {
    _ctrl.dispose();
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

  Future<void> _autoReport() =>
      _ask('帮我分析下本月的消费情况，挑重点说、简短点，再给一两条省钱小建议', auto: true);

  Future<void> _ask(String question, {bool auto = false}) async {
    final repo = context.read<AppRepository>();
    final aiConfig = repo.aiProviderConfigFor(AiTaskType.chatQuery);
    if (!aiConfig.hasKey) {
      setState(() => _msgs
          .add(_Msg(false, '喵还没连上 AI～去「我的 → AI 记账设置」填个 API Key，我就能帮你分析账单啦。')));
      return;
    }
    final consented = await ensureAiPrivacyConsent(context);
    if (!consented) {
      setState(() => _msgs.add(_Msg(false, '未同意 AI 隐私说明，喵不会把账本内容发出去。')));
      return;
    }
    setState(() {
      if (!auto) _msgs.add(_Msg(true, question));
      _busy = true;
    });
    _scrollToBottom();

    String answer;
    try {
      answer = await LlmQuery.ask(
        question: question,
        config: aiConfig,
        transactionsText: _txnContext(repo),
      );
    } catch (_) {
      answer = '喵没连上 AI，待会儿再试试？';
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(false, answer));
      _busy = false;
    });
    _scrollToBottom();
  }

  String _txnContext(AppRepository repo) {
    final txns = repo.visibleTransactions.where((t) => !t.excluded).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final thisStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final lastStart = DateTime(now.year, now.month - 1, 1);

    ({int count, Decimal expense, Decimal income}) summary(
        DateTime start, DateTime end) {
      var expense = Decimal.zero;
      var income = Decimal.zero;
      var count = 0;
      for (final t in txns) {
        if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
        count++;
        if (t.txKind == TransactionKind.expense) {
          final net = repo.netAmountOf(t);
          if (net > Decimal.zero) expense += net;
        } else if (t.txKind == TransactionKind.income) {
          income += t.amount;
        }
      }
      return (count: count, expense: expense, income: income);
    }

    final thisMonth = summary(thisStart, nextMonth);
    final lastMonth = summary(lastStart, thisStart);
    final sb = StringBuffer();
    sb.writeln(
        '今天是 ${now.year}-${now.month}-${now.day}。当前账本：${repo.currentBook?.name ?? '总账本'}。');
    sb.writeln('【准确月度汇总】这些数字由本地全量账本计算，优先使用：');
    sb.writeln(
        '本月：支出 ${MoneyFormat.string(thisMonth.expense)}，收入 ${MoneyFormat.string(thisMonth.income)}，${thisMonth.count} 笔');
    sb.writeln(
        '上月：支出 ${MoneyFormat.string(lastMonth.expense)}，收入 ${MoneyFormat.string(lastMonth.income)}，${lastMonth.count} 笔');
    sb.writeln('账目数据（金额均为退款后净额；格式：日期|收支|分类|金额元|备注）：');
    for (final t in txns.take(160)) {
      final k = t.txKind == TransactionKind.income
          ? '收'
          : (t.txKind == TransactionKind.transfer ? '转' : '支');
      final d =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      final amount =
          t.txKind == TransactionKind.expense ? repo.netAmountOf(t) : t.amount;
      sb.writeln(
          '$d|$k|${t.categoryNameZh}|${MoneyFormat.string(amount)}|${t.note}');
    }
    return sb.toString();
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _busy) return;
    _ctrl.clear();
    _ask(t);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sendEnabled = _ctrl.text.trim().isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('喵助手'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _msgs.length + (_busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= _msgs.length) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        const Mascot(mood: MascotMood.thinking, size: 30),
                        const SizedBox(width: 8),
                        Text('喵在看你的账本…',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                }
                final m = _msgs[i];
                return m.user
                    ? _userBubble(m.text, scheme)
                    : _catBubble(m.text, scheme);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: AppGlassInputShell(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AppCircleButton(
                      icon: Icons.add,
                      iconSize: 20,
                      onPressed: () => showRecordExtrasSheet(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onChanged: (_) => setState(() {}),
                        cursorColor: scheme.primary,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                        ),
                        decoration: InputDecoration(
                          hintText: '记一记',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppGlassInputIconButton(
                      icon: Icons.arrow_upward,
                      onPressed: sendEnabled ? _send : null,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text, ColorScheme scheme) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text, style: const TextStyle(fontSize: 15)),
        ),
      );

  Widget _catBubble(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(bottom: 14, right: 32),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SelectableText(
                  text,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      );
}
