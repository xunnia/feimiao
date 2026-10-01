import 'package:decimal/decimal.dart';

// 金额 ↔ 分 的通用换算。原来放在 core/budget/budget_window_resolver.dart，
// 旧预算系统删掉后（预算规则第三批）挪到这里；资产、仓库、预算都在用。

/// 金额入库前统一归一到 2 位小数（四舍五入）。
/// AI 解析、外部导入、手输余额等来源可能带来超精度金额，绝不能原样落库。
Decimal normalizeMoneyAmount(Decimal value) => value.round(scale: 2);

int decimalToBudgetCents(Decimal amount) {
  // 超过 2 位小数的金额四舍五入到分。这里绝不能抛异常：读取路径
  // （主页/统计/预算/小组件）会对全库交易行调用本函数，一条脏数据
  // 抛出来就是每次启动都崩且用户无法自救。
  return (amount * Decimal.fromInt(100)).round().toBigInt().toInt();
}

Decimal? budgetDecimalFromCents(int? cents) {
  if (cents == null) return null;
  final negative = cents < 0;
  final absolute = cents.abs();
  final value = '${negative ? '-' : ''}${absolute ~/ 100}.'
      '${(absolute % 100).toString().padLeft(2, '0')}';
  return Decimal.parse(value);
}
