import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 拥有「自有 iOS 风 SVG 图标」的分类 key 全集。
/// 由图标生成器产出（assets/cat_icons/{key}.svg）。不在此集合里的 key
/// （例如用户自建分类、标签）会自动回退到彩色 emoji，绝不崩。
///
/// 注：'transfer' 不是分类，而是给「转账」交易行用的方块图标（青色双箭头）。
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
  'transfer',
  // Phase A 后补齐的新分类图标（b0703-28，同款圆角方块+品类色）。
  'shop_digital_acc', 'shop_jewelry', 'dining_tobacco', 'trans_bike',
  'car', 'car_toll', 'car_wash', 'car_tax', 'ent_photo', 'house_loan',
  'med_hospital', 'med_dental', 'med_eye', 'med_mental', 'med_beauty',
  'med_health', 'edu_tuition', 'edu_exam',
  'insurance', 'ins_car', 'ins_medical', 'ins_critical', 'ins_accident',
  'ins_life', 'ins_property', 'ins_other', 'gift_parents',
  'other_fee', 'other_tax', 'other_loss',
  'inc_salary_base', 'inc_salary_ot', 'inc_salary_allow',
  'inc_salary_commission', 'inc_bonus_year', 'inc_bonus_project',
  'inc_bonus_full', 'sideline', 'inc_parttime', 'inc_freelance', 'inc_media',
  'inc_interest', 'inc_dividend', 'inc_gain', 'inc_rent', 'pension',
  'familySupport', 'inc_rp_wx', 'inc_rp_ali', 'inc_rp_gift', 'business',
  'inc_prize', 'inc_subsidy',
};

/// 分类图标控件：优先渲染自有 iOS 风 SVG（圆角方块 + 品类色 + 白色图形）；
/// 没有对应 SVG 时回退到原彩色 emoji 文本，保证永不崩、永不白屏。
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
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.64, height: 1.0)),
      ),
    );
  }
}
