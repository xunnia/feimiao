import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 拥有「自有 iOS 风 SVG 图标」的分类 key 全集。
/// 由图标生成器产出（assets/cat_icons/{key}.svg）。不在此集合里的 key
/// （例如用户自建分类、标签）会自动回退到彩色 emoji，绝不崩。
const Set<String> kSvgCategoryKeys = {
  'dining', 'dining_breakfast', 'dining_lunch', 'dining_dinner', 'dining_drink',
  'dining_snack', 'groceries', 'dining_treat', 'dining_cook',
  'shopping', 'shop_home', 'shop_beauty', 'shop_digital', 'subscription',
  'shop_appliance', 'shop_watch', 'shop_baby', 'shop_clothes', 'pets',
  'shop_office', 'shop_deco',
  'transport', 'trans_taxi', 'trans_public', 'trans_park', 'trans_fuel',
  'trans_train', 'trans_flight', 'trans_repair',
  'entertainment', 'travel', 'ent_movie', 'ent_sport', 'ent_spa', 'ent_game',
  'ent_bar', 'ent_show',
  'housing', 'house_phone', 'utilities', 'house_water', 'house_gas',
  'house_property', 'house_rent', 'house_park', 'house_clean',
  'medical', 'med_drug', 'med_clinic', 'med_checkup',
  'education', 'edu_book', 'edu_course', 'edu_print',
  'gifts', 'gift_red', 'gift_present',
  'other', 'other_fine', 'other_invest', 'other_charity',
  'salary', 'bonus', 'investment', 'redPacket', 'refund', 'otherIncome',
};

/// 分类图标控件：优先渲染自有 iOS 风 SVG（圆角方块 + 品类色 + 白色图形）；
/// 没有对应 SVG 时回退到原彩色 emoji 文本，保证永不崩、永不白屏。
///
/// 用法：`CatIcon(categoryKey: c.key, emoji: CategorySeed.emojiOf(c.key), size: 44)`
class CatIcon extends StatelessWidget {
  final String categoryKey;
  final String emoji;
  final double size;

  const CatIcon({
    super.key,
    required this.categoryKey,
    required this.emoji,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (kSvgCategoryKeys.contains(categoryKey)) {
      return SvgPicture.asset(
        'assets/cat_icons/$categoryKey.svg',
        width: size,
        height: size,
        placeholderBuilder: (_) => SizedBox(width: size, height: size),
      );
    }
    // 回退：彩色 emoji 居中
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.64, height: 1.0)),
      ),
    );
  }
}
