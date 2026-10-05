import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The list extends behind the chrome; only its scroll padding reserves space.
class ChatReadingViewport extends StatefulWidget {
  final Widget Function(EdgeInsets padding) history;
  final Widget composer;
  final Widget header;
  final Widget topFade;
  final double headerHeight;
  const ChatReadingViewport(
      {super.key,
      required this.history,
      required this.composer,
      required this.header,
      required this.topFade,
      this.headerHeight = 56});
  @override
  State<ChatReadingViewport> createState() => _ChatReadingViewportState();
}

class _ChatReadingViewportState extends State<ChatReadingViewport> {
  double _composerHeight = 114;
  void _measure(Size size) {
    if (!mounted || (_composerHeight - size.height).abs() < 0.5) return;
    setState(() => _composerHeight = size.height);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
          // Fade history, not the theme behind it. A tint overlay repaints the
          // bottom with the top color and breaks the page gradient on IME lift.
          child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final start = bounds.height <= 0
                    ? 0.0
                    : ((bounds.height - _composerHeight - 20) / bounds.height)
                        .clamp(0.0, 1.0)
                        .toDouble();
                return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Colors.black,
                      Colors.black,
                      Colors.transparent
                    ],
                    stops: [
                      0,
                      start,
                      1
                    ]).createShader(bounds);
              },
              child: widget.history(EdgeInsets.only(
                  top: widget.headerHeight + 8, bottom: _composerHeight + 8)))),
      Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MeasureComposer(onSize: _measure, child: widget.composer)),
      Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 108,
          child: IgnorePointer(child: widget.topFade)),
      Positioned(left: 0, right: 0, top: 0, child: widget.header),
    ]);
  }
}

class _MeasureComposer extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;
  const _MeasureComposer({required this.onSize, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _ComposerBox(onSize);
  @override
  void updateRenderObject(BuildContext context, _ComposerBox renderObject) {
    renderObject.onSize = onSize;
  }
}

class _ComposerBox extends RenderProxyBox {
  ValueChanged<Size> onSize;
  Size? _lastSize;
  _ComposerBox(this.onSize);
  @override
  void performLayout() {
    super.performLayout();
    if (_lastSize == size) return;
    _lastSize = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && measured == size) onSize(measured);
    });
  }
}
