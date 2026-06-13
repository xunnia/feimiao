import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../quick_add/ai_quick_entry_view.dart';
import '../quick_add/quick_add_view.dart';

/// Claude 风格底部输入栏。
///
/// 布局（两行）：
///   上：文本输入框（占位"记一记"）
///   下：[+扩展] ... [手动/AI 胶囊] ... [话筒] [发送]
///
/// 手动模式：点输入框或发送 → Navigator.push QuickAddView
/// AI 模式：点发送 → Navigator.push AiQuickEntryView(initialText: text)
///           若文本为空，也直接跳转让用户在那里输入
/// 话筒：speech_to_text 中文听写，识别结果填入输入框
class RecordInputBar extends StatefulWidget {
  const RecordInputBar({super.key});

  @override
  State<RecordInputBar> createState() => _RecordInputBarState();
}

class _RecordInputBarState extends State<RecordInputBar> {
  final TextEditingController _textCtrl = TextEditingController();
  bool _isAiMode = false;

  // ---------- speech_to_text ----------
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

  // ---------- 语音初始化 ----------

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
            // 把光标移到末尾
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

  // ---------- 记账跳转 ----------

  void _handleSend() {
    final text = _textCtrl.text.trim();
    if (_isAiMode) {
      // AI 模式：把文字带过去自动解析
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AiQuickEntryView(initialText: text.isEmpty ? null : text),
        ),
      );
    } else {
      // 手动模式：直接打开数字键盘记账页
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const QuickAddView()),
      );
    }
    // 发送后清空输入框
    _textCtrl.clear();
  }

  void _handleTapTextField() {
    if (!_isAiMode) {
      // 手动模式：点输入框即跳转，不弹系统键盘
      _handleSend();
    }
    // AI 模式：正常聚焦，让用户输入文字
  }

  // ---------- + 扩展菜单 ----------

  void _showExtrasSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Text(
                    '更多功能',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 外层容器：surface + 顶部细线分隔
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 行 1：输入框 ──────────────────────────────────────────
              _InputField(
                controller: _textCtrl,
                isAiMode: _isAiMode,
                onTap: _handleTapTextField,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),

              // ── 行 2：工具栏 ─────────────────────────────────────────
              Row(
                children: [
                  // + 扩展
                  _ToolButton(
                    icon: Icons.add,
                    onTap: _showExtrasSheet,
                  ),
                  const SizedBox(width: 6),

                  // 手动 / AI 胶囊切换
                  _ModePill(
                    isAi: _isAiMode,
                    onChanged: (ai) => setState(() => _isAiMode = ai),
                  ),

                  const Spacer(),

                  // 话筒
                  _ToolButton(
                    icon: _listening ? Icons.mic : Icons.mic_none_outlined,
                    tintColor: _listening ? scheme.error : null,
                    onTap: _toggleListen,
                  ),
                  const SizedBox(width: 6),

                  // 发送
                  _SendButton(onTap: _handleSend),
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
// 输入框
// ---------------------------------------------------------------------------

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final bool isAiMode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const _InputField({
    required this.controller,
    required this.isAiMode,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 手动模式：手势拦截，点击直接跳转
      onTap: isAiMode ? null : onTap,
      child: AbsorbPointer(
        absorbing: !isAiMode,
        child: TextField(
          controller: controller,
          enabled: isAiMode,
          onTap: isAiMode ? null : onTap,
          onChanged: onChanged,
          textInputAction: TextInputAction.send,
          maxLines: 1,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: '记一记',
            hintStyle: TextStyle(
              color: scheme.onSurfaceVariant.withOpacity(0.55),
            ),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withOpacity(0.6),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 模式胶囊切换（手动 / AI）
// ---------------------------------------------------------------------------

class _ModePill extends StatelessWidget {
  final bool isAi;
  final ValueChanged<bool> onChanged;

  const _ModePill({required this.isAi, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillSegment(
            label: '手动',
            selected: !isAi,
            onTap: () => onChanged(false),
          ),
          _PillSegment(
            label: 'AI',
            selected: isAi,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _PillSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 小图标按钮（+ / 话筒）
// ---------------------------------------------------------------------------

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? tintColor;

  const _ToolButton({
    required this.icon,
    required this.onTap,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tintColor ?? scheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 发送按钮（深色圆形箭头）
// ---------------------------------------------------------------------------

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_upward,
          size: 20,
          color: scheme.onPrimary,
        ),
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
