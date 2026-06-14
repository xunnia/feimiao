import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../quick_add/ai_quick_entry_view.dart';

/// AI 聚焦输入卡片（贴键盘上方弹出）。
///
/// 用 showModalBottomSheet(isScrollControlled: true) 弹出。
/// 内容：
///   顶行："手动记账"小胶囊（切手动大卡片） + 圆形 X 关闭
///   输入框：自动聚焦弹键盘，占位"记一记"
///   输入框右侧：话筒（语音听写） + +（扩展：截图/导入/导出，即将到来）
///   底部：发送/解析 → 跳转 AiQuickEntryView(initialText)
///
/// [startVoiceImmediately] 为 true 时，打开后立即触发语音听写（话筒按钮触发路径）。
class AiFocusedInputSheet extends StatefulWidget {
  final bool speechAvailable;
  final bool startVoiceImmediately;

  /// 点击"手动记账"胶囊的回调（由调用方切换到 ManualAddSheet）。
  final VoidCallback onSwitchToManual;

  const AiFocusedInputSheet({
    super.key,
    required this.speechAvailable,
    required this.onSwitchToManual,
    this.startVoiceImmediately = false,
  });

  @override
  State<AiFocusedInputSheet> createState() => _AiFocusedInputSheetState();
}

class _AiFocusedInputSheetState extends State<AiFocusedInputSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    // 如果调用方已确认可用，直接 initialize 以拿到本地 SpeechToText 实例。
    final available = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (status) {
        if (status == stt.SpeechToText.doneStatus ||
            status == stt.SpeechToText.notListeningStatus) {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    if (mounted) {
      setState(() => _speechReady = available);
      if (available && widget.startVoiceImmediately) {
        // 延一帧，等弹层动画完成再开始录音
        WidgetsBinding.instance.addPostFrameCallback((_) => _startListen());
      }
    }
  }

  Future<void> _startListen() async {
    if (!_speechReady || _listening) return;
    final started = await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _textCtrl.text = result.recognizedWords;
            _textCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _textCtrl.text.length),
            );
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'zh_CN',
      cancelOnError: true,
      partialResults: true,
    );
    if (!started && mounted) {
      _showSnack('无法启动语音识别，请检查麦克风权限');
      return;
    }
    if (mounted) setState(() => _listening = true);
  }

  Future<void> _toggleListen() async {
    if (!_speechReady) {
      _showSnack('该设备不支持语音识别');
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    } else {
      await _startListen();
    }
  }

  // ── 解析：关闭 sheet 并跳转全页 AI 记账 ──────────────────────────────────

  void _doParse() {
    final text = _textCtrl.text.trim();
    Navigator.pop(context);
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiQuickEntryView(initialText: text.isEmpty ? null : text),
      ),
    );
  }

  void _showExtras() {
    _showSnack('即将到来');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasText = _textCtrl.text.trim().isNotEmpty;

    return Padding(
      // 卡片跟着键盘上移
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 拖动条 ──
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // ── 顶行："手动记账"胶囊 + X 关闭 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
              child: Row(
                children: [
                  // 手动记账胶囊
                  GestureDetector(
                    onTap: widget.onSwitchToManual,
                    child: Container(
                      height: 34,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grid_view,
                              size: 14,
                              color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '手动记账',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // X 关闭
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // ── 输入框 + 工具图标 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 输入框（Expanded）
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (hasText) _doParse();
                      },
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        hintText: '记一记',
                        hintStyle: TextStyle(
                          fontSize: 17,
                          color:
                              scheme.onSurfaceVariant.withOpacity(0.55),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 话筒
                  _SmallIconButton(
                    icon: _listening ? Icons.mic : Icons.mic_none,
                    tint: _listening ? scheme.error : scheme.onSurfaceVariant,
                    onTap: _toggleListen,
                  ),
                  const SizedBox(width: 4),

                  // + 扩展
                  _SmallIconButton(
                    icon: Icons.add_circle_outline,
                    tint: scheme.onSurfaceVariant,
                    onTap: _showExtras,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── 底部发送按钮 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                onPressed: hasText ? _doParse : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_upward, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      '解析记账',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 小图标按钮（输入框右侧）
// ─────────────────────────────────────────────────────────────────────────────

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  const _SmallIconButton({
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 22, color: tint),
      ),
    );
  }
}
