import 'package:flutter/material.dart';

import 'mascot.dart';

/// 顶部轻提示（对齐 Claude 的「已复制」toast）：
/// 深色小胶囊从顶部滑入，停 1.2 秒后淡出。全 App 的轻提示统一用它。
/// [mascot] 非空时用猫表情替代图标（如记账/核对成功配 MascotMood.success）。
void showAppToast(BuildContext context, String text,
    {IconData icon = Icons.check_circle, MascotMood? mascot}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      text: text,
      icon: icon,
      mascot: mascot,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String text;
  final IconData icon;
  final MascotMood? mascot;
  final VoidCallback onDone;

  const _Toast({
    required this.text,
    required this.icon,
    this.mascot,
    required this.onDone,
  });

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top + 12;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_c.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Center(
            child: Container(
              // 长文案（如错误信息）别顶出屏幕：限宽 + 最多两行。
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 48),
              // 配猫图（22px）时上下内距略收，胶囊不至于被撑得太高。
              padding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: widget.mascot == null ? 8 : 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.mascot != null)
                    // Mascot 自带加载失败回退 emoji，不会崩。
                    Mascot(mood: widget.mascot!, size: 22, animate: false)
                  else
                    Icon(widget.icon, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
