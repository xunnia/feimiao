import 'package:flutter/services.dart';

/// 语义化触感反馈封装。
///
/// 集中管理全 App 的振动手感，便于统一风格、将来加「关闭振动」开关。
/// Android 没有 iOS 的 notification feedback（success/warning），
/// 这里用 impact 近似。
enum Haptic { selection, light, medium, heavy, success, warning }

class Haptics {
  Haptics._();

  static void of(Haptic h) {
    switch (h) {
      case Haptic.selection:
        HapticFeedback.selectionClick();
      case Haptic.light:
        HapticFeedback.lightImpact();
      case Haptic.medium:
        HapticFeedback.mediumImpact();
      case Haptic.heavy:
        HapticFeedback.heavyImpact();
      case Haptic.success:
        HapticFeedback.mediumImpact(); // Android 近似
      case Haptic.warning:
        HapticFeedback.heavyImpact(); // Android 近似
    }
  }

  static void selection() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
}
