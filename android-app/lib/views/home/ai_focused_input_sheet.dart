import 'package:flutter/material.dart';

import '../quick_add/ai_quick_entry_view.dart';
import 'voice_input_sheet.dart';

/// AI 聚焦输入卡片（贴键盘上方弹出，对标 Claude 输入框图五布局）。
///
/// 布局：
///   顶部：下拉手柄
///   中间：自动聚焦 TextField（无边框融入卡片，占位"记一记"）
///   底部工具行：[+]  [⇄手动记账胶囊]  …Spacer…  [话筒]  [发送↑]
///
/// 发送 → Navigator.push AiQuickEntryView(initialText)
/// 话筒 → showVoiceInputSheet（按住说话）
/// 模式胶囊 → onSwitchToManual 回调
///
/// [startVoiceImmediately] 已废弃但保留签名，避免调用方改动；
///  实际打开 voice_input_sheet 由 _onMicTap 处理。
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

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── 解析：关闭 sheet 并跳转全页 AI 记账 ──────────────────────────────────

  void _doParse() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context);
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiQuickEntryView(initialText: text),
      ),
    );
  }

  // ── 话筒：打开「按住说话」面板 ────────────────────────────────────────────

  void _onMicTap() {
    if (!widget.speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('该设备不支持语音识别'),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
      );
      return;
    }
    // 先收起键盘，再弹语音面板
    _focusNode.unfocus();
    showVoiceInputSheet(context);
  }

  // ── 扩展菜单（+ 按钮）────────────────────────────────────────────────────

  void _showExtras() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('即将到来'),
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasText = _textCtrl.text.trim().isNotEmpty;

    return Padding(
      // 跟键盘上移
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 拖动手柄 + 右上角关闭 ──
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 手柄居中
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 关闭按钮右侧
                  Positioned(
                    right: 12,
                    child: _ToolCircleButton(
                      icon: Icons.close,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),

            // ── 输入框（无边框，融入卡片）──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                autofocus: true,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _doParse(),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: '记一记',
                  hintStyle: TextStyle(
                    fontSize: 17,
                    color: scheme.onSurfaceVariant.withOpacity(0.55),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── 底部工具行 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Row(
                children: [
                  // + 扩展按钮
                  _ToolCircleButton(
                    icon: Icons.add,
                    onTap: _showExtras,
                  ),
                  const SizedBox(width: 8),

                  // 模式胶囊（⇄手动记账 → 切回手动大卡）
                  _ModePill(
                    label: '手动记账',
                    onTap: widget.onSwitchToManual,
                  ),

                  const Spacer(),

                  // 话筒按钮
                  _ToolCircleButton(
                    icon: Icons.mic,
                    onTap: _onMicTap,
                  ),
                  const SizedBox(width: 8),

                  // 发送按钮（实心主色，对标 Claude 右下角醒目按钮）
                  _ToolCircleButton(
                    icon: Icons.arrow_upward,
                    filled: true,
                    onTap: hasText ? _doParse : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 统一圆形工具按钮（透明底 + 淡阴影，对标 Claude）
//
// filled=true → 实心 scheme.primary（发送按钮）
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
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
      final active = onTap != null;
      // 发送按钮：铜金高亮（scheme.secondary），符合可爱风
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? scheme.secondary : scheme.onSurface.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? scheme.onSecondary : scheme.onSurface.withOpacity(0.38),
          ),
        ),
      );
    }

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
// 模式胶囊（透明底 + swap_horiz 前置图标 + 不加粗）
// ─────────────────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ModePill({required this.label, required this.onTap});

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
              label,
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
