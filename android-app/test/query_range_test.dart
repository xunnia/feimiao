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
