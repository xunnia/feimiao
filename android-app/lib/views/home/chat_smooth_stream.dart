import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Claude-style adaptive streaming reveal controller.
///
/// Upstream LLM gateways frequently emit bursty SSE chunks (e.g. 20–120 chars
/// arriving every 100–300 ms). Rendering the raw buffer directly makes paragraphs
/// jump onto the screen in jarring blocks. This controller smoothly drains
/// incoming text at display refresh rate (vsync via [Ticker]):
/// - adapts drain speed to the queued backlog so fast models never fall behind
///   more than ~180–250 ms while bursts glide smoothly word-by-word;
/// - snaps immediately when [reduceMotion] is enabled or when [finish] is
///   called so tests and completed turns never lag behind final persistence.
class SmoothStreamTextController extends ChangeNotifier {
  final TickerProvider _vsync;
  Ticker? _ticker;
  String _target = '';
  int _revealedLength = 0;
  double _carry = 0;
  Duration? _lastElapsed;
  bool _reduceMotion = false;
  bool _disposed = false;

  /// Minimum characters per second when backlog is small — smooth, readable
  /// Claude iOS-style cadence (~38 chars/sec, ~1 char every 2–3 frames at 120Hz).
  static const double _minCharsPerSecond = 38.0;

  /// Target catch-up window (~380 ms) so even a large 80–200 char burst from
  /// an upstream relay glides out smoothly word-by-word instead of dumping
  /// an entire paragraph in 2–3 frames.
  static const double _catchUpWindowSeconds = 0.38;

  /// Soft ceiling on reveal velocity (chars/sec) while streaming is active:
  /// keeps fast relays and large proxy-flushed chunks feeling like fluid,
  /// continuous typing (~1.8–2.0 chars per 120Hz frame max) instead of jumping
  /// in whole blocks. Once the stream finishes (`complete()`), remaining text
  /// accelerates gently to finish within ~280 ms instead of hard-snapping.
  static const double _maxCharsPerSecond = 220.0;

  /// Accelerated drain ceiling after upstream finishes so the tail completes
  /// cleanly in a smooth glide without jarring block-snapping.
  static const double _finishingCharsPerSecond = 520.0;

  bool _finishing = false;
  VoidCallback? _onDrainComplete;

  SmoothStreamTextController({required TickerProvider vsync}) : _vsync = vsync;

  String get target => _target;

  bool get isCatchingUp => _revealedLength < _target.length;

  bool get isFinishing => _finishing && isCatchingUp;

  /// Visible slice aligned on UTF-16 grapheme / surrogate boundaries so
  /// emojis and CJK surrogate pairs are never split mid-code-point.
  String get visibleText {
    if (_revealedLength <= 0) return '';
    if (_revealedLength >= _target.length) return _target;
    return _target.substring(0, _safeCodeUnitBoundary(_target, _revealedLength));
  }

  /// Newly revealed tail length for optional subtle lead-in emphasis.
  int get revealedLength => _revealedLength;

