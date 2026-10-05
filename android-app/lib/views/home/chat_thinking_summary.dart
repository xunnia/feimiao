import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'chat_markdown_body.dart';

class ChatThinkingSummary extends StatefulWidget {
  final bool completed;
  final bool initiallyExpanded;
  final String summary;
  final String label;
  final TextStyle style;
  const ChatThinkingSummary(
      {super.key,
      required this.completed,
      required this.summary,
      required this.label,
      required this.style,
      this.initiallyExpanded = false});

  @override
  State<ChatThinkingSummary> createState() => _ChatThinkingSummaryState();
}

class _ChatThinkingSummaryState extends State<ChatThinkingSummary>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _pulse;
  Timer? _timer;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1350));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePulse();
  }

  void _updatePulse() {
    _timer?.cancel();
    if (widget.completed ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _pulse.stop();
      return;
    }
    if (!_pulse.isAnimating) _pulse.forward(from: 0);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _pulse.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(ChatThinkingSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.completed && widget.completed) _expanded = false;
    if (oldWidget.completed != widget.completed) _updatePulse();
    if (oldWidget.summary != widget.summary &&
        _expanded &&
        (!_scroll.hasClients || _scroll.position.extentAfter < 32)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _expanded && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSummary = widget.summary.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final color =
        widget.style.color ?? scheme.onSurface.withValues(alpha: 0.68);
    final label = Text(widget.label,
        key: const ValueKey('ai-chat-thinking-label'), style: widget.style);
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: hasSummary
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Semantics(
                button: hasSummary,
                expanded: hasSummary ? _expanded : null,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: widget.completed
                              ? label
                              : AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (_, child) => ShaderMask(
                                      blendMode: BlendMode.srcIn,
                                      shaderCallback: (bounds) =>
                                          LinearGradient(
                                            begin: Alignment(
                                                -1.8 + _pulse.value * 3.6, 0),
                                            end: Alignment(
                                                -0.8 + _pulse.value * 3.6, 0),
                                            colors: [
                                              color.withValues(
                                                  alpha: color.a * 0.78),
                                              color,
                                              color.withValues(
                                                  alpha: color.a * 0.78)
                                            ],
                                          ).createShader(bounds),
                                      child: child),
                                  child: label)),
                      if (hasSummary) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                            turns: _expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 170),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 18, color: color))
                      ],
                    ]))),
          ),
          AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 190),
              alignment: Alignment.topLeft,
              curve: Curves.easeOutCubic,
              child: _expanded && hasSummary
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      key: const ValueKey('ai-chat-thinking-details'),
                      children: [
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: Scrollbar(
                                  controller: _scroll,
                                  child: SingleChildScrollView(
                                      controller: _scroll,
                                      padding: const EdgeInsets.only(
                                          top: 7, right: 16, bottom: 10),
                                      child: ChatMarkdownBody(
                                          text: widget.summary,
                                          style: widget.style.copyWith(
                                              fontSize: 13, height: 1.5))))),
                          Divider(
                              height: 1,
                              thickness: 0.6,
                              color: AppColors.hairline(scheme)),
                        ])
                  : const SizedBox.shrink()),
        ]));
  }
}
