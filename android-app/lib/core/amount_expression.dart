import 'package:decimal/decimal.dart';

/// 快记键盘的金额输入模型，支持连加（如 12+3.5+8）。
/// 不变式：[_parts] 始终非空，最后一项是正在编辑的数字。
class AmountExpression {
  static const int maxIntegerDigits = 9;
  static const int maxFractionDigits = 2;

  List<String> _parts = [''];

  AmountExpression();

  /// 用于测试的内部构造（拷贝 parts 列表）。
  AmountExpression._fromParts(List<String> parts) : _parts = List.of(parts);

  AmountExpression copy() => AmountExpression._fromParts(_parts);

  bool get isEmpty => _parts.length == 1 && _parts[0] == '';

  /// 是否是多段相加的表达式（UI 据此显示 "=合计"）。
  bool get isCompound => _parts.length > 1;

  /// 表达式合计金额。
  Decimal get value {
    return _parts.fold(Decimal.zero, (sum, part) {
      final parsed = Decimal.tryParse(part);
      return sum + (parsed ?? Decimal.zero);
    });
  }

  /// 键盘上方展示的原始表达式文本，如 "12+3.5"。
  String get displayText {
    if (isEmpty) return '0';
    return _parts.join('+');
  }

  void insertDigit(String digit) {
    if (digit.isEmpty || !RegExp(r'^\d$').hasMatch(digit)) return;
    var current = _parts.last;
    final dotIndex = current.indexOf('.');
    if (dotIndex >= 0) {
      final fractionCount = current.length - dotIndex - 1;
      if (fractionCount >= maxFractionDigits) return;
    } else {
      if (current.length >= maxIntegerDigits) return;
      if (current == '0') current = '';
    }
    current += digit;
    _parts[_parts.length - 1] = current;
  }

  void insertDot() {
    var current = _parts.last;
    if (current.contains('.')) return;
    if (current.isEmpty) current = '0';
    current += '.';
    _parts[_parts.length - 1] = current;
  }

  /// 按下 "+"：结束当前数字，开始输入下一段。当前段无法解析为数字时忽略。
  void beginAddition() {
    if (Decimal.tryParse(_parts.last) == null) return;
    _parts.add('');
  }

  void deleteBackward() {
    var current = _parts.last;
    if (current.isEmpty) {
      if (_parts.length > 1) _parts.removeLast();
    } else {
      current = current.substring(0, current.length - 1);
      _parts[_parts.length - 1] = current;
    }
  }

  void clear() {
    _parts = [''];
  }

  /// 直接载入一个已有金额（用于编辑已有账目时把金额预填进键盘）。
  /// 负数或非正数视为清空。
  void loadAmount(Decimal value) {
    if (value <= Decimal.zero) {
      clear();
      return;
    }
    // 去掉多余的尾零：12.00 → 12，3.50 → 3.5
    var s = value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    _parts = [s];
  }
}
