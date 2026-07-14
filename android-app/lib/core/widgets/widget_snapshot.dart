import 'package:decimal/decimal.dart';

class FeimiaoWidgetCategorySnapshot {
  final int id;
  final String name;
  final String amountText;
  final String percentText;
  final int progress;
  final int count;
  final int colorValue;
  final String semanticText;

  const FeimiaoWidgetCategorySnapshot({
    required this.id,
    required this.name,
    required this.amountText,
    required this.percentText,
    required this.progress,
    required this.count,
    required this.colorValue,
    required this.semanticText,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'amountText': amountText,
        'percentText': percentText,
        'progress': progress,
        'count': count,
        'colorValue': colorValue,
        'semanticText': semanticText,
      };
}

class FeimiaoWidgetMetricSnapshot {
  final String label;
  final String amountText;
  final String semanticText;

  const FeimiaoWidgetMetricSnapshot({
    required this.label,
    required this.amountText,
    required this.semanticText,
  });

  Map<String, Object?> toJson() => {
        'label': label,
        'amountText': amountText,
        'semanticText': semanticText,
      };
}

class FeimiaoWidgetProgressSnapshot {
  final bool visible;
  final int value;
  final String status;

  const FeimiaoWidgetProgressSnapshot({
    required this.visible,
    required this.value,
    required this.status,
  });

  Map<String, Object?> toJson() => {
        'visible': visible,
        'value': value,
        'status': status,
      };
}

class FeimiaoWidgetOverviewSnapshot {
  final String mode;
  final String title;
  final FeimiaoWidgetMetricSnapshot primary;
  final List<FeimiaoWidgetMetricSnapshot> secondary;
  final FeimiaoWidgetProgressSnapshot progress;

  const FeimiaoWidgetOverviewSnapshot({
    required this.mode,
    required this.title,
    required this.primary,
    required this.secondary,
    required this.progress,
  });

  Map<String, Object?> toJson() => {
        'mode': mode,
        'title': title,
        'primary': primary.toJson(),
        'secondary': secondary.map((item) => item.toJson()).toList(),
        'progress': progress.toJson(),
      };
}

class FeimiaoWidgetPaceMonthSnapshot {
  final String label;
  final double fullValue;
  final double sameProgressValue;
  final bool isCurrent;

  const FeimiaoWidgetPaceMonthSnapshot({
    required this.label,
    required this.fullValue,
    required this.sameProgressValue,
    required this.isCurrent,
  });

  Map<String, Object?> toJson() => {
        'label': label,
        'fullValue': fullValue,
        'sameProgressValue': sameProgressValue,
        'isCurrent': isCurrent,
      };
}

class FeimiaoWidgetPaceSnapshot {
  final String state;
  final String title;
  final FeimiaoWidgetMetricSnapshot average;
  final FeimiaoWidgetMetricSnapshot current;
  final double averageValue;
  final double currentValue;
  final double maxChartValue;
  final List<FeimiaoWidgetPaceMonthSnapshot> months;
  final String semanticText;

  const FeimiaoWidgetPaceSnapshot({
    required this.state,
    required this.title,
    required this.average,
    required this.current,
    required this.averageValue,
    required this.currentValue,
    required this.maxChartValue,
    required this.months,
    required this.semanticText,
  });

  Map<String, Object?> toJson() => {
        'state': state,
        'title': title,
        'average': {
          ...average.toJson(),
          'value': averageValue,
        },
        'current': {
          ...current.toJson(),
          'value': currentValue,
        },
        'chart': {
          'maxValue': maxChartValue,
          'months': months.map((item) => item.toJson()).toList(),
        },
        'semanticText': semanticText,
      };
}

class FeimiaoWidgetCategoriesSnapshot {
  final String state;
  final String title;
  final List<FeimiaoWidgetCategorySnapshot> items;
  final String showAllText;

  const FeimiaoWidgetCategoriesSnapshot({
    required this.state,
    required this.title,
    required this.items,
    required this.showAllText,
  });