  void setReduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    if (value && _revealedLength < _target.length) {
      snapToTarget();
    }
  }

  /// Update the authoritative upstream text buffer.
  ///
  /// - While [streaming] is true, reveals text progressively at vsync pace.
  /// - When [streaming] transitions to false with unrevealed backlog (e.g. a
  ///   bursty gateway flushed the final block right before `[DONE]`), pass
  ///   [smoothFinish: true] to smoothly finish draining the tail instead of
  ///   teleporting the rest of the answer in 1 frame.
  void update(
    String nextTarget, {
    required bool streaming,
    bool smoothFinish = false,
    VoidCallback? onDrainComplete,
  }) {
    if (_disposed) return;
    final previous = _target;
    _target = nextTarget;
    _onDrainComplete = onDrainComplete;

    // Non-streaming or reduced-motion: either smoothly drain final tail or snap.
    if (!streaming || _reduceMotion) {
      if (!_reduceMotion &&
          smoothFinish &&
          _revealedLength < _target.length &&
          _target.length - _revealedLength <= 600) {
        _finishing = true;
        _ensureTicker();
        return;
      }
      _finishing = false;
      _stopTicker();
      if (_revealedLength != _target.length || previous != _target) {
        _revealedLength = _target.length;
        _carry = 0;
        notifyListeners();
      }
      _onDrainComplete?.call();
      _onDrainComplete = null;
      return;
    }

    _finishing = false;

    // If upstream replaced/shortened text (e.g. final canonical answer or
    // reset), clamp safely.
    if (!_target.startsWith(previous) || _revealedLength > _target.length) {
      _revealedLength = _revealedLength.clamp(0, _target.length);
    }

    // Tiny first chunk (1–2 chars): show immediately so time-to-first-glyph
    // has zero artificial delay.
    if (previous.isEmpty && _target.length <= 2) {
      _revealedLength = _target.length;
      _carry = 0;
      notifyListeners();
      return;
    }

    if (_revealedLength < _target.length) {
      _ensureTicker();
    } else if (previous != _target) {
      notifyListeners();
    }
  }

  /// Snap immediately to the complete target (e.g. on reduceMotion or reset).
  void snapToTarget() {
    if (_disposed) return;
    _finishing = false;
    _stopTicker();
    if (_revealedLength != _target.length) {
      _revealedLength = _target.length;
      _carry = 0;
      notifyListeners();
    }
    final cb = _onDrainComplete;
    _onDrainComplete = null;
    cb?.call();
  }

  void _ensureTicker() {
    if (_disposed) return;
    _ticker ??= _vsync.createTicker(_onTick);
    if (!_ticker!.isActive) {
      _lastElapsed = null;
      _ticker!.start();
    }
  }

  void _stopTicker() {
    _ticker?.stop();
    _lastElapsed = null;
  }

  void _onTick(Duration elapsed) {
    if (_disposed) {
      _stopTicker();
      return;
    }
    final prev = _lastElapsed;
    _lastElapsed = elapsed;
    final dtSec = prev == null
        ? 1 / 120
        : ((elapsed - prev).inMicroseconds / 1000000.0).clamp(0.002, 0.05);

    final pending = _target.length - _revealedLength;
    if (pending <= 0) {
      _finishing = false;
      _stopTicker();
      final cb = _onDrainComplete;
      _onDrainComplete = null;
      cb?.call();
      return;
    }

    // Adaptive, refresh-rate-independent velocity:
    // - smooth gentle glide when backlog is small (_minCharsPerSecond)
    // - smoothly speeds up as backlog grows, capped at _maxCharsPerSecond
    //   so even large 100+ char proxy bursts stream out fluidly word-by-word
    //   at 120Hz rather than popping whole paragraphs in 1-2 frames.
    final maxRate = _finishing ? _finishingCharsPerSecond : _maxCharsPerSecond;
    final window = _finishing ? 0.22 : _catchUpWindowSeconds;
    final rate = math
        .max(_minCharsPerSecond, pending / window)
        .clamp(_minCharsPerSecond, maxRate)
        .toDouble();
    _carry += rate * dtSec;
    final step = _carry.floor();
    if (step <= 0) return;
    _carry -= step;

    final nextRaw = math.min(_target.length, _revealedLength + step);
    final nextSafe = _safeCodeUnitBoundary(_target, nextRaw);
    if (nextSafe == _revealedLength) {
      // Advance at least past a surrogate/ZWJ cluster if step landed inside one.
      final nudged = _advanceOneGrapheme(_target, _revealedLength);
      _revealedLength = nudged;
    } else {
      _revealedLength = nextSafe;
    }

    var drained = false;
    if (_revealedLength >= _target.length) {
      _revealedLength = _target.length;
      _carry = 0;
      _finishing = false;
      _stopTicker();
      drained = true;
    }
    notifyListeners();
    if (drained) {
      final cb = _onDrainComplete;
      _onDrainComplete = null;
      cb?.call();
    }
  }

  static int _safeCodeUnitBoundary(String text, int index) {
    if (index <= 0) return 0;
    if (index >= text.length) return text.length;
    // Avoid splitting a UTF-16 surrogate pair (high surrogate 0xD800..0xDBFF).
    final prevUnit = text.codeUnitAt(index - 1);
    if (prevUnit >= 0xD800 && prevUnit <= 0xDBFF) {
      return index + 1 <= text.length ? index + 1 : index - 1;
    }
    // Avoid leaving a trailing markdown emphasis marker alone if the next char
    // completes `**` so bold text doesn't flash raw `*` mid-token.
    if (prevUnit == 0x2A /* * */ &&
        index < text.length &&
        text.codeUnitAt(index) == 0x2A) {
      return index + 1;
    }
    return index;
  }

  static int _advanceOneGrapheme(String text, int from) {
    if (from >= text.length) return text.length;
    var next = from + 1;
    final unit = text.codeUnitAt(from);
    if (unit >= 0xD800 && unit <= 0xDBFF && next < text.length) {
      next++;
    }
    return next.clamp(0, text.length);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Pure helper to test adaptive streaming pacing math without a widget tree.
@visibleForTesting
int computeSmoothRevealStep({
  required int pendingChars,
  required double dtSeconds,
}) {
  if (pendingChars <= 0 || dtSeconds <= 0) return 0;
  final rate = math
      .max(38.0, pendingChars / 0.38)
      .clamp(38.0, 220.0)
      .toDouble();
  return math.min(pendingChars, math.max(1, (rate * dtSeconds).floor()));
}
