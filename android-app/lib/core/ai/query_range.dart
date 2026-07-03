/// 从查账问题里解析时间范围（纯本地规则）：
/// 「上个月吃饭花了多少」→ 上个月整月；「今年收入」→ 今年至今。
/// 解析出来后 AI 只喂该范围的账目——比固定喂最近 80 条准得多（账多时
/// 上个月的数据可能根本不在最近 80 条里）。解析不出返回 null，走默认。
class QueryRange {
  final DateTime start; // 含当天 0 点
  final DateTime end; // 含当天，调用方按「不晚于 end 当天」过滤

  const QueryRange(this.start, this.end);

  static const _cnDigits = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6,
    '七': 7, '八': 8, '九': 9, '十': 10, '十一': 11, '十二': 12,
  };

  static QueryRange? parse(String question, DateTime now) {
    final q = question.trim();
    final today = DateTime(now.year, now.month, now.day);

    if (q.contains('今天')) return QueryRange(today, today);
    if (q.contains('昨天')) {
      final d = today.subtract(const Duration(days: 1));
      return QueryRange(d, d);
    }
    if (q.contains('本周') || q.contains('这周') || q.contains('这个星期')) {
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return QueryRange(monday, today);
    }
    if (q.contains('上周') || q.contains('上个星期')) {
      final monday =
          today.subtract(Duration(days: today.weekday - 1 + 7));
      return QueryRange(monday, monday.add(const Duration(days: 6)));
    }
    if (q.contains('本月') || q.contains('这个月') || q.contains('这月')) {
      return QueryRange(DateTime(now.year, now.month, 1), today);
    }
    if (q.contains('上个月') || q.contains('上月')) {
      final first = DateTime(now.year, now.month - 1, 1);
      return QueryRange(first, DateTime(now.year, now.month, 0));
    }
    if (q.contains('今年')) {
      return QueryRange(DateTime(now.year, 1, 1), today);
    }
    if (q.contains('去年')) {
      return QueryRange(DateTime(now.year - 1, 1, 1),
          DateTime(now.year - 1, 12, 31));
    }

    // 最近 / 近 N 天
    final recent = RegExp(r'[最]?近\s*(\d{1,3})\s*天').firstMatch(q);
    if (recent != null) {
      final n = int.parse(recent.group(1)!).clamp(1, 366);
      return QueryRange(
          today.subtract(Duration(days: n - 1)), today);
    }

    // 「5月」「五月」「2026年5月」：默认今年；还没到的月份按去年算。
    final m = RegExp(r'(?:(\d{4})\s*年)?\s*(\d{1,2}|[一二三四五六七八九十]{1,2})\s*月(?!份?底|初)')
        .firstMatch(q);
    if (m != null) {
      final month = int.tryParse(m.group(2)!) ?? _cnDigits[m.group(2)!] ?? 0;
      if (month >= 1 && month <= 12) {
        var year = int.tryParse(m.group(1) ?? '') ?? now.year;
        if (m.group(1) == null && month > now.month) year -= 1;
        return QueryRange(
            DateTime(year, month, 1), DateTime(year, month + 1, 0));
      }
    }
    return null;
  }

  /// [d] 是否落在范围内（忽略时间部分）。
  bool covers(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}