  Map<String, Object?> toJson() => {
        'state': state,
        'title': title,
        'items': items.map((item) => item.toJson()).toList(),
        'showAllText': showAllText,
      };
}

class FeimiaoWidgetQuickAddSnapshot {
  final String title;
  final String subtitle;
  final String openMode;

  const FeimiaoWidgetQuickAddSnapshot({
    required this.title,
    required this.subtitle,
    required this.openMode,
  });

  Map<String, Object?> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'openMode': openMode,
      };
}

class FeimiaoWidgetSnapshot {
  static const int currentSchemaVersion = 2;

  final int generatedAtMs;
  final int? bookId;
  final String bookName;
  final String dateText;
  final int year;
  final int month;
  final int day;
  final String todayExpenseText;
  final String monthExpenseText;
  final String monthIncomeText;
  final String balanceText;
  final String budgetTitle;
  final String budgetText;
  final String budgetHint;
  final int budgetProgress;
  final String paceCaption;
  final String paceAverageText;
  final int paceThisProgress;
  final int paceAverageProgress;
  final bool privacyMode;
  final List<FeimiaoWidgetCategorySnapshot> categories;
  final FeimiaoWidgetOverviewSnapshot overview;
  final FeimiaoWidgetPaceSnapshot pace;
  final FeimiaoWidgetCategoriesSnapshot categoriesModule;
  final FeimiaoWidgetQuickAddSnapshot quickAdd;

  const FeimiaoWidgetSnapshot({
    required this.generatedAtMs,
    required this.bookId,
    required this.bookName,
    required this.dateText,
    required this.year,
    required this.month,
    required this.day,
    required this.todayExpenseText,
    required this.monthExpenseText,
    required this.monthIncomeText,
    required this.balanceText,
    required this.budgetTitle,
    required this.budgetText,
    required this.budgetHint,
    required this.budgetProgress,
    required this.paceCaption,
    required this.paceAverageText,
    required this.paceThisProgress,
    required this.paceAverageProgress,
    required this.privacyMode,
    required this.categories,
    required this.overview,
    required this.pace,
    required this.categoriesModule,
    required this.quickAdd,
  });

  Map<String, Object?> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'generatedAtMs': generatedAtMs,
        'book': {
          'id': bookId,
          'name': bookName,
          'scope': 'current',
        },
        'settings': {
          'privacyMode': privacyMode,
        },
        'period': {
          'year': year,
          'month': month,
          'day': day,
          'dateText': dateText,
          'monthLabel': '$month月',
          'cutoffText': '截至$month月$day日',
        },
        'modules': {
          'overview': overview.toJson(),
          'quickAdd': quickAdd.toJson(),
          'pace': pace.toJson(),
          'categories': categoriesModule.toJson(),
        },
        'extensions': <String, Object?>{},
        // V1 fallback fields. Keep these until old widgets have aged out.
        'bookName': bookName,
        'dateText': dateText,
        'todayExpenseText': todayExpenseText,
        'monthExpenseText': monthExpenseText,
        'monthIncomeText': monthIncomeText,
        'balanceText': balanceText,
        'budgetTitle': budgetTitle,
        'budgetText': budgetText,
        'budgetHint': budgetHint,
        'budgetProgress': budgetProgress,
        'paceCaption': paceCaption,
        'paceAverageText': paceAverageText,
        'paceThisProgress': paceThisProgress,
        'paceAverageProgress': paceAverageProgress,
        'privacyMode': privacyMode,
        'categories': categories.map((c) => c.toJson()).toList(),
      };
}

class WidgetCategoryTotal {
  final int id;
  final String key;
  final String name;
  final int colorValue;
  Decimal total;
  int count;

  WidgetCategoryTotal({
    required this.id,
    required this.key,
    required this.name,
    required this.colorValue,
    required this.total,
    this.count = 0,
  });
}
