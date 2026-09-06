import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// 思考强度滑块底部弹层。
///
/// 显示连续滑块（0.0-1.0），左侧「Faster」右侧「Smarter」，
/// 中间显示当前档位标签（Faster/Balanced/Smarter）。
class EffortSliderSheet extends StatefulWidget {
  final double currentEffort;
  final ValueChanged<double> onEffortChanged;

  const EffortSliderSheet({
    super.key,
    required this.currentEffort,
    required this.onEffortChanged,
  });

  @override
  State<EffortSliderSheet> createState() => _EffortSliderSheetState();
}

class _EffortSliderSheetState extends State<EffortSliderSheet> {
  late double _effort;

  @override
  void initState() {
    super.initState();
    _effort = widget.currentEffort;
  }

  String get _effortLabel {
    if (_effort < 0.33) return 'Faster';
    if (_effort < 0.66) return 'Balanced';
    return 'Smarter';
  }

  void _handleConfirm() {
    widget.onEffortChanged(_effort);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // 标题 + 帮助图标
              Row(
                children: [
                  Text(
                    'Effort Ultracode',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.help_outline,
                    size: 20,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Faster / Smarter 标签
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Faster',
                    style: AppType.caption(scheme),
                  ),
                  Text(
                    'Smarter',
                    style: AppType.caption(scheme),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 滑块
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                ),
                child: Slider(
                  value: _effort,
                  onChanged: (v) => setState(() => _effort = v),
                  activeColor: scheme.primary,
                  inactiveColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),

              // 当前档位标签
              Text(
                _effortLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 32),

              // 确定按钮
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _handleConfirm,
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
