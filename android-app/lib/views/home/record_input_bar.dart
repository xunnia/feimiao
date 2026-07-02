import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../widgets/glass.dart';
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
  bool _modeInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 启动时沿用上次记账模式（已持久化）。
    if (!_modeInit) {
      _modeInit = true;
      _isAiMode = context.read<AppRepository>().recordAiMode;
    }
  }

  void _setMode(bool ai) {
    if (_isAiMode != ai) {
      Haptics.selection();
      setState(() => _isAiMode = ai);
    }
    context.read<AppRepository>().setRecordAiMode(ai);
  }

  // ── 打开手动大卡片 ─────────────────────────────────────────────────────────

  void _openManual() {
    _setMode(false);
    showManualAddSheet(
      context,
      onSwitchToAi: () {
        Navigator.pop(context);
        _openAi();
      },
    );
  }

  // ── 打开 AI 聚焦输入 ──────────────────────────────────────────────────────

  void _openAi() {
    _setMode(true);
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
                foregroundPainter: const GlassEdgePainter(radius: 28),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
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
              const SizedBox(height: 10),

              // ── 工具行 ──
              Row(
                children: [
                  _ToolCircleButton(
                    icon: Icons.add,
                    onTap: () => showRecordExtrasSheet(context),
                  ),
                  const SizedBox(width: 6),
                  _ModePill(
                    isAi: _isAiMode,
                    onTap: () => _setMode(!_isAiMode),
                  ),
                  const Spacer(),
                  _ToolCircleButton(
                    icon: Icons.arrow_upward,
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

  const _ToolCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 统一玻璃圆钮：透明模糊 + 不规则细黑边，黑色图标。
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: GlassSurface(
          circle: true,
          blur: 0, // 在输入卡内部，背景均匀，无需再模糊
          child: Center(
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
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
      child: GlassSurface(
        radius: 16,
        blur: 0, // 在输入卡内部，背景均匀，无需再模糊
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isAi ? Icons.auto_awesome : Icons.edit_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                isAi ? 'AI 记账' : '手动记账',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

