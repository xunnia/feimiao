enum CategoryIconStyle {
  filled,
  line,
}

extension CategoryIconStyleX on CategoryIconStyle {
  String get storageKey => switch (this) {
        CategoryIconStyle.filled => 'filled',
        CategoryIconStyle.line => 'line',
      };

  String get label => switch (this) {
        CategoryIconStyle.filled => '面性',
        CategoryIconStyle.line => '线性',
      };

  String get assetDir => switch (this) {
        CategoryIconStyle.filled => 'assets/cat_icons_filled',
        CategoryIconStyle.line => 'assets/cat_icons_line',
      };

  static CategoryIconStyle fromStorage(String? value) {
    for (final style in CategoryIconStyle.values) {
      if (style.storageKey == value) return style;
    }
    return CategoryIconStyle.filled;
  }
}
