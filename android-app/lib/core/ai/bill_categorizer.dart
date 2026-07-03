import '../models/transaction_kind.dart';
import 'merchant_category.dart';
import 'natural_language_entry_parser.dart';

/// 分类置信度：高=可静默入库；中=较可信；低=拿不准，UI 可标「待确认」。
enum CatConfidence { high, medium, low }

class CatGuess {
  final String? key;
  final CatConfidence confidence;
  const CatGuess(this.key, this.confidence);
  static const none = CatGuess(null, CatConfidence.low);
  bool get isEmpty => key == null;
}

/// 账单/AI 记账的分类大脑（纯逻辑）。
///
/// 核心认知：**分类取决于「买了什么」，不是「谁卖的」。**
/// 京东/淘宝/拼多多/美团是「万能平台」，商户名几乎零信息，必须看商品；
/// 瑞幸/滴滴/中国电信是「决定性商户」，商户名本身就锁死分类。
/// 所以按商户品类唯一性分流处理，并给出置信度。
class BillCategorizer {
  BillCategorizer._();

  /// 万能平台 → 其自然的**顶级**默认分类（子类靠商品细化）。
  /// 平台默认只落大类，永远是对的（京东买啥都算购物）；不落子类，避免学错。
  static const Map<String, String> platformDefault = {
    '京东': 'shopping', '淘宝': 'shopping', '天猫': 'shopping',
    '拼多多': 'shopping', '苏宁': 'shopping', '唯品会': 'shopping',
    '闲鱼': 'shopping', '得物': 'shopping', '1688': 'shopping',
    '美团': 'dining', '饿了么': 'dining',
    '抖音': 'shopping', '快手': 'shopping',
    // 支付宝/微信 转账 之类不给默认（信息不足，交给用户）
  };

  /// 从脏「交易对方」里提炼稳定的商户主体：剥订单号/长数字/平台后缀/备注前缀。
  /// 「京东-订单编号349126…」→「京东」；「拼多多平台商户」→「拼多多」。
  static String normalizeMerchant(String raw) {
    var s = raw.trim();
    // 收款/转账备注整段丢弃（"收款方备注:二维码收款" 之类）
    s = s.replaceAll(RegExp(r'(收款方备注|转账备注|备注)[:：].*$'), '');
    // 平台/退款/扫码 等噪声后缀
    s = s.replaceAll(
        RegExp(r'商城平台商户|平台商户|旗舰店|官方旗舰店|-?退款|扫二维码付款|散单'), '');
    // 「订单编号xxx」「订单-xxx」「订单号xxx」
    s = s.replaceAll(RegExp(r'订单\s*(编号|号)?\s*[-:：]?\s*[A-Za-z0-9]+'), '');
    // 剩下的长数字/单号尾巴
    s = s.replaceAll(RegExp(r'[-_·:：]?\s*[A-Za-z]*\d{5,}[A-Za-z0-9]*'), '');
    // 去掉首尾残留的分隔符/空格（如 "京东-" 的尾 dash）
    s = s.replaceAll(RegExp(r'^[-_·:：\s]+|[-_·:：\s]+$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// 命中的平台名（normalizeMerchant 后的文本里包含某平台关键词），无则 null。
  static String? matchedPlatform(String merchant) {
    for (final p in platformDefault.keys) {
      if (merchant.contains(p)) return p;
    }
    return null;
  }

  /// 分类核心。给交易对方 + 商品 + 兜底备注 + 收支方向，返回 (分类key, 置信度)。
  /// 优先级：商品关键词 > 决定性商户 > 平台顶级默认 > 兜底备注 > 无。
  static CatGuess classify({
    required String merchant,
    required String product,
    required String note,
    required TransactionKind kind,
  }) {
    // 1) 商品最能说明买了什么（"文印中心"→打印、"麦当劳麦咖啡"→饮料）。
    final prodKey = _fromText(product, kind);
    if (prodKey != null) return CatGuess(prodKey, CatConfidence.high);

    final m = normalizeMerchant(merchant);
    final platform = matchedPlatform(m);

    if (platform == null) {
      // 2) 决定性商户：非平台时商户名可信（瑞幸/滴滴/中国电信…）。
      final mKey = _fromText(m, kind);
      if (mKey != null) return CatGuess(mKey, CatConfidence.high);
    } else {
      // 3) 平台商户：只落安全的顶级默认（京东→购物、美团→餐饮）。
      return CatGuess(platformDefault[platform], CatConfidence.medium);
    }

    // 4) 兜底：整条备注碰运气（低置信，UI 可标待确认）。
    final nKey = _fromText(note, kind);
    if (nKey != null) return CatGuess(nKey, CatConfidence.low);
    return CatGuess.none;
  }

  /// 学习键：决定性商户学「商户主体」（一次改，以后同商户都对）；
  /// 平台商户不学商户（会把"京东→数码"错学成铁律），返回 null 表示不学商户级。
  static String? learnKeyFor(String merchant) {
    final m = normalizeMerchant(merchant);
    if (m.isEmpty || matchedPlatform(m) != null) return null;
    return m;
  }

  static String? _fromText(String text, TransactionKind kind) {
    if (text.trim().isEmpty) return null;
    return MerchantCategory.classify(text, kind) ??
        NaturalLanguageEntryParser.guessCategory(text, kind: kind);
  }
}
