import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/query_range.dart';

void main() {
  final now = DateTime(2026, 7, 3); // 周五

  group('QueryRange.parse', () {
    test('上个月 = 上月整月', () {
      final r = QueryRange.parse('上个月吃饭花了多少', now)!;
      expect(r.start, DateTime(2026, 6, 1));
      expect(r.end, DateTime(2026, 6, 30));
    });

    test('本月 = 1号到今天', () {
      final r = QueryRange.parse('这个月超支了吗', now)!;
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.end, DateTime(2026, 7, 3));
    });

    test('今年 / 去年', () {
      final y = QueryRange.parse('今年一共花了多少', now)!;
      expect(y.start, DateTime(2026, 1, 1));
      expect(y.end, DateTime(2026, 7, 3));
      final ly = QueryRange.parse('去年的收入', now)!;
      expect(ly.start, DateTime(2025, 1, 1));
      expect(ly.end, DateTime(2025, 12, 31));
    });

    test('本周从周一起；上周整周', () {
      final w = QueryRange.parse('本周花销', now)!;
      expect(w.start, DateTime(2026, 6, 29)); // 周一
      expect(w.end, DateTime(2026, 7, 3));
      final lw = QueryRange.parse('上周呢', now)!;
      expect(lw.start, DateTime(2026, 6, 22));
      expect(lw.end, DateTime(2026, 6, 28));
    });

    test('数字月/中文月；未到的月份按去年算', () {
      final m5 = QueryRange.parse('5月餐饮多少钱', now)!;
      expect(m5.start, DateTime(2026, 5, 1));
      expect(m5.end, DateTime(2026, 5, 31));
      final cn = QueryRange.parse('五月餐饮多少钱', now)!;
      expect(cn.start, DateTime(2026, 5, 1));
      // 11 月还没到 → 去年 11 月。
      final m11 = QueryRange.parse('11月花了多少', now)!;
      expect(m11.start, DateTime(2025, 11, 1));
      expect(m11.end, DateTime(2025, 11, 30));
    });

    test('「今年X月」「去年X月」是单月，不是整年（整年分支不得抢先）', () {
      final r = QueryRange.parse('今年3月花了多少', now)!;
      expect(r.start, DateTime(2026, 3, 1));
      expect(r.end, DateTime(2026, 3, 31));
      // 明确说了「今年」，未到的月份也不回退去年。
      final m11 = QueryRange.parse('今年11月预算多少', now)!;
      expect(m11.start, DateTime(2026, 11, 1));
      final last = QueryRange.parse('去年5月吃饭多少', now)!;
      expect(last.start, DateTime(2025, 5, 1));
      expect(last.end, DateTime(2025, 5, 31));
      // 纯「今年/去年」仍是整年。
      final y = QueryRange.parse('今年一共花了多少', now)!;
      expect(y.start, DateTime(2026, 1, 1));
      final ly = QueryRange.parse('去年总支出', now)!;
      expect(ly.start, DateTime(2025, 1, 1));
      expect(ly.end, DateTime(2025, 12, 31));
    });

    test('「今年X月到Y月」跨月区间不得收窄成单月（回归 M21）', () {
      // 「今年1月到6月」：收窄成 1 月会算错，退回整年范围（超集覆盖 1-6 月）。
      final r = QueryRange.parse('今年1月到6月花了多少', now)!;
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2026, 7, 3));
      expect(r.covers(DateTime(2026, 6, 15)), isTrue);
      // 「1-6月」只有一个「月」字的区间写法同样不收窄。
      final dash = QueryRange.parse('今年1-6月支出多少', now)!;
      expect(dash.start, DateTime(2026, 1, 1));
      expect(dash.covers(DateTime(2026, 1, 10)), isTrue);
      // 并列对比：两个月份出现时不收窄（先命中「今年」→ 整年）。
      final cmp = QueryRange.parse('去年3月和今年5月对比', now)!;
      expect(cmp.start, DateTime(2026, 1, 1));
      expect(cmp.covers(DateTime(2026, 5, 15)), isTrue);
      // 单个月份保持现有行为：仍收窄成单月。
      final single = QueryRange.parse('今年3月花了多少', now)!;
      expect(single.start, DateTime(2026, 3, 1));
      expect(single.end, DateTime(2026, 3, 31));
    });

    test('近 N 天含今天', () {
      final r = QueryRange.parse('最近7天的支出', now)!;
      expect(r.start, DateTime(2026, 6, 27));
      expect(r.end, DateTime(2026, 7, 3));
    });

    test('无时间词返回 null', () {
      expect(QueryRange.parse('我最大的一笔支出是什么', now), isNull);
      expect(QueryRange.parse('记一笔午饭20', now), isNull);
    });

    test('covers 忽略时间部分', () {
      final r = QueryRange.parse('上个月', now)!;
      expect(r.covers(DateTime(2026, 6, 30, 23, 59)), isTrue);
      expect(r.covers(DateTime(2026, 7, 1, 0, 1)), isFalse);
    });
  });
}
