import 'package:flutter/material.dart';
import 'transaction_kind.dart';

/// 预置分类（中英双语），首次启动时写入数据库。
/// SF Symbols 图标名已映射为 Material Icons 等价图标。
class CategorySeed {
  /// 稳定标识，不随语言变化，用于排序学习与导入匹配。
  final String key;
  final String nameZh;
  final String nameEn;

  /// Material Icons 图标。
  final IconData icon;
  final TransactionKind kind;

  const CategorySeed({
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.icon,
    required this.kind,
  });

  String localizedName(String languageCode) =>
      languageCode.toLowerCase().startsWith('zh') ? nameZh : nameEn;

  /// 兜底分类，导入账单匹配不到分类时使用。
  static const String fallbackExpenseKey = 'other';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategorySeed &&
          key == other.key &&
          nameZh == other.nameZh &&
          nameEn == other.nameEn &&
          icon == other.icon &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(key, nameZh, nameEn, icon, kind);

  // SF Symbol -> Material Icons 映射说明：
  // fork.knife        -> Icons.restaurant
  // cart              -> Icons.shopping_cart
  // bus               -> Icons.directions_bus
  // bag               -> Icons.shopping_bag
  // gamecontroller    -> Icons.sports_esports
  // house             -> Icons.home
  // bolt              -> Icons.bolt
  // cross.case        -> Icons.medical_services
  // book              -> Icons.menu_book
  // airplane          -> Icons.flight
  // pawprint          -> Icons.pets
  // gift              -> Icons.card_giftcard
  // arrow.triangle.2.circlepath -> Icons.autorenew
  // ellipsis.circle   -> Icons.more_horiz
  // banknote          -> Icons.payments
  // star              -> Icons.star
  // chart.line.uptrend.xyaxis -> Icons.trending_up
  // envelope          -> Icons.mail
  // arrow.uturn.backward -> Icons.undo
  // plus.circle       -> Icons.add_circle

  static const List<CategorySeed> expenses = [
    CategorySeed(key: 'dining', nameZh: '餐饮', nameEn: 'Dining', icon: Icons.restaurant, kind: TransactionKind.expense),
    CategorySeed(key: 'groceries', nameZh: '买菜超市', nameEn: 'Groceries', icon: Icons.shopping_cart, kind: TransactionKind.expense),
    CategorySeed(key: 'transport', nameZh: '交通', nameEn: 'Transport', icon: Icons.directions_bus, kind: TransactionKind.expense),
    CategorySeed(key: 'shopping', nameZh: '购物', nameEn: 'Shopping', icon: Icons.shopping_bag, kind: TransactionKind.expense),
    CategorySeed(key: 'entertainment', nameZh: '娱乐', nameEn: 'Entertainment', icon: Icons.sports_esports, kind: TransactionKind.expense),
    CategorySeed(key: 'housing', nameZh: '住房', nameEn: 'Housing', icon: Icons.home, kind: TransactionKind.expense),
    CategorySeed(key: 'utilities', nameZh: '水电网', nameEn: 'Utilities', icon: Icons.bolt, kind: TransactionKind.expense),
    CategorySeed(key: 'medical', nameZh: '医疗', nameEn: 'Medical', icon: Icons.medical_services, kind: TransactionKind.expense),
    CategorySeed(key: 'education', nameZh: '学习', nameEn: 'Education', icon: Icons.menu_book, kind: TransactionKind.expense),
    CategorySeed(key: 'travel', nameZh: '旅行', nameEn: 'Travel', icon: Icons.flight, kind: TransactionKind.expense),
    CategorySeed(key: 'pets', nameZh: '宠物', nameEn: 'Pets', icon: Icons.pets, kind: TransactionKind.expense),
    CategorySeed(key: 'gifts', nameZh: '人情', nameEn: 'Gifts', icon: Icons.card_giftcard, kind: TransactionKind.expense),
    CategorySeed(key: 'subscription', nameZh: '订阅', nameEn: 'Subscriptions', icon: Icons.autorenew, kind: TransactionKind.expense),
    CategorySeed(key: 'other', nameZh: '其他', nameEn: 'Other', icon: Icons.more_horiz, kind: TransactionKind.expense),
  ];

  static const List<CategorySeed> incomes = [
    CategorySeed(key: 'salary', nameZh: '工资', nameEn: 'Salary', icon: Icons.payments, kind: TransactionKind.income),
    CategorySeed(key: 'bonus', nameZh: '奖金', nameEn: 'Bonus', icon: Icons.star, kind: TransactionKind.income),
    CategorySeed(key: 'investment', nameZh: '理财', nameEn: 'Investment', icon: Icons.trending_up, kind: TransactionKind.income),
    CategorySeed(key: 'redPacket', nameZh: '红包', nameEn: 'Red Packet', icon: Icons.mail, kind: TransactionKind.income),
    CategorySeed(key: 'refund', nameZh: '退款', nameEn: 'Refund', icon: Icons.undo, kind: TransactionKind.income),
    CategorySeed(key: 'otherIncome', nameZh: '其他', nameEn: 'Other', icon: Icons.add_circle, kind: TransactionKind.income),
  ];

  static List<CategorySeed> get all => [...expenses, ...incomes];
}
