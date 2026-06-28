/// 「解析更聪明」之一：按时段把笼统的「食品餐饮」细化到 早/午/晚餐。
///
/// 只在分类正好是大类 `dining`（食品餐饮）、且备注没指明具体餐次/品类时才细化，
/// 不覆盖已经具体的分类（午餐/奶茶/咖啡等），也不影响非餐饮分类。
class MealTime {
  MealTime._();

  static final RegExp _specific =
      RegExp('早餐|早饭|午餐|午饭|中午|晚餐|晚饭|夜宵|宵夜|奶茶|咖啡|饮料|零食|水果|生鲜|买菜');

  /// 返回细化后的 categoryKey（不需要细化时原样返回）。
  static String? refine(String? categoryKey, DateTime when, String note) {
    if (categoryKey != 'dining') return categoryKey;
    if (_specific.hasMatch(note)) return categoryKey;
    final h = when.hour;
    if (h >= 5 && h < 10) return 'dining_breakfast';
    if (h >= 10 && h < 15) return 'dining_lunch';
    if (h >= 16 && h < 22) return 'dining_dinner';
    return categoryKey; // 下午茶/深夜不强行归餐次
  }
}
