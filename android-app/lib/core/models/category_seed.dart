import 'transaction_kind.dart';

/// 预置分类（两级：大类 + 子类）。
///
/// - 大类：parentKey == null（如 食品餐饮 / 购物消费）。
/// - 子类：parentKey 指向所属大类的 key（如 dining_breakfast→dining）。
/// - 图标统一用 emoji（彩色），不再依赖 Material IconData。
/// - key 稳定不变，用于排序学习、导入匹配、迁移定位。
class CategorySeed {
  final String key;
  final String nameZh;
  final String nameEn;

  /// 分类 emoji（彩色图标渲染 + Fluent 3D 兜底）。
  final String emoji;
  final TransactionKind kind;

  /// 所属大类 key；null 表示自身就是大类。
  final String? parentKey;

  const CategorySeed({
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.emoji,
    required this.kind,
    this.parentKey,
  });

  bool get isTopLevel => parentKey == null;

  String localizedName(String languageCode) =>
      languageCode.toLowerCase().startsWith('zh') ? nameZh : nameEn;

  /// 兜底分类，导入/解析匹配不到分类时使用。
  static const String fallbackExpenseKey = 'other';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategorySeed && key == other.key;

  @override
  int get hashCode => key.hashCode;

  // ───────────────────────── 支出：大类 + 子类 ─────────────────────────
  static const List<CategorySeed> expenses = [
    // 食品餐饮
    CategorySeed(key: 'dining', nameZh: '食品餐饮', nameEn: 'Food', emoji: '🍜', kind: TransactionKind.expense),
    CategorySeed(key: 'dining_breakfast', nameZh: '早餐', nameEn: 'Breakfast', emoji: '🍳', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_lunch', nameZh: '午餐', nameEn: 'Lunch', emoji: '🍱', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_dinner', nameZh: '晚餐', nameEn: 'Dinner', emoji: '🍚', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_drink', nameZh: '饮料酒水', nameEn: 'Drinks', emoji: '🧋', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_snack', nameZh: '休闲零食', nameEn: 'Snacks', emoji: '🍿', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'groceries', nameZh: '生鲜食品', nameEn: 'Groceries', emoji: '🥬', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_treat', nameZh: '请客吃饭', nameEn: 'Treat', emoji: '🍻', kind: TransactionKind.expense, parentKey: 'dining'),
    CategorySeed(key: 'dining_cook', nameZh: '粮油调味', nameEn: 'Cooking', emoji: '🧂', kind: TransactionKind.expense, parentKey: 'dining'),

    // 购物消费
    CategorySeed(key: 'shopping', nameZh: '购物消费', nameEn: 'Shopping', emoji: '🛍️', kind: TransactionKind.expense),
    CategorySeed(key: 'shop_home', nameZh: '日常家居', nameEn: 'Home', emoji: '🛋️', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_beauty', nameZh: '个护美妆', nameEn: 'Beauty', emoji: '💄', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_digital', nameZh: '手机数码', nameEn: 'Digital', emoji: '📱', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'subscription', nameZh: '虚拟充值', nameEn: 'Top-up', emoji: '🎟️', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_appliance', nameZh: '生活电器', nameEn: 'Appliances', emoji: '📺', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_watch', nameZh: '配饰腕表', nameEn: 'Accessories', emoji: '⌚', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_baby', nameZh: '母婴玩具', nameEn: 'Baby', emoji: '🧸', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_clothes', nameZh: '服饰运动', nameEn: 'Clothing', emoji: '👟', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'pets', nameZh: '宠物用品', nameEn: 'Pets', emoji: '🐾', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_office', nameZh: '办公用品', nameEn: 'Office', emoji: '📎', kind: TransactionKind.expense, parentKey: 'shopping'),
    CategorySeed(key: 'shop_deco', nameZh: '装修装饰', nameEn: 'Decor', emoji: '🧰', kind: TransactionKind.expense, parentKey: 'shopping'),

    // 出行交通
    CategorySeed(key: 'transport', nameZh: '出行交通', nameEn: 'Transport', emoji: '🚗', kind: TransactionKind.expense),
    CategorySeed(key: 'trans_taxi', nameZh: '打车', nameEn: 'Taxi', emoji: '🚕', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_public', nameZh: '公共交通', nameEn: 'Transit', emoji: '🚌', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_park', nameZh: '停车费', nameEn: 'Parking', emoji: '🅿️', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_fuel', nameZh: '加油', nameEn: 'Fuel', emoji: '⛽', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_train', nameZh: '火车', nameEn: 'Train', emoji: '🚄', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_flight', nameZh: '飞机', nameEn: 'Flight', emoji: '✈️', kind: TransactionKind.expense, parentKey: 'transport'),
    CategorySeed(key: 'trans_repair', nameZh: '保养修车', nameEn: 'Car Service', emoji: '🔧', kind: TransactionKind.expense, parentKey: 'transport'),

    // 休闲娱乐
    CategorySeed(key: 'entertainment', nameZh: '休闲娱乐', nameEn: 'Leisure', emoji: '🎮', kind: TransactionKind.expense),
    CategorySeed(key: 'travel', nameZh: '旅游度假', nameEn: 'Travel', emoji: '🧳', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_movie', nameZh: '电影唱歌', nameEn: 'Movie/KTV', emoji: '🎤', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_sport', nameZh: '运动健身', nameEn: 'Sports', emoji: '🏋️', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_spa', nameZh: '足浴按摩', nameEn: 'Spa', emoji: '💆', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_game', nameZh: '棋牌桌游', nameEn: 'Games', emoji: '🀄', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_bar', nameZh: '酒吧', nameEn: 'Bar', emoji: '🍸', kind: TransactionKind.expense, parentKey: 'entertainment'),
    CategorySeed(key: 'ent_show', nameZh: '演出', nameEn: 'Show', emoji: '🎭', kind: TransactionKind.expense, parentKey: 'entertainment'),

    // 居家生活
    CategorySeed(key: 'housing', nameZh: '居家生活', nameEn: 'Living', emoji: '🏠', kind: TransactionKind.expense),
    CategorySeed(key: 'house_phone', nameZh: '话费宽带', nameEn: 'Phone/Net', emoji: '📶', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'utilities', nameZh: '电费', nameEn: 'Electricity', emoji: '💡', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_water', nameZh: '水费', nameEn: 'Water', emoji: '🚰', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_gas', nameZh: '燃气费', nameEn: 'Gas', emoji: '🔥', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_property', nameZh: '物业费', nameEn: 'Property', emoji: '🏢', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_rent', nameZh: '房租还贷', nameEn: 'Rent/Loan', emoji: '🏦', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_park', nameZh: '车位费', nameEn: 'Parking Lot', emoji: '🚙', kind: TransactionKind.expense, parentKey: 'housing'),
    CategorySeed(key: 'house_clean', nameZh: '家政清洁', nameEn: 'Cleaning', emoji: '🧹', kind: TransactionKind.expense, parentKey: 'housing'),

    // 医疗健康
    CategorySeed(key: 'medical', nameZh: '医疗健康', nameEn: 'Medical', emoji: '💊', kind: TransactionKind.expense),
    CategorySeed(key: 'med_drug', nameZh: '药品', nameEn: 'Medicine', emoji: '💊', kind: TransactionKind.expense, parentKey: 'medical'),
    CategorySeed(key: 'med_clinic', nameZh: '门诊', nameEn: 'Clinic', emoji: '🏥', kind: TransactionKind.expense, parentKey: 'medical'),
    CategorySeed(key: 'med_checkup', nameZh: '体检', nameEn: 'Checkup', emoji: '🩺', kind: TransactionKind.expense, parentKey: 'medical'),

    // 教育学习
    CategorySeed(key: 'education', nameZh: '教育学习', nameEn: 'Education', emoji: '📚', kind: TransactionKind.expense),
    CategorySeed(key: 'edu_book', nameZh: '书籍', nameEn: 'Books', emoji: '📖', kind: TransactionKind.expense, parentKey: 'education'),
    CategorySeed(key: 'edu_course', nameZh: '课程', nameEn: 'Course', emoji: '🎓', kind: TransactionKind.expense, parentKey: 'education'),
    CategorySeed(key: 'edu_print', nameZh: '文具打印', nameEn: 'Stationery', emoji: '🖨️', kind: TransactionKind.expense, parentKey: 'education'),

    // 人情往来
    CategorySeed(key: 'gifts', nameZh: '人情往来', nameEn: 'Gifts', emoji: '🎁', kind: TransactionKind.expense),
    CategorySeed(key: 'gift_red', nameZh: '随礼红包', nameEn: 'Gift Money', emoji: '🧧', kind: TransactionKind.expense, parentKey: 'gifts'),
    CategorySeed(key: 'gift_present', nameZh: '礼物', nameEn: 'Present', emoji: '🎀', kind: TransactionKind.expense, parentKey: 'gifts'),

    // 其他
    CategorySeed(key: 'other', nameZh: '其他', nameEn: 'Other', emoji: '📦', kind: TransactionKind.expense),
    CategorySeed(key: 'other_fine', nameZh: '罚款赔偿', nameEn: 'Fine', emoji: '⚖️', kind: TransactionKind.expense, parentKey: 'other'),
    CategorySeed(key: 'other_invest', nameZh: '理财支出', nameEn: 'Invest Out', emoji: '📉', kind: TransactionKind.expense, parentKey: 'other'),
    CategorySeed(key: 'other_charity', nameZh: '慈善捐助', nameEn: 'Charity', emoji: '❤️', kind: TransactionKind.expense, parentKey: 'other'),
  ];

  // ───────────────────────── 收入：仅大类 ─────────────────────────
  static const List<CategorySeed> incomes = [
    CategorySeed(key: 'salary', nameZh: '工资', nameEn: 'Salary', emoji: '💰', kind: TransactionKind.income),
    CategorySeed(key: 'bonus', nameZh: '奖金', nameEn: 'Bonus', emoji: '🏆', kind: TransactionKind.income),
    CategorySeed(key: 'investment', nameZh: '理财', nameEn: 'Investment', emoji: '📈', kind: TransactionKind.income),
    CategorySeed(key: 'redPacket', nameZh: '红包', nameEn: 'Red Packet', emoji: '🧧', kind: TransactionKind.income),
    CategorySeed(key: 'refund', nameZh: '退款', nameEn: 'Refund', emoji: '↩️', kind: TransactionKind.income),
    CategorySeed(key: 'otherIncome', nameZh: '其他', nameEn: 'Other', emoji: '💵', kind: TransactionKind.income),
  ];

  static List<CategorySeed> get all => [...expenses, ...incomes];

  /// 按 key 查种子。
  static CategorySeed? byKey(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 某 key 的 emoji（找不到给标签兜底）。
  static String emojiOf(String? key) =>
      key == null ? '🏷️' : (byKey(key)?.emoji ?? '🏷️');
}
