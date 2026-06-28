import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/meal_time.dart';

void main() {
  DateTime at(int h) => DateTime(2026, 6, 28, h);

  group('MealTime.refine — 笼统餐饮按时段细化', () {
    test('早上 → 早餐', () {
      expect(MealTime.refine('dining', at(8), '吃饭'), 'dining_breakfast');
    });
    test('中午 → 午餐', () {
      expect(MealTime.refine('dining', at(12), '随便吃点'), 'dining_lunch');
    });
    test('晚上 → 晚餐', () {
      expect(MealTime.refine('dining', at(19), '聚餐吃饭'), 'dining_dinner');
    });
    test('下午茶时段(15点)不强分', () {
      expect(MealTime.refine('dining', at(15), '吃点东西'), 'dining');
    });
  });

  group('MealTime.refine — 不该动的不动', () {
    test('备注已指明餐次/品类 → 不改', () {
      expect(MealTime.refine('dining', at(8), '午餐'), 'dining');
      expect(MealTime.refine('dining', at(12), '喝奶茶'), 'dining');
    });
    test('已是具体子类 → 原样', () {
      expect(MealTime.refine('dining_lunch', at(8), 'x'), 'dining_lunch');
    });
    test('非餐饮分类 → 原样', () {
      expect(MealTime.refine('trans_taxi', at(8), '打车'), 'trans_taxi');
    });
    test('null → null', () {
      expect(MealTime.refine(null, at(8), ''), isNull);
    });
  });
}
