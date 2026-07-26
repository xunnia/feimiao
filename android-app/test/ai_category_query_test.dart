import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/category_query.dart';

void main() {
  const options = [
    AiCategoryOption(
        id: 1, key: 'shopping', nameZh: '购物消费', nameEn: 'Shopping'),
    AiCategoryOption(
      id: 2,
      key: 'shop_home',
      nameZh: '日常家居',
      nameEn: 'Home',
      parentKey: 'shopping',
    ),
    AiCategoryOption(
      id: 3,
      key: 'subscription',
      nameZh: '虚拟充值',
      nameEn: 'Top-up',
      parentKey: 'shopping',
    ),
    AiCategoryOption(id: 4, key: 'dining', nameZh: '食品餐饮', nameEn: 'Food'),
    AiCategoryOption(
      id: 5,
      key: 'dining_lunch',
      nameZh: '午餐',
      nameEn: 'Lunch',
      parentKey: 'dining',
    ),
  ];

  test('购物命中一级分类并包含全部子分类', () {
    final scope = resolveAiCategoryScope('这个月购物我花了多少', options)!;
    expect(scope.categoryKeys, {'shopping', 'shop_home', 'subscription'});
    expect(scope.categoryKeys, isNot(contains('dining')));
    expect(scope.labels, contains('购物消费'));
  });

  test('子分类问题只命中该子分类', () {
    final scope = resolveAiCategoryScope('本月午餐多少钱', options)!;
    expect(scope.categoryKeys, {'dining_lunch'});
  });

  test('总支出等通用词不触发分类筛选', () {
    expect(resolveAiCategoryScope('这个月总支出多少', options), isNull);
  });

  test('分类范围可同时匹配交易的 id 或 key', () {
    final scope = resolveAiCategoryScope('购物', options)!;
    expect(scope.matches(categoryId: 2), isTrue);
    expect(scope.matches(categoryKey: 'subscription'), isTrue);
    expect(scope.matches(categoryKey: 'dining_lunch'), isFalse);
  });
}
