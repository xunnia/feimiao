import 'package:flutter/widgets.dart';

/// 分类彩色 emoji → Microsoft Fluent UI Emoji「3D」资源映射。
///
/// - value 是本地资源的「文件名主干」，对应 assets/cat_icons/{value}.png。
/// - 这些 PNG 由 CI 在构建前用 ci/fetch_fluent_icons.py 下载（本地缺失也不影响，会回退）。
/// - 找不到 PNG（未映射 / 文件未下载 / 解码失败）时，一律回退到原 emoji 文本，绝不崩。
///
/// key 用「裸 emoji」即可：查表时两边都会剥掉变体选择符(U+FE0F)，所以带不带 ️ 都能命中。
const Map<String, String> kEmojiToFluentBase = {
  // 食品餐饮
  '🍜': 'steaming_bowl',
  '🍳': 'cooking',
  '🍱': 'bento_box',
  '🍚': 'cooked_rice',
  '🧋': 'bubble_tea',
  '🍿': 'popcorn',
  '🥬': 'leafy_green',
  '🍻': 'clinking_beer_mugs',
  '🧂': 'salt',
  // 购物消费
  '🛍️': 'shopping_bags',
  '🛋️': 'couch_and_lamp',
  '💄': 'lipstick',
  '📱': 'mobile_phone',
  '🎟️': 'admission_tickets',
  '📺': 'television',
  '⌚': 'watch',
  '🧸': 'teddy_bear',
  '👟': 'running_shoe',
  '🐾': 'paw_prints',
  '📎': 'paperclip',
  '🧰': 'toolbox',
  // 出行交通
  '🚗': 'automobile',
  '🚕': 'taxi',
  '🚌': 'bus',
  '🅿️': 'p_button',
  '⛽': 'fuel_pump',
  '🚄': 'high-speed_train',
  '✈️': 'airplane',
  '🔧': 'wrench',
  // 休闲娱乐
  '🎮': 'video_game',
  '🧳': 'luggage',
  '🎤': 'microphone',
  '🏋️': 'person_lifting_weights',
  '💆': 'person_getting_massage',
  '🀄': 'mahjong_red_dragon',
  '🍸': 'cocktail_glass',
  '🎭': 'performing_arts',
  // 居家生活
  '🏠': 'house',
  '📶': 'antenna_bars',
  '💡': 'light_bulb',
  '🚰': 'potable_water',
  '🔥': 'fire',
  '🏢': 'office_building',
  '🏦': 'bank',
  '🚙': 'sport_utility_vehicle',
  '🧹': 'broom',
  // 医疗健康
  '💊': 'pill',
  '🏥': 'hospital',
  '🩺': 'stethoscope',
  // 教育学习
  '📚': 'books',
  '📖': 'open_book',
  '🎓': 'graduation_cap',
  '🖨️': 'printer',
  // 人情往来
  '🎁': 'wrapped_gift',
  '🧧': 'red_envelope',
  '🎀': 'ribbon',
  // 其他 / 收入
  '📦': 'package',
  '⚖️': 'balance_scale',
  '📉': 'chart_decreasing',
  '❤️': 'red_heart',
  '💰': 'money_bag',
  '🏆': 'trophy',
  '📈': 'chart_increasing',
  '↩️': 'right_arrow_curving_left',
  '💵': 'dollar_banknote',
};

// U+FE0F = emoji 变体选择符（让字符显示为彩色 emoji 而非黑白字形）。
String _stripVariation(String e) => e.replaceAll('️', '');

/// 把上表归一化（剥掉 U+FE0F），保证带不带变体选择符都能查到。
final Map<String, String> _normalized = {
  for (final e in kEmojiToFluentBase.entries) _stripVariation(e.key): e.value,
};

/// 某 emoji 对应的本地资源路径；无映射返回 null。
String? fluentAssetForEmoji(String emoji) {
  final base = _normalized[_stripVariation(emoji)];
  return base == null ? null : 'assets/cat_icons/$base.png';
}

/// 分类图标控件：优先渲染 Fluent 3D PNG，缺失/未映射/解码失败时回退到 emoji 文本。
///
/// 用法：把原来的 `Text(emoji, style: TextStyle(fontSize: n))` 换成
/// `CategoryIcon(emoji, size: n)` 即可。
class CategoryIcon extends StatelessWidget {
  final String emoji;
  final double size;

  const CategoryIcon(this.emoji, {super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      emoji,
      style: TextStyle(fontSize: size, height: 1.0),
    );
    final asset = fluentAssetForEmoji(emoji);
    if (asset == null) return fallback;
    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      // PNG 不存在 / 未打包 / 解码失败时，安静回退到 emoji
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
