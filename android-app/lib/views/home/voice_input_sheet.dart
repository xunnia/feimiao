import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 按住说话语音输入面板（对标咔皮：实时显示识别文字 + 上滑取消/编辑）。
///
/// 交互（微信/咔皮式按住-滑动）：
///   · 按住按钮 → 开始识别，中间实时显示听到的文字；
///   · 手指上滑到「取消」区 → 松手丢弃；
///   · 手指上滑到「编辑」区 → 松手把文字带去校对（同发送，进 AI 面板可改）；
///   · 不滑、停在按钮上「松手发送」→ 松手直接带文字去解析。
///
/// 返回识别到的文字（发送/编辑）；取消或没听清返回 null。
Future<String?> showVoiceInputSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _VoiceInputSheet(),
  );
}

/// 松手时手指所在区域。
enum _DragTarget { send, cancel, edit }

class _VoiceInputSheetState extends State<_VoiceInputSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _listening = false;
  String _recognized = '';
  String _hint = '按住下方按钮说话';
  String? _localeId; // 解析出的中文 locale

  _DragTarget _target = _DragTarget.send;

  // 实时音量（0~1）驱动波形
  double _level = 0.2;

  // 取消 / 编辑 两个区域的位置，用于命中判断
  final GlobalKey _cancelKey = GlobalKey();
  final GlobalKey _editKey = GlobalKey();

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.85,
      upperBound: 1.0,
    );
    _initSpeech();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (e) {
        // 不因瞬时错误中断已识别的文字；只在没有结果时提示
        if (!mounted) return;
        if (_recognized.isEmpty) {
          setState(() => _hint = '没听清，再按住试试');
        }
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == stt.SpeechToText.doneStatus ||
            status == stt.SpeechToText.notListeningStatus) {
          if (_listening) setState(() => _listening = false);
          _pulseCtrl.stop();
        }
      },
    );
    // 选一个中文 locale（zh / cmn / 中文），找不到就用系统默认
    if (available) {
      try {
        final locales = await _speech.locales();
        final zh = locales.where((l) {
          final id = l.localeId.toLowerCase();
          return id.startsWith('zh') ||
              id.startsWith('cmn') ||
              l.name.contains('中文') ||
              l.name.toLowerCase().contains('chinese');
        }).toList();
        if (zh.isNotEmpty) {
          // 优先简体中国大陆
          final cn = zh.firstWhere(
            (l) => l.localeId.toLowerCase().contains('cn') ||
                l.localeId.toLowerCase().contains('hans'),
            orElse: () => zh.first,
          );
          _localeId = cn.localeId;
        }
      } catch (_) {/* 用默认 */}
    }
    if (mounted) setState(() => _speechReady = available);
  }

  // ── 按住开始 ──────────────────────────────────────────────────────────────
  Future<void> _onPressStart(LongPressStartDetails _) async {
    if (!_speechReady) {
      _snack('该设备不支持语音识别，请检查系统语音服务');
      return;
    }
    if (_listening) return;

    setState(() {
      _recognized = '';
      _hint = '正在聆听…';
      _listening = true;
      _target = _DragTarget.send;
      _level = 0.3;
    });
    _pulseCtrl.repeat(reverse: true);

    final started = await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _recognized = result.recognizedWords);
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        // speech_to_text 的 level 约 -2~10，归一化到 0.15~1
        final norm = ((level + 2) / 12).clamp(0.15, 1.0);
        setState(() => _level = norm);
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 8),
      localeId: _localeId,
      cancelOnError: false,
      partialResults: true,
    );

    if (!started && mounted) {
      setState(() {
        _listening = false;
        _hint = '无法启动，请检查麦克风权限';
      });
      _pulseCtrl.stop();
    }
  }

  // ── 拖动：判断手指在哪个区 ───────────────────────────────────────────────────
  void _onPressMove(LongPressMoveUpdateDetails d) {
    if (!_listening) return;
    final p = d.globalPosition;
    final next = _hitTest(_cancelKey, p)
        ? _DragTarget.cancel
        : _hitTest(_editKey, p)
            ? _DragTarget.edit
            : _DragTarget.send;
    if (next != _target) setState(() => _target = next);
  }

  bool _hitTest(GlobalKey key, Offset globalPoint) {
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    // 放大命中范围，便于手指滑到
    return rect.inflate(16).contains(globalPoint);
  }

  // ── 松开结束 ──────────────────────────────────────────────────────────────
  Future<void> _onPressEnd(LongPressEndDetails _) async {
    if (!_listening) return;
    await _speech.stop();
    _pulseCtrl.stop();
    if (!mounted) return;

    if (_target == _DragTarget.cancel) {
      Navigator.pop(context); // 丢弃
      return;
    }

    final text = _recognized.trim();
    if (text.isEmpty) {
      setState(() {
        _listening = false;
        _hint = '没听清，再按住试试';
      });
      return;
    }
    // 发送 / 编辑都把文字带回（调用方进 AI 面板可继续校对）
    Navigator.pop(context, text);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 2000),
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 下拉手柄
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 实时识别文字（大字居中，像咔皮）
            Container(
              constraints: const BoxConstraints(minHeight: 72),
              alignment: Alignment.center,
              child: Text(
                _recognized.isNotEmpty ? _recognized : _hint,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _recognized.isNotEmpty ? 22 : 15,
                  fontWeight: _recognized.isNotEmpty
                      ? FontWeight.w600
                      : FontWeight.w400,
                  height: 1.35,
                  color: _recognized.isNotEmpty
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 18),

            // 取消 / 编辑 两个圆形区（录音时显示，手指滑上去高亮）
            AnimatedOpacity(
              opacity: _listening ? 1 : 0.35,
              duration: const Duration(milliseconds: 150),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SlotButton(
                    key: _cancelKey,
                    icon: Icons.close,
                    label: '取消',
                    active: _listening && _target == _DragTarget.cancel,
                    activeColor: scheme.error,
                  ),
                  _SlotButton(
                    key: _editKey,
                    icon: Icons.edit_outlined,
                    label: '编辑',
                    active: _listening && _target == _DragTarget.edit,
                    activeColor: scheme.primary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 波形（录音时按真实音量起伏）
            SizedBox(
              height: 36,
              child: _Waveform(
                active: _listening,
                level: _level,
                color: _target == _DragTarget.cancel
                    ? scheme.error
                    : scheme.primary,
              ),
            ),

            const SizedBox(height: 16),

            // 按住说话按钮
            GestureDetector(
              onLongPressStart: _onPressStart,
              onLongPressMoveUpdate: _onPressMove,
              onLongPressEnd: _onPressEnd,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) => Transform.scale(
                  scale: _listening ? _pulseCtrl.value : 1.0,
                  child: child,
                ),
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _listening
                        ? (_target == _DragTarget.cancel
                            ? scheme.error
                            : scheme.primary)
                        : scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _listening
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        size: 22,
                        color: _listening
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _listening
                            ? (_target == _DragTarget.cancel
                                ? '松手取消'
                                : _target == _DragTarget.edit
                                    ? '松手编辑'
                                    : '松手发送')
                            : '按住说话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _listening
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceInputSheet extends StatefulWidget {
  const _VoiceInputSheet();

  @override
  State<_VoiceInputSheet> createState() => _VoiceInputSheetState();
}

/// 取消 / 编辑 圆形目标按钮。
class _SlotButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;

  const _SlotButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: active ? 60 : 52,
          height: active ? 60 : 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? activeColor
                : scheme.surfaceContainerHighest,
          ),
          child: Icon(
            icon,
            color: active ? Colors.white : scheme.onSurfaceVariant,
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? activeColor : scheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// 一排随音量起伏的小竖条。
class _Waveform extends StatelessWidget {
  final bool active;
  final double level; // 0~1
  final Color color;

  const _Waveform({
    required this.active,
    required this.level,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const n = 21;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(n, (i) {
        // 中间高两边低的包络 × 实时音量
        final envelope = 1.0 - (((i - n / 2).abs()) / (n / 2)) * 0.6;
        final h = active ? (8 + 28 * level * envelope) : 4.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 3,
            height: h,
            decoration: BoxDecoration(
              color: active ? color : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
