import 'package:decimal/decimal.dart';

/// 快记键盘的金额输入模型，支持连加 / 连减（如 12+3.5-2）。
/// 不变式：[_parts] 始终非空，最后一项是正在编辑的数字；
///        [_signs] 与 [_parts] 等长，[_signs[0]] 恒为 +1。
class AmountExpression {
  static const int maxIntegerDigits = 9;
  static const int maxFractionDigits = 2;

  List<String> _parts = [''];
  List<int> _signs = [1]; // 每一段的符号：+1 / -1

  AmountExpression();

  /// 用于测试 / copy 的内部构造（拷贝列表）。
  AmountExpression._fromParts(List<String> parts, List<int> signs)
      : _parts = List.of(parts),
        _signs = List.of(signs);

  AmountExpression copy() => AmountExpression._fromParts(_parts, _signs);

  bool get isEmpty => _parts.length == 1 && _parts[0] == '';

  /// 是否是多段表达式（UI 据此显示 "=合计"）。
  bool get isCompound => _parts.length > 1;

  /// 表达式合计金额（带符号求和）。
  Decimal get value {
    var sum = Decimal.zero;
    for (var i = 0; i < _parts.length; i++) {
      final parsed = Decimal.tryParse(_parts[i]);
      if (parsed == null) continue;
      sum += _signs[i] >= 0 ? parsed : (Decimal.zero - parsed);
    }
    return sum;
  }

  /// 键盘上方展示的原始表达式文本，如 "12+3.5-2"。
  String get displayText {
    if (isEmpty) return '0';
    final sb = StringBuffer();
    for (var i = 0; i < _parts.length; i++) {
      if (i > 0) sb.write(_signs[i] >= 0 ? '+' : '-');
      sb.write(_parts[i]);
    }
    return sb.toString();
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

  /// 按下 "+"：结束当前数字，开始输入下一段（加）。当前段无法解析为数字时忽略。
  void beginAddition() => _appendTerm(1);

  /// 按下 "−"：结束当前数字，开始输入下一段（减）。当前段无法解析为数字时忽略。
  void beginSubtraction() => _appendTerm(-1);

  void _appendTerm(int sign) {
    if (Decimal.tryParse(_parts.last) == null) return;
    _parts.add('');
    _signs.add(sign);
  }

  void deleteBackward() {
    var current = _parts.last;
    if (current.isEmpty) {
      if (_parts.length > 1) {
        _parts.removeLast();
        _signs.removeLast();
      }
    } else {
      current = current.substring(0, current.length - 1);
      _parts[_parts.length - 1] = current;
    }
  }

  void clear() {
    _parts = [''];
    _signs = [1];
  }

  /// 直接载入一个已有金额（编辑已有账目时把金额预填进键盘）。
  /// 负数或非正数视为清空。
  void loadAmount(Decimal value) {
    if (value <= Decimal.zero) {
      clear();
      return;
    }
    var s = value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    _parts = [s];
    _signs = [1];
  }
}
