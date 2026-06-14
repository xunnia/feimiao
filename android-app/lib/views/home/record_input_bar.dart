import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'ai_chat_panel.dart';
import 'manual_add_sheet.dart';
import 'voice_input_sheet.dart';

/// 底部启动器卡片（对标 Claude 输入框）。
///
/// 样式：scheme.surface 白底 + 轻阴影 + 极浅边框，圆角 28。
/// 工具行：[+]  [模式胶囊 ▾]  …  [话筒]  [发送↑]
///
/// 点击分流：
///   手动模式 → ManualAddSheet（模态大卡片）
///   AI 模式  → AiFocusedInputSheet（贴键盘聚焦输入卡片）
///   话筒（任意模式）→ AiFocusedInputSheet 并立即开始录音
class RecordInputBar extends StatefulWidget {
  const RecordInputBar({super.key});

  @override
  State<RecordInputBar> createState() => _RecordInputBarState();
}

class _RecordInputBarState extends State<RecordInputBar> {
  bool _isAiMode = false;

  // ── 语音（仅用于话筒按钮 → 传参给 AiFocusedInputSheet）──
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(onError: (_) {});
    if (mounted) setState(() => _speechAvailable = available);
  }

  // ── 模式选择面板 ──────────────────────────────────────────────────────────

  void _showModeSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ModeSelectionSheet(
        isAiMode: _isAiMode,
        onSelected: (isAi) {
          Navigator.pop(ctx);
          setState(() => _isAiMode = isAi);
        },
      ),
    );
  }

  // ── 打开手动大卡片 ─────────────────────────────────────────────────────────

  void _openManual() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ManualAddSheet(
        onSwitchToAi: () {
          Navigator.pop(ctx);
          _openAi();
        },
      ),
    );
  }

  // ── 打开 AI 聚焦输入 ──────────────────────────────────────────────────────

  void _openAi() {
    showAiChatPanel(
      context,
      speechAvailable: _speechAvailable,
      onSwitchToManual: _openManual,
    );
  }

  // ── 话筒 ──────────────────────────────────────────────────────────────────

  void _onMicTap() {
    if (!_speechAvailable) {
      _showSnack('该设备不支持语音识别');
      return;
    }
    showVoiceInputSheet(context);
  }

  // ── 发送 / 点击输入区 ─────────────────────────────────────────────────────

  void _onSend() {
    if (_isAiMode) {
      _openAi();
    } else {
      _openManual();
    }
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

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          decoration: BoxDecoration(
            // 对标 Claude：近纯白底
            color: scheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scheme.outlineVariant.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000), // ~8% 黑
                blurRadius: 14,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 占位文字行（点击整行触发分流）──
              GestureDetector(
                onTap: _onSend,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '记一记',
                    style: TextStyle(
                      fontSize: 17,
                      color: scheme.onSurfaceVariant.withOpacity(0.55),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── 工具行 ──
              Row(
                children: [
                  _ToolCircleButton(
                    icon: Icons.add,
                    onTap: () => _showExtrasSheet(),
                  ),
                  const SizedBox(width: 8),
                  _ModePill(
                    isAi: _isAiMode,
                    onTap: _showModeSheet,
                  ),
                  const Spacer(),
                  _ToolCircleButton(
                    icon: Icons.mic,
                    onTap: _onMicTap,
                  ),
                  const SizedBox(width: 8),
                  _ToolCircleButton(
                    icon: Icons.arrow_upward,
                    filled: true,
                    onTap: _onSend,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExtrasSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '更多功能',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 模式选择面板（对标 Claude 选模型弹层）
// ─────────────────────────────────────────────────────────────────────────────

class _ModeSelectionSheet extends StatelessWidget {
  final bool isAiMode;
  final ValueChanged<bool> onSelected;

  const _ModeSelectionSheet({
    required this.isAiMode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶行：X 关闭 + 标题
            Row(
              children: [
                _CloseButton(onTap: () => Navigator.pop(context)),
                const SizedBox(width: 12),
                Text(
                  '记账方式',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 手动记账选项
            _ModeCard(
              title: '手动记账',
              subtitle: '数字键盘，手动记一笔',
              selected: !isAiMode,
              scheme: scheme,
              onTap: () => onSelected(false),
            ),
            const SizedBox(height: 10),

            // AI 记账选项
            _ModeCard(
              title: 'AI 记账',
              subtitle: '一句话或语音，智能拆多笔',
              selected: isAiMode,
              scheme: scheme,
              onTap: () => onSelected(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? scheme.primaryContainer.withOpacity(0.5)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 20, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 统一圆形工具按钮（透明底 + 淡阴影，对标 Claude）
//
// filled=true → 实心 scheme.primary 背景（发送按钮专用）
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _ToolCircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (filled) {
      // 发送按钮：铜金高亮（scheme.secondary），符合可爱风
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.secondary,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: scheme.onSecondary),
        ),
      );
    }

    // 次要按钮：透明底 + 淡边框 + 淡阴影
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
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
        child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 模式胶囊（透明底 + 淡阴影，swap_horiz 前置图标，不加粗）
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
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
            Icon(Icons.swap_horiz, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              isAi ? 'AI 记账' : '手动记账',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 圆形关闭按钮（透明风格，供 sheet 复用）
// ─────────────────────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
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
        child: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 扩展菜单项
// ─────────────────────────────────────────────────────────────────────────────

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
