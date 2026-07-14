import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../core/money_format.dart';

/// 滚动计数的金额文本：首次出现从 0 平滑滚到目标值；
/// 之后金额变化时从旧值滚到新值（记账后结余跳动，有 iOS 那种利落感）。
class AnimatedMoney extends StatefulWidget {
  final Decimal value; // 展示的绝对值
  final String prefix; // '-' / '+' / ''
  final TextStyle? style;
  final Duration duration;

  const AnimatedMoney({
    super.key,
    required this.value,
    this.prefix = '',
    this.style,
    this.duration = const Duration(milliseconds: 650),
  });

  @override
  State<AnimatedMoney> createState() => _AnimatedMoneyState();
}

class _AnimatedMoneyState extends State<AnimatedMoney>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _anim;

  double get _target => widget.value.toDouble();

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: _target)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.forward();
  }

  @override
  void didUpdateWidget(AnimatedMoney old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _anim.value, end: _target)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ticker 被禁用的环境（小组件离屏渲染）里动画永远停在第 0 帧，
    // 会把金额渲成 ¥0.00——这种场景直接静态显示最终值。
    if (!TickerMode.valuesOf(context).enabled) {
      return Text(
        '${widget.prefix}${MoneyFormat.string(widget.value)}',
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final v = Decimal.parse(_anim.value.toStringAsFixed(2));
        return Text(
          '${widget.prefix}${MoneyFormat.string(v)}',
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
