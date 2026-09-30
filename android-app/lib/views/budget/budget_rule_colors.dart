import 'package:flutter/material.dart';

import '../../core/budget/budget_rules.dart';
import '../../theme/app_tokens.dart';

/// 特别安排的颜色：按新建顺序轮流取蓝、紫、粉、青、灰蓝（docs/08 §6.2）。
/// 不用绿（预算健康）、金（收入）、橙（超支）。iOS `BudgetRuleColors` 同一组色值。
const budgetRulePalette = <Color>[
  Color(0xFF5C8DD4),
  Color(0xFF9C7FD0),
  Color(0xFFD08BB0),
  Color(0xFF4FA3B3),
  Color(0xFF7F93AE),
];

/// 规则的点/色条颜色：日常预算不画色条，点用灰。
Color budgetRuleColor(BudgetRule rule, ColorScheme scheme) => rule.isBase
    ? AppTextColor.hint(scheme)
    : budgetRulePalette[rule.colorIndex % budgetRulePalette.length];

class BudgetRuleDot extends StatelessWidget {
  final Color color;
  final double size;

  const BudgetRuleDot({super.key, required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
