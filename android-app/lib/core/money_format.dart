import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// 货币格式化工具（对应 iOS MoneyFormat）。
/// 金额使用 [Decimal] 保证精度，转 double 仅供图表等场景使用。
class MoneyFormat {
  MoneyFormat._();

  /// 货币符号，如 "CNY" -> "¥"。
  /// 借助 [NumberFormat.simpleCurrency] 从 intl 获取本地化符号；
  /// 无法识别的货币码直接返回原码字符串。
  static String symbol(String currencyCode) {
    try {
      final fmt = NumberFormat.simpleCurrency(name: currencyCode);
      return fmt.currencySymbol;
    } catch (_) {
      return currencyCode;
    }
  }

  /// "¥1,234.50" 风格的金额文本（固定两位小数）。
  /// CNY 强制用 "¥"，避免某些 intl locale 下输出 "CN¥" 或 "CNY"。
  static String string(Decimal amount, {String currencyCode = 'CNY'}) {
    try {
      final sym = currencyCode == 'CNY' ? '¥' : symbol(currencyCode);
      final fmt = NumberFormat.currency(
        symbol: sym,
        decimalDigits: 2,
      );
      return fmt.format(amount.toDouble());
    } catch (_) {
      return '¥${amount.toStringAsFixed(2)}';
    }
  }

  /// [Decimal] -> [double]，仅供图表/动画等不需要精确计算的场合。
  static double toDouble(Decimal amount) => amount.toDouble();
}
