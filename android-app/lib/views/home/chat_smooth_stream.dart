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

  /// Minimum characters per second when backlog is tiny (smooth, calm glide).
  static const double _minCharsPerSecond = 56.0;

  /// Target catch-up window so large bursts drain smoothly within ~160 ms
  /// rather than stalling behind fast models.
  static const double _catchUpWindowSeconds = 0.16;

  /// Maximum reveal rate (chars/sec) — scaled by actual frame `dtSec` so
  /// 60Hz, 90Hz, 120Hz and 144Hz displays all run at the exact same smooth
  /// physical velocity, with half-sized per-frame micro-steps at 120Hz.
  static const double _maxCharsPerSecond = 1600.0;

  SmoothStreamTextController({required TickerProvider vsync}) : _vsync = vsync;

  String get target => _target;

  bool get isCatchingUp => _revealedLength < _target.length;

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
  /// When [streaming] is false (completed, restored from history, or reduced
  /// motion), the full text is shown immediately.
  void update(String nextTarget, {required bool streaming}) {
    if (_disposed) return;
    final previous = _target;
    _target = nextTarget;

    // Non-streaming or reduced-motion: reveal immediately.
    if (!streaming || _reduceMotion) {
      _stopTicker();
      if (_revealedLength != _target.length || previous != _target) {
        _revealedLength = _target.length;
        _carry = 0;
        notifyListeners();
      }
      return;
    }

    // If upstream replaced/shortened text (e.g. final canonical answer or
    // reset), clamp safely.
    if (!_target.startsWith(previous) || _revealedLength > _target.length) {
      _revealedLength = _revealedLength.clamp(0, _target.length);
    }

    // Tiny first chunk (1–3 chars): show immediately so time-to-first-glyph
    // has zero artificial delay.
    if (previous.isEmpty && _target.length <= 4) {
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

  /// Snap immediately to the complete target (e.g. on stream completion).
  void snapToTarget() {
    if (_disposed) return;
    _stopTicker();
    if (_revealedLength != _target.length) {
      _revealedLength = _target.length;
      _carry = 0;
      notifyListeners();
    }
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
      _stopTicker();
      return;
    }

    // Adaptive, refresh-rate-independent rate: fast enough to finish current
    // backlog in ~160 ms, floored at _minCharsPerSecond and capped at
    // _maxCharsPerSecond so 120Hz/144Hz frames take finer steps per tick.
    final rate = math
        .max(_minCharsPerSecond, pending / _catchUpWindowSeconds)
        .clamp(_minCharsPerSecond, _maxCharsPerSecond)
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

    if (_revealedLength >= _target.length) {
      _revealedLength = _target.length;
      _carry = 0;
      _stopTicker();
    }
    notifyListeners();
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
      .max(56.0, pendingChars / 0.16)
      .clamp(56.0, 1600.0)
      .toDouble();
  return math.min(pendingChars, math.max(1, (rate * dtSeconds).floor()));
}
