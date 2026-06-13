/// 分类智能排序：按使用频率 + 当前时段匹配度对分类排序，
/// 让「早上打开 App 时早餐分类排最前」。
class CategoryRanker {
  CategoryRanker._();

  /// 把一天划分为 5 个消费时段：早(5-10)、午(10-14)、下午(14-17)、晚(17-21)、夜(21-5)。
  static int timeBucket(int hour) {
    if (hour >= 5 && hour < 10) return 0;
    if (hour >= 10 && hour < 14) return 1;
    if (hour >= 14 && hour < 17) return 2;
    if (hour >= 17 && hour < 21) return 3;
    return 4;
  }

  /// 对 [defaultOrder] 中的分类重新排序，使用记录越多、与当前时段越匹配的越靠前。
  /// 得分相同的保持 [defaultOrder] 的相对顺序。
  static List<String> rank({
    required List<String> defaultOrder,
    required List<({String category, DateTime date})> usages,
    DateTime? at,
  }) {
    final referenceDate = at ?? DateTime.now();
    final referenceBucket = timeBucket(referenceDate.hour);

    final scores = <String, double>{};
    for (final usage in usages) {
      var score = 1.0;
      if (timeBucket(usage.date.hour) == referenceBucket) {
        score += 2.0;
      }
      final diff = referenceDate.difference(usage.date).inDays;
      if (diff >= 0 && diff <= 30) {
        score += 0.5;
      }
      scores[usage.category] = (scores[usage.category] ?? 0.0) + score;
    }

    final defaultIndex = {
      for (var i = 0; i < defaultOrder.length; i++) defaultOrder[i]: i
    };

    final sorted = List<String>.from(defaultOrder)
      ..sort((a, b) {
        final scoreA = scores[a] ?? 0.0;
        final scoreB = scores[b] ?? 0.0;
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return (defaultIndex[a] ?? 999999)
            .compareTo(defaultIndex[b] ?? 999999);
      });

    return sorted;
  }
}
