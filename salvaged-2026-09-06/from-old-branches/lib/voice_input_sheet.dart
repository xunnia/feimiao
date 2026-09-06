import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../quick_add/ai_quick_entry_view.dart';

/// 按住说话语音输入面板（对标图二，极简无吉祥物）。
///
/// 用 showVoiceInputSheet 弹出，识别完成后自动跳转 AiQuickEntryView。
Future<void> showVoiceInputSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _VoiceInputSheet(),
  );
}

class _VoiceInputSheet extends StatefulWidget {
  const _VoiceInputSheet();

  @override
  State<_VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<_VoiceInputSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _listening = false;
  String _recognized = '';
  String _statusText = '按住下方按钮说话';

  // 脉冲动画控制器（录音中使用）
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // 随机波形高度（固定种子，每次按住重新生成）
  final List<double> _bars = List.generate(18, (_) => 0.0);
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _pulseCtrl.reverse();
        } else if (status == AnimationStatus.dismissed && _listening) {
          _pulseCtrl.forward();
        }
      });
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
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
      onError: (_) {
        if (mounted) {
          setState(() {
            _listening = false;
            _statusText = '按住下方按钮说话';
          });
          _pulseCtrl.stop();
        }
      },
      onStatus: (status) {
        if ((status == stt.SpeechToText.doneStatus ||
                status == stt.SpeechToText.notListeningStatus) &&
            mounted) {
          setState(() {
            _listening = false;
            _statusText = _recognized.isEmpty ? '没听清，再试一次' : _recognized;
          });
          _pulseCtrl.stop();
        }
      },
    );
    if (mounted) setState(() => _speechReady = available);
  }

  // ── 按住开始 ──────────────────────────────────────────────────────────────

  Future<void> _onPressStart(LongPressStartDetails _) async {
    if (!_speechReady) {
      _showSnack('该设备不支持语音识别');
      return;
    }
    if (_listening) return;

    // 重置状态
    setState(() {
      _recognized = '';
      _statusText = '正在聆听… 松开结束';
      _listening = true;
      _refreshBars();
    });
    _pulseCtrl.forward();

    final started = await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _recognized = result.recognizedWords;
          _refreshBars();
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      localeId: 'zh_CN',
      cancelOnError: true,
      partialResults: true,
    );

    if (!started && mounted) {
      setState(() {
        _listening = false;
        _statusText = '无法启动语音识别，请检查麦克风权限';
      });
      _pulseCtrl.stop();
    }
  }

  // ── 松开结束 ──────────────────────────────────────────────────────────────

  Future<void> _onPressEnd(LongPressEndDetails _) async {
    if (!_listening) return;
    await _speech.stop();
    if (!mounted) return;

    final text = _recognized.trim();
    _pulseCtrl.stop();

    if (text.isEmpty) {
      setState(() {
        _listening = false;
        _statusText = '没听清，再试一次';
      });
      return;
    }

    // 关闭本 sheet，再跳转 AI 解析页
    Navigator.pop(context);
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiQuickEntryView(initialText: text),
      ),
    );
  }

  void _refreshBars() {
    for (int i = 0; i < _bars.length; i++) {
      _bars[i] = _listening ? (0.2 + _rng.nextDouble() * 0.8) : 0.15;
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
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 下拉手柄
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
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

            // 波形 / 脉冲可视化（高度 48，仅录音中有动感）
            SizedBox(
              height: 48,
              child: _listening
                  ? AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => _WaveformBars(
                        bars: _bars,
                        color: scheme.primary,
                        scale: _pulseAnim.value,
                      ),
                    )
                  : _WaveformBars(
                      bars: List.filled(18, 0.1),
                      color: scheme.outlineVariant,
                      scale: 1.0,
                    ),
            ),

            const SizedBox(height: 20),

            // 提示文字 / 识别结果
            Text(
              _recognized.isNotEmpty ? _recognized : _statusText,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                color: _recognized.isNotEmpty
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 32),

            // 按住说话按钮
            GestureDetector(
              onLongPressStart: _onPressStart,
              onLongPressEnd: _onPressEnd,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _listening ? _pulseAnim.value : 1.0,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _listening ? scheme.primary : scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _listening
                            ? scheme.primary
                            : Colors.black.withOpacity(0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _listening
                              ? scheme.primary.withOpacity(0.25)
                              : Colors.black.withOpacity(0.06),
                          blurRadius: _listening ? 12 : 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
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
                          _listening ? '正在聆听… 松开结束' : '按住说话',
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
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 波形条形图（一排小竖条，极简）
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  final List<double> bars; // 每条归一化高度 [0, 1]
  final Color color;
  final double scale;

  const _WaveformBars({
    required this.bars,
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: bars.map((h) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: 48 * h * scale,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }).toList(),
    );
  }
}
