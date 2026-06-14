import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../quick_add/ai_quick_entry_view.dart';
import '../quick_add/quick_add_view.dart';

/// 类 Claude 输入框：一整块圆角软卡片。
///
/// 卡片内：
///   上：占位"记一记"的文本行
///   下：[+]  [手动/AI 模式胶囊]  ……  [话筒]  [发送]
///
/// 手动模式：点输入框或发送 → QuickAddView（键盘）
/// AI 模式：点发送 → AiQuickEntryView(initialText)，自动解析
/// 话筒：speech_to_text 中文听写，结果填进输入框
class RecordInputBar extends StatefulWidget {
  const RecordInputBar({super.key});

  @override
  State<RecordInputBar> createState() => _RecordInputBarState();
}

class _RecordInputBarState extends State<RecordInputBar> {
  final TextEditingController _textCtrl = TextEditingController();
  bool _isAiMode = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
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
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListen() async {
    if (!_speechAvailable) {
      _showSnack('该设备不支持语音识别');
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
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

  void _handleSend() {
    final text = _textCtrl.text.trim();
    if (_isAiMode) {
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              AiQuickEntryView(initialText: text.isEmpty ? null : text),
        ),
      );
    } else {
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const QuickAddView()),
      );
    }
    _textCtrl.clear();
  }

  void _handleTapTextField() {
    if (!_isAiMode) _handleSend();
  }

  void _showExtrasSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('更多功能',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            _ExtrasItem(
              icon: Icons.image_outlined,
              label: '支付截图识别',
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('即将到来');
              },
            ),
            _ExtrasItem(
              icon: Icons.upload_file_outlined,
              label: '导入账单',
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('即将到来');
              },
            ),
            _ExtrasItem(
              icon: Icons.download_outlined,
              label: '导出账单',
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('即将到来');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        // 一整块圆角软卡片
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scheme.outlineVariant.withOpacity(0.6),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 占位 / 输入文字（无边框，融入卡片）──
              GestureDetector(
                onTap: _isAiMode ? null : _handleTapTextField,
                child: AbsorbPointer(
                  absorbing: !_isAiMode,
                  child: TextField(
                    controller: _textCtrl,
                    enabled: _isAiMode,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _handleSend(),
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 17),
                    decoration: InputDecoration(
                      hintText: '记一记',
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: scheme.onSurfaceVariant.withOpacity(0.6),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── 工具行 ──
              Row(
                children: [
                  _CircleButton(
                    icon: Icons.add,
                    onTap: _showExtrasSheet,
                  ),
                  const SizedBox(width: 8),
                  _ModePill(
                    isAi: _isAiMode,
                    onTap: () => setState(() => _isAiMode = !_isAiMode),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: _listening ? Icons.mic : Icons.mic_none,
                    tint: _listening ? scheme.error : null,
                    onTap: _toggleListen,
                  ),
                  const SizedBox(width: 8),
                  _CircleButton(
                    icon: Icons.arrow_upward,
                    filled: true,
                    onTap: _handleSend,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 模式胶囊（单个胶囊，显示当前模式，点击切换）—— 对标参考图里的 Opus pill
// ---------------------------------------------------------------------------

class _ModePill extends StatelessWidget {
  final bool isAi;
  final VoidCallback onTap;

  const _ModePill({required this.isAi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isAi ? 'AI 记账' : '手动记账',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 圆形按钮（+ / 话筒 / 发送）
// ---------------------------------------------------------------------------

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color? tint;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = filled ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = filled ? scheme.onPrimary : (tint ?? scheme.onSurfaceVariant);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: fg),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 扩展菜单项
// ---------------------------------------------------------------------------

class _ExtrasItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExtrasItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '即将到来',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      onTap: onTap,
    );
  }
}
