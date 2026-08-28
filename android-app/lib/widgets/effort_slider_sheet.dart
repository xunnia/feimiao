import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart';
import '../core/ai/ai_provider_config.dart';
import 'app_buttons.dart';
import '../views/common/app_sheet.dart';

/// Effort 滑块选择器（半屏弹窗）
///
/// 设计对齐图二：
/// - 标签区：Effort (灰色 w-100) + 当前档位名 (深墨色)
/// - Faster/Smarter 标签在滑条左右上方
/// - 滑条：较粗轨道、带圆角的方形滑块、深灰已过/浅灰未到、档位刻度圆点
/// - Ultra 专属：紫色渐变动画
/// - 档位：Low → Medium → High → Extra → Max → Ultra
Future<void> showEffortSliderSheet(BuildContext context) async {
  await showBlurSheet<void>(
    context,
    radius: 28,
    child: const _EffortSliderSheet(),
  );
}

class _EffortSliderSheet extends StatefulWidget {
  const _EffortSliderSheet();

  @override
  State<_EffortSliderSheet> createState() => _EffortSliderSheetState();
}

class _EffortSliderSheetState extends State<_EffortSliderSheet>
    with SingleTickerProviderStateMixin {
  late int _value;
  late AnimationController _ultraAnimController;

  static const _efforts = [
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
    AiReasoningEffort.xhigh, // Extra
    AiReasoningEffort.max,
    AiReasoningEffort.ultra,
  ];

  static const _labels = [
    'Low',
    'Medium',
    'High',
    'Extra',
    'Max',
    'Ultracode',
  ];

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final current = repo.chatReasoningEffort;
    _value = _efforts.indexOf(current);
    if (_value < 0) _value = 0;

    _ultraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (_value == _efforts.length - 1) {
      _ultraAnimController.repeat();
    }
  }

  @override
  void dispose() {
    _ultraAnimController.dispose();
    super.dispose();
  }

  void _onChange(double v) {
    final newValue = v.round().clamp(0, _efforts.length - 1);
    if (newValue != _value) {
      setState(() => _value = newValue);
      if (newValue == _efforts.length - 1) {
        _ultraAnimController.repeat();
      } else {
        _ultraAnimController.stop();
      }
    }
  }

  Future<void> _confirm() async {
    final repo = context.read<AppRepository>();
    await repo.setChatReasoningEffort(_efforts[_value]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUltra = _value == _efforts.length - 1;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {}, // 阻止点击穿透
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── 标题行：✕ + Effort 灰 + 档位深墨 ──
                      Row(
                        children: [
                          AppCircleButton(
                            icon: Icons.close,
                            size: 28,
                            iconSize: 18,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Effort',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _labels[_value],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ── Faster/Smarter 标签在滑条上方 ──
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Faster',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Smarter',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.48),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── 滑条 ──
                      _buildSlider(scheme, isUltra),

                      const SizedBox(height: 24),

                      // ── 确认按钮 ──
                      Center(
                        child: AppPillButton(
                          label: '确认',
                          onPressed: _confirm,
                        ),
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

  Widget _buildSlider(ColorScheme scheme, bool isUltra) {
    return SizedBox(
      height: 48,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 7.2,
          thumbShape: const _SquareThumbShape(size: 20),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: isUltra
              ? Colors.purple.shade400
              : scheme.onSurface.withValues(alpha: 0.7),
          inactiveTrackColor: scheme.onSurfaceVariant.withValues(alpha: 0.2),
          thumbColor: scheme.surface,
          tickMarkShape: const _DotTickMarkShape(),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: scheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
        child: Stack(
          children: [
            // Ultra 专属紫色渐变动画
            if (isUltra)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _ultraAnimController,
                  builder: (_, __) {
                    return CustomPaint(
                      painter: _UltraGradientPainter(
                        progress: _ultraAnimController.value,
                        trackHeight: 7.2,
                      ),
                    );
                  },
                ),
              ),
            // 滑条本体
            Slider(
              value: _value.toDouble(),
              min: 0,
              max: (_efforts.length - 1).toDouble(),
              divisions: _efforts.length - 1,
              onChanged: _onChange,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 方形滑块 ──
class _SquareThumbShape extends SliderComponentShape {
  final double size;
  const _SquareThumbShape({required this.size});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = sliderTheme.activeTrackColor!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(rrect, paint);
    canvas.drawRRect(rrect, borderPaint);
  }
}

// ── 档位圆点刻度 ──
class _DotTickMarkShape extends SliderTickMarkShape {
  const _DotTickMarkShape();

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) =>
      const Size(6, 6);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    required bool isEnabled,
  }) {
    final canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.inactiveTickMarkColor!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3, paint);
  }
}

// ── Ultra 紫色渐变流动动画 ──
class _UltraGradientPainter extends CustomPainter {
  final double progress;
  final double trackHeight;

  const _UltraGradientPainter({
    required this.progress,
    required this.trackHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      (size.height - trackHeight) / 2,
      size.width,
      trackHeight,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(trackHeight / 2),
    );

    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.purple.shade300,
        Colors.purple.shade500,
        Colors.purple.shade700,
        Colors.purple.shade500,
        Colors.purple.shade300,
      ],
      stops: [
        (progress - 0.2).clamp(0.0, 1.0),
        (progress - 0.1).clamp(0.0, 1.0),
        progress.clamp(0.0, 1.0),
        (progress + 0.1).clamp(0.0, 1.0),
        (progress + 0.2).clamp(0.0, 1.0),
      ],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_UltraGradientPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
