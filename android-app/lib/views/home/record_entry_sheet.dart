import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import 'ai_chat_panel.dart';
import 'manual_add_sheet.dart';

enum RecordEntryMode { manual, ai }

Future<void> showRecordEntrySheet(
  BuildContext context, {
  required RecordEntryMode initialMode,
  ValueChanged<bool>? onModeChanged,
}) async {
  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: '记账',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, __, ___) => _RecordEntrySheetHost(
      initialMode: initialMode,
      onModeChanged: onModeChanged,
    ),
    transitionsBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.045),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  await Navigator.of(context, rootNavigator: true).push<void>(route);
}

class _RecordEntrySheetHost extends StatefulWidget {
  final RecordEntryMode initialMode;
  final ValueChanged<bool>? onModeChanged;

  const _RecordEntrySheetHost({
    required this.initialMode,
    this.onModeChanged,
  });

  @override
  State<_RecordEntrySheetHost> createState() => _RecordEntrySheetHostState();
}

class _RecordEntrySheetHostState extends State<_RecordEntrySheetHost>
    with SingleTickerProviderStateMixin {
  static const Duration _switchDuration = Duration(milliseconds: 150);

  late RecordEntryMode _mode;
  RecordEntryMode? _outgoingMode;
  late final AnimationController _switchController;
  bool _manualBuilt = false;
  bool _aiBuilt = false;
  bool _ignoreManualKeyboardInset = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _manualBuilt = _mode == RecordEntryMode.manual;
    _aiBuilt = _mode == RecordEntryMode.ai;
    _switchController = AnimationController(
      vsync: this,
      duration: _switchDuration,
      value: 1,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _outgoingMode != null) {
          setState(() => _outgoingMode = null);
        }
      });
  }

  @override
  void dispose() {
    _switchController.dispose();
    super.dispose();
  }

  void _setMode(RecordEntryMode mode) {
    if (_mode == mode) return;
    Haptics.selection();
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final ai = mode == RecordEntryMode.ai;

    FocusManager.instance.primaryFocus?.unfocus();
    context.read<AppRepository>().setRecordAiMode(ai);
    widget.onModeChanged?.call(ai);

    setState(() {
      _outgoingMode = _mode;
      _mode = mode;
      _manualBuilt = _manualBuilt || mode == RecordEntryMode.manual;
      _aiBuilt = _aiBuilt || mode == RecordEntryMode.ai;
      _ignoreManualKeyboardInset = !ai && keyboardOpen;
    });
    _switchController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (_aiBuilt)
        _EntryModeSlot(
          key: const ValueKey('record-entry-ai-slot'),
          controller: _switchController,
          mode: RecordEntryMode.ai,
          currentMode: _mode,
          outgoingMode: _outgoingMode,
          child: RepaintBoundary(
            child: AiChatPanel(
              fastSwitch: true,
              active: _mode == RecordEntryMode.ai,
              recordOnly: true,
              onSwitchToManual: () => _setMode(RecordEntryMode.manual),
            ),
          ),
        ),
      if (_manualBuilt)
        _EntryModeSlot(
          key: const ValueKey('record-entry-manual-slot'),
          controller: _switchController,
          mode: RecordEntryMode.manual,
          currentMode: _mode,
          outgoingMode: _outgoingMode,
          child: _KeyboardInsetFrame(
            key: const ValueKey('record-entry-manual-frame'),
            ignoreInitialKeyboardInset: _ignoreManualKeyboardInset,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: ManualAddSheet(
                    onSwitchToAi: () => _setMode(RecordEntryMode.ai),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];

    return Stack(
      fit: StackFit.expand,
      children: children,
    );
  }
}

class _EntryModeSlot extends StatelessWidget {
  final AnimationController controller;
  final RecordEntryMode mode;
  final RecordEntryMode currentMode;
  final RecordEntryMode? outgoingMode;
  final Widget child;

  const _EntryModeSlot({
    super.key,
    required this.controller,
    required this.mode,
    required this.currentMode,
    required this.outgoingMode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = currentMode == mode;
    final isOutgoing = outgoingMode == mode && controller.isAnimating;
    final shouldPaint = isCurrent || isOutgoing;

    final keptChild = Offstage(
      offstage: !shouldPaint,
      child: TickerMode(
        enabled: isCurrent,
        child: IgnorePointer(
          ignoring: !isCurrent,
          child: child,
        ),
      ),
    );
    if (!shouldPaint) return keptChild;

    return AnimatedBuilder(
      animation: controller,
      child: keptChild,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(controller.value);
        final opacity = isCurrent ? t : (1 - t);
        final slide = isCurrent ? (1 - t) * 10 : -t * 6;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, slide),
            child: child,
          ),
        );
      },
    );
  }
}

class _KeyboardInsetFrame extends StatefulWidget {
  final Widget child;
  final bool ignoreInitialKeyboardInset;

  const _KeyboardInsetFrame({
    super.key,
    required this.child,
    required this.ignoreInitialKeyboardInset,
  });

  @override
  State<_KeyboardInsetFrame> createState() => _KeyboardInsetFrameState();
}

class _KeyboardInsetFrameState extends State<_KeyboardInsetFrame> {
  late bool _ignoreInsets;

  @override
  void initState() {
    super.initState();
    _ignoreInsets = widget.ignoreInitialKeyboardInset;
  }

  @override
  void didUpdateWidget(covariant _KeyboardInsetFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ignoreInitialKeyboardInset !=
        oldWidget.ignoreInitialKeyboardInset) {
      _ignoreInsets = widget.ignoreInitialKeyboardInset;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ignoreInsets && MediaQuery.viewInsetsOf(context).bottom <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ignoreInsets = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = _ignoreInsets ? 0.0 : mq.viewInsets.bottom;
    final child = _ignoreInsets
        ? MediaQuery(
            data: mq.copyWith(
              viewInsets: EdgeInsets.fromLTRB(
                mq.viewInsets.left,
                mq.viewInsets.top,
                mq.viewInsets.right,
                0,
              ),
            ),
            child: widget.child,
          )
        : widget.child;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: RepaintBoundary(child: child),
      ),
    );
  }
}
