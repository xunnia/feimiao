import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../widgets/pressable_scale.dart';
import 'ai_chat_panel.dart';
import 'manual_add_sheet.dart';
import 'record_extras_sheet.dart';

/// 底部启动器卡片（对标 Claude 输入框）。
///
/// 样式：scheme.surface 白底 + 轻阴影 + 极浅边框，圆角 28。
/// 工具行：[+]  [模式胶囊 ▾]  …  [发送↑]
///
/// 点击分流：
///   手动模式 → ManualAddSheet（模态大卡片）
///   AI 模式  → AiChatPanel（贴键盘聚焦输入卡片，语音用键盘自带听写）
///
/// 交互手感：可点元素统一用 [PressableScale]（按下缩放 + 变暗 + 触感），
/// 不用 Material 水波纹，贴近 iOS。
class RecordInputBar extends StatefulWidget {
  const RecordInputBar({super.key});

  @override
  State<RecordInputBar> createState() => _RecordInputBarState();
}

class _RecordInputBarState extends State<RecordInputBar> {
  bool _isAiMode = false;

  // ── 打开手动大卡片 ─────────────────────────────────────────────────────────

  void _openManual() {
    // 记住本次选择：下次打开默认手动
    setState(() => _isAiMode = false);
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
    // 记住本次选择：下次打开默认 AI
    setState(() => _isAiMode = true);
    showAiChatPanel(
      context,
      onSwitchToManual: _openManual,
    );
  }

  // ── 发送 / 点击输入区 ─────────────────────────────────────────────────────

  void _onSend() {
    if (_isAiMode) {
      _openAi();
    } else {
      _openManual();
    }
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000), // ~8% 黑
                blurRadius: 14,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: CustomPaint(
                foregroundPainter: const _GlassEdgePainter(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                  decoration: BoxDecoration(
                    // iOS 玻璃：半透明白底；细黑边由 _GlassEdgePainter 画（深浅不均）
                    color: scheme.surface.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 占位文字行（点击整行触发分流）──
              PressableScale(
                onPressed: _onSend,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '记一记',
                    style: TextStyle(
                      fontSize: 17,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
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
                    onTap: () => showRecordExtrasSheet(context),
                  ),
                  const SizedBox(width: 8),
                  _ModePill(
                    isAi: _isAiMode,
                    onTap: () => setState(() => _isAiMode = !_isAiMode),
                  ),
                  const Spacer(),
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
            ),
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
      return PressableScale(
        onPressed: onTap,
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
    return PressableScale(
      onPressed: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
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
    return PressableScale(
      onPressed: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
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

/// Claude 风玻璃边：沿圆角描一圈深浅不均的细线——
/// 顶部一抹白色高光，往下渐变成一条很细的黑线（深浅/明暗不等粗）。
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      const Radius.circular(28),
    );
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x99FFFFFF), // 顶部高光（白 ~60%）
        Color(0x0F000000), // 中段很淡（黑 ~6%）
        Color(0x29000000), // 底部偏深（黑 ~16%）
      ],
      stops: [0.0, 0.45, 1.0],
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = shader;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter oldDelegate) => false;
}
