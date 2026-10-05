import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/money_format.dart';
import '../../theme/app_colors.dart';

abstract final class AssetOverviewStyle {
  static String amount(Decimal value) =>
      MoneyFormat.string(value).replaceAll('¥', '').trim();

  static Color labelColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (MediaQuery.highContrastOf(context)) return scheme.onSurface;
    return scheme.brightness == Brightness.dark
        ? scheme.onSurface.withValues(alpha: 0.65)
        : const Color(0xFF868384);
  }

  static TextStyle label(BuildContext context) => TextStyle(
        fontFamily: 'AssetLabels',
        fontSize: 12.5,
        height: 1.35,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
        color: labelColor(context),
      );
}

class AssetOverviewAmount extends StatelessWidget {
  const AssetOverviewAmount(this.value,
      {super.key, required this.size, this.weight = FontWeight.w800});

  final Decimal value;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${AssetOverviewStyle.amount(value)} 人民币',
        child: ExcludeSemantics(
            child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(AssetOverviewStyle.amount(value),
              style: TextStyle(
                  fontFamily: 'AssetAmount',
                  fontSize: size,
                  height: size < 30 ? 1 : 1.1,
                  fontWeight: weight,
                  fontFeatures: const [FontFeature('ss01')],
                  color: value < Decimal.zero
                      ? Theme.of(context).brightness == Brightness.dark
                          ? AppColors.warning
                          : Color.lerp(AppColors.warning, Colors.black, 0.4)
                      : Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.black)),
        )),
      );
}
