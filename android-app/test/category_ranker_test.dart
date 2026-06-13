import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/category_ranker.dart';

DateTime _date({required int day, required int hour}) =>
    DateTime(2026, 6, day, hour);

void main() {
  group('CategoryRanker', () {
    test('frequency wins', () {
      final ranked = CategoryRanker.rank(
        defaultOrder: ['dining', 'transport', 'shopping'],
        usages: [
          (category: 'shopping', date: _date(day: 1, hour: 15)),
          (category: 'shopping', date: _date(day: 2, hour: 15)),
          (category: 'transport', date: _date(day: 3, hour: 15)),
        ],
        at: _date(day: 10, hour: 15),
      );
      expect(ranked, ['shopping', 'transport', 'dining']);
    });

    test('time bucket boost beats raw frequency', () {
      // transport 用过 2 次但都在晚上；dining 只用过 1 次但和当前同为早晨时段，
      // 时段加成（+2）应让 dining 排前面。
      final ranked = CategoryRanker.rank(
        defaultOrder: ['transport', 'dining'],
        usages: [
          (category: 'transport', date: _date(day: 1, hour: 20)),
          (category: 'transport', date: _date(day: 2, hour: 20)),
          (category: 'dining', date: _date(day: 3, hour: 8)),
        ],
        at: _date(day: 10, hour: 8),
      );
      expect(ranked.first, 'dining');
    });

    test('ties keep default order', () {
      final ranked = CategoryRanker.rank(
        defaultOrder: ['a', 'b', 'c'],
        usages: [],
        at: _date(day: 1, hour: 12),
      );
      expect(ranked, ['a', 'b', 'c']);
    });

    test('time buckets', () {
      expect(CategoryRanker.timeBucket(8), 0);
      expect(CategoryRanker.timeBucket(12), 1);
      expect(CategoryRanker.timeBucket(15), 2);
      expect(CategoryRanker.timeBucket(19), 3);
      expect(CategoryRanker.timeBucket(23), 4);
      expect(CategoryRanker.timeBucket(2), 4);
    });
  });
}
