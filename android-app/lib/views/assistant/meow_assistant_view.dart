import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/llm_query.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../widgets/mascot.dart';

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
    final key = repo.deepSeekApiKey;
    if (key == null || key.isEmpty) {
      setState(() => _msgs.add(_Msg(false,
          '喵还没连上 AI～去「我的 → AI 记账设置」填个 DeepSeek key，我就能帮你分析账单啦。')));
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
        apiKey: key,
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
    final txns = [...repo.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final sb = StringBuffer();
    sb.writeln(
        '今天是 ${now.year}-${now.month}-${now.day}。当前账本：${repo.currentBook?.name ?? '总账本'}。');
    sb.writeln('账目数据（日期|收支|分类|金额元|备注）：');
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
      appBar: AppBar(title: const Text('喵助手')),
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
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '问问喵助手…',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: sendEnabled ? _send : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: sendEnabled
                            ? scheme.secondary
                            : scheme.onSurface.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_upward,
                        size: 20,
                        color: sendEnabled
                            ? scheme.onSecondary
                            : scheme.onSurface.withOpacity(0.38),
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
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
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
