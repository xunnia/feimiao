import 'package:decimal/decimal.dart';

/// 「解析更聪明」之异常提醒（纯逻辑，可单测）：
/// 把本次金额和同分类历史比，明显偏高就给一句温和提醒。
class SpendingAnomaly {
  SpendingAnomaly._();

  /// [pastAmounts]：同分类的历史支出金额（正数，不含本次）。
  /// 规则（保守，避免误报）：样本 ≥5；本次 > 历史中位数 ×2 且高出 ≥10 元。
  /// 命中返回提醒文案，否则 null。
  static String? note(
      List<Decimal> pastAmounts, Decimal current, String catName) {
    final past = pastAmounts.where((a) => a > Decimal.zero).toList()..sort();
    if (past.length < 5) return null;
    final med = past[past.length ~/ 2];
    if (med <= Decimal.zero) return null;
    final overTwice = current > med * Decimal.fromInt(2);
    final gapEnough = (current - med) >= Decimal.fromInt(10);
    if (overTwice && gapEnough) {
      return '这笔「$catName」比你平时(约 $med 元)高不少哦，确认没记错~';
    }
    return null;
  }
}
