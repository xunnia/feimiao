import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';
import 'entry_sanity.dart';

/// 一句话记账的解析结果。
class ParsedEntry {
  final Decimal? amount;
  final TransactionKind kind;

  /// 匹配到的分类 key（对应 CategorySeed.key），null 表示没识别出来。
  final String? categoryKey;
  final String note;
  final DateTime date;

  /// 解析置信度 0~1：高(>=0.9)可自动入库，中等需确认，低需补全。
  /// 本地规则解析默认较低（0.55），云端 LLM 按返回值。
  final double confidence;

  const ParsedEntry({
    required this.amount,
    required this.kind,
    required this.categoryKey,
    required this.note,
    required this.date,
    this.confidence = 0.7,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedEntry &&
          amount == other.amount &&
          kind == other.kind &&
          categoryKey == other.categoryKey &&
          note == other.note &&
          date == other.date &&
          confidence == other.confidence;

  @override
  int get hashCode =>
      Object.hash(amount, kind, categoryKey, note, date, confidence);
}

/// 本地规则版「一句话记账」解析器：
/// 「昨天打车23块」→ 支出 / 打车 / 23 元 / 昨天。
/// 纯本地、零网络，后续可在 App 层用云端 LLM 替换（同样产出 ParsedEntry）。
class NaturalLanguageEntryParser {
  NaturalLanguageEntryParser._();

  static ParsedEntry parse(
    String text, {
    DateTime? at,
    bool useLocalTimeZone = false,
  }) {
    final now = at ?? DateTime.now();
    final trimmed = text.trim();
    final kind = _detectKind(trimmed);
    return EntrySanity.clean(
      ParsedEntry(
        amount: extractAmount(trimmed),
        kind: kind,
        categoryKey: _detectCategory(trimmed, kind: kind),
        note: trimmed,
        date: _detectDate(trimmed, now: now),
        confidence: 0.55, // 本地规则不够确定，始终走确认
      ),
      now: now,
    );
  }

  // ---------------------------------------------------------------------------
  // 金额

  /// 提取金额。优先「X块Y」口语格式，其次带货币标记的数字，最后取最后一个数字。
  static Decimal? extractAmount(String text) {
    // "23块5" -> 23.5
    final kuaiPattern = RegExp(r'(\d+)[块元]([1-9])\b');
    final kuaiMatch = kuaiPattern.firstMatch(text);
    if (kuaiMatch != null) {
      final yuan = Decimal.tryParse(kuaiMatch.group(1)!);
      final jiao = Decimal.tryParse(kuaiMatch.group(2)!);
      if (yuan != null && jiao != null) {
        return yuan + (jiao / Decimal.fromInt(10)).toDecimal();
      }
    }

    // 带货币标记的数字：¥23.5 / 23.5元 / 23块 / 23.5刀
    final yenPattern = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
    final unitPattern = RegExp(r'(\d+(?:\.\d{1,2})?)\s*[块元刀]');
    final markedMatch =
        yenPattern.firstMatch(text) ?? unitPattern.firstMatch(text);
    if (markedMatch != null) {
      return Decimal.tryParse(markedMatch.group(1)!);
    }

    // 中文数字金额（离线/无 key 也能认）：
    // "两块五""三块五毛" → X元Y角；"三十块""一百二""一百二十元" → 整元。
    const cn = '零〇一二两三四五六七八九十百千万';
    final cnKuaiJiao =
        RegExp('([$cn]+)\\s*[块元]\\s*([一二两三四五六七八九])\\s*[毛角]?');
    final mkj = cnKuaiJiao.firstMatch(text);
    if (mkj != null) {
      final yuan = _cnToInt(mkj.group(1)!);
      final jiao = _cnToInt(mkj.group(2)!);
      if (yuan != null && jiao != null) {
        return Decimal.fromInt(yuan) +
            (Decimal.fromInt(jiao) / Decimal.fromInt(10)).toDecimal();
      }
    }
    final cnYuan = RegExp('([$cn]+)\\s*[块元]');
    final mY = cnYuan.firstMatch(text);
    if (mY != null) {
      final yuan = _cnToInt(mY.group(1)!);
      if (yuan != null) return Decimal.fromInt(yuan);
    }

    // 兜底：最后一个数字（"买了2杯咖啡58" -> 58）
    final allPattern = RegExp(r'(\d+(?:\.\d{1,2})?)');
    final allMatches = allPattern.allMatches(text).toList();
    if (allMatches.isNotEmpty) {
      return Decimal.tryParse(allMatches.last.group(1)!);
    }

    return null;
  }

  /// 中文数字 → 整数：支持 十/百/千/万 及口语省略（"一百二"=120、"一万二"=12000）。
  /// 仅接受中文数字字符，遇到其它字符返回 null。
  static int? _cnToInt(String s) {
    const digit = {
      '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3,
      '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    };
    const unit = {'十': 10, '百': 100, '千': 1000};
    if (s.isEmpty) return null;
    int section = 0; // 当前万段内累加
    int number = 0; // 待处理数字
    int result = 0; // 总和
    int lastUnit = 0; // 最近的单位（口语省略时给末位定位）
    bool bareUnits = false; // 出现「零」后，末位按个位
    bool any = false;
    for (final ch in s.split('')) {
      if (ch == '零' || ch == '〇') {
        bareUnits = true;
        number = 0;
        any = true;
      } else if (digit.containsKey(ch)) {
        number = digit[ch]!;
        any = true;
      } else if (unit.containsKey(ch)) {
        final u = unit[ch]!;
        final n = number == 0 ? 1 : number; // 十 = 一十
        section += n * u;
        lastUnit = u;
        bareUnits = false;
        number = 0;
        any = true;
      } else if (ch == '万') {
        final base = section + number; // 当前万段的值
        result += (base == 0 ? 1 : base) * 10000;
        section = 0;
        number = 0;
        lastUnit = 10000;
        bareUnits = false;
        any = true;
      } else {
        return null;
      }
    }
    if (number != 0) {
      section += (!bareUnits && lastUnit >= 10)
          ? number * (lastUnit ~/ 10) // 口语省略，如 一百「二」=120
          : number;
    }
    result += section;
    return any ? result : null;
  }

  // ---------------------------------------------------------------------------
  // 收支方向

  static TransactionKind _detectKind(String text) {
    const incomeMarkers = [
      '收入', '工资', '发薪', '奖金', '年终奖', '退款', '退了', '报销',
      '收到红包', '收红包', '分红', '利息', '卖了',
    ];
    return incomeMarkers.any(text.contains) ? TransactionKind.income : TransactionKind.expense;
  }

  // ---------------------------------------------------------------------------
  // 日期

  static DateTime _detectDate(String text, {required DateTime now}) {
    const offsets = [
      ('大前天', -3),
      ('前天', -2),
      ('昨天', -1),
      ('昨晚', -1),
      ('今天', 0),
      ('今早', 0),
      ('今晚', 0),
    ];
    for (final (word, offset) in offsets) {
      if (text.contains(word)) {
        return now.add(Duration(days: offset));
      }
    }
    return now;
  }

  // ---------------------------------------------------------------------------
  // 分类
  //
  // 顺序敏感：越具体的子类越靠前，「吃/饭/买」这类泛词放最后兜底到大类。
  // 第一个命中的条目即为结果（_detectCategory 顺序遍历）。
  // 既用于「一句话记账」，也用于账单导入的自动归类（guessCategory）。

  static const _expenseKeywords = [
    // —— 食品餐饮（子类优先；吃/饭/餐 兜底到大类 dining）——
    ('dining_drink', ['咖啡', '奶茶', '饮料', '酒水', '啤酒', '可乐', '瑞幸', '星巴克', '蜜雪', '茶百道', '喜茶', '奈雪', 'coffee']),
    ('dining_breakfast', ['早餐', '早饭', '包子', '豆浆', '油条']),
    ('dining_treat', ['请客', '请吃饭', '聚餐', '饭局', '做东']),
    ('groceries', ['买菜', '超市', '菜市场', '生鲜', '钱大妈', '盒马', '永辉', '便利店', 'grocery']),
    ('dining_cook', ['粮油', '调味', '食用油', '大米', '酱油', '挂面']),
    ('dining_snack', ['零食', '薯片', '瓜子', '小吃', '坚果']),
    ('dining_lunch', ['午餐', '午饭', '中午饭']),
    ('dining_dinner', ['晚餐', '晚饭', '夜宵', '宵夜']),
    ('dining', ['外卖', '吃', '饭', '餐', '火锅', '烧烤', '美团', '饿了么', '麦当劳', '肯德基', '海底捞', 'lunch', 'dinner']),
    // —— 出行交通 ——
    ('trans_taxi', ['打车', '滴滴', '出租', '网约车', '曹操', '花小猪', 'taxi', 'uber']),
    ('trans_public', ['地铁', '公交', '公交车', '巴士', 'metro']),
    ('trans_train', ['高铁', '火车', '动车', '12306']),
    ('trans_flight', ['机票', '航班', '飞机', 'flight']),
    ('trans_fuel', ['加油', '油费', '中石化', '中石油', '加油站']),
    ('trans_park', ['停车', '停车费', 'parking']),
    ('trans_repair', ['保养', '修车', '洗车', '4s店']),
    ('transport', ['青桔', '哈啰', '共享单车', '单车']),
    // —— 居家生活 / 水电网气 ——
    ('house_phone', ['话费', '宽带', '流量', '网费', '中国移动', '中国联通', '中国电信']),
    ('utilities', ['电费', '用电']),
    ('house_water', ['水费']),
    ('house_gas', ['燃气', '天然气', '煤气']),
    ('house_property', ['物业']),
    ('house_rent', ['房租', '房贷', '租金', 'rent']),
    ('house_park', ['车位']),
    ('house_clean', ['保洁', '家政', '打扫']),
    // —— 医疗健康 ——
    ('med_drug', ['药', '大药房', '药店', '药房']),
    ('med_checkup', ['体检']),
    ('med_clinic', ['医院', '挂号', '看病', '牙科', '诊所', '门诊', 'hospital']),
    // —— 教育学习 ——
    ('edu_print', ['打印', '文印', '复印']),
    ('edu_book', ['图书', '书店', '教辅', '书籍']),
    ('edu_course', ['学费', '课', '培训', '网课', 'course']),
    // —— 休闲娱乐 ——
    ('travel', ['酒店', '门票', '旅游', '旅行', '民宿', '携程', '飞猪', 'hotel']),
    ('ent_movie', ['电影', '影城', 'ktv', '唱歌', '演唱会', '音乐会', 'movie']),
    ('ent_sport', ['健身', '游泳', '球馆', '健身房']),
    ('ent_spa', ['足浴', '按摩', 'spa', '理疗']),
    ('ent_game', ['剧本杀', '桌游', '棋牌', '麻将']),
    ('ent_bar', ['酒吧', '清吧']),
    ('ent_show', ['演出', '话剧', '展览', 'livehouse']),
    ('entertainment', ['游戏', 'steam']),
    // —— 购物消费 ——
    ('shop_beauty', ['化妆', '护肤', '美妆', '口红', '面膜', '洗发水']),
    ('shop_digital', ['手机', '数码', '电脑', '耳机', 'iphone', '华为', '充电宝']),
    ('shop_appliance', ['电器', '冰箱', '洗衣机', '空调']),
    ('shop_clothes', ['衣服', '鞋', '裤', '外套', '优衣库', '耐克', '阿迪']),
    ('shop_baby', ['母婴', '奶粉', '尿不湿', '纸尿裤', '玩具']),
    ('shop_home', ['家居', '家具', '宜家', '收纳']),
    ('shop_office', ['办公', '文具', '本子']),
    ('shop_deco', ['装修', '建材', '油漆', '五金']),
    ('shop_watch', ['手表', '腕表', '配饰', '首饰']),
    ('pets', ['猫', '狗', '宠物', '猫粮', '狗粮', 'pet']),
    ('subscription', ['会员', '订阅', '续费', 'vip', 'subscription']),
    ('shopping', ['买', '购物', '淘宝', '天猫', '京东', '拼多多', '网购', '苏宁', '唯品会', 'shopping']),
    // —— 人情往来 ——
    ('gift_red', ['随礼', '份子', '发红包', '给红包']),
    ('gift_present', ['礼物', '礼品', '送礼', 'gift']),
    // —— 其他 ——
    ('other_charity', ['捐款', '慈善', '公益']),
    ('other_fine', ['罚款', '违章', '赔偿']),
  ];

  static const _incomeKeywords = [
    ('salary', ['工资', '发薪', '薪水', 'salary']),
    ('bonus', ['奖金', '年终奖', 'bonus']),
    ('investment', ['理财', '基金', '股票', '分红', '利息', 'investment']),
    ('redPacket', ['红包']),
    ('refund', ['退款', '退了', '报销', 'refund']),
  ];

  static String? _detectCategory(String text, {required TransactionKind kind}) {
    final table =
        kind == TransactionKind.income ? _incomeKeywords : _expenseKeywords;
    for (final (key, words) in table) {
      if (words.any(text.contains)) return key;
    }
    return null;
  }

  /// 公开的分类猜测：给一段文字（如商户名+商品）和已知收支方向，
  /// 返回匹配到的分类 key（CategorySeed.key），猜不出返回 null。
  /// 账单导入时用来给「未分类」的外部账目自动归类（会细到子类）。
  static String? guessCategory(String text, {required TransactionKind kind}) =>
      _detectCategory(text, kind: kind);
}

/// 支付截图 OCR 文本的金额提取（微信/支付宝支付完成页、账单详情页）。
class PaymentScreenshotParser {
  PaymentScreenshotParser._();

  /// 截图 OCR 清噪：剔掉明显与交易无关的行（订单号/卡号/余额/积分/纯长数字），
  /// 但凡含"实付/支付/付款/消费/金额"等支付关键词的行一律保留，避免误删真金额。
  static String cleanOcr(String raw) {
    final noise = RegExp(
        r'订单号|交易单号|商户单号|流水号|订单编号|卡号|余额|积分|实名|手机号|身份证');
    final pay = RegExp(r'实付|支付金额|付款金额|消费金额|交易金额|合计|￥|¥');
    final pureDigits = RegExp(r'^[\d\s\-*]{11,}$');
    final hasDigit = RegExp(r'\d');
    final kept = <String>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (noise.hasMatch(t) && !pay.hasMatch(t)) continue;
      // 纯长数字串(>=11位，无小数) → 订单号/卡号/手机号
      if (pureDigits.hasMatch(t) &&
          hasDigit.hasMatch(t) &&
          !t.contains('.')) {
        continue;
      }
      kept.add(t);
    }
    return kept.join('\n');
  }

  /// 从 OCR 出来的多行文本里找「这笔交易的金额」：
  /// 优先带 ¥/￥/− 标记的大号金额行，其次任何两位小数的数字，取金额最大者。
  static Decimal? extractAmount({required String fromOCRText}) {
    final text = fromOCRText;
    final marked = <Decimal>[];
    final plain = <Decimal>[];

    // 匹配可选前缀标记 + 数字（含千分位逗号，1-2位小数）
    final pattern = RegExp(
      r'([-−¥￥]?)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
    );

    for (final match in pattern.allMatches(text)) {
      final markPart = match.group(1) ?? '';
      final numberText = (match.group(2) ?? '').replaceAll(',', '');
      final value = Decimal.tryParse(numberText);
      if (value == null || value <= Decimal.zero) continue;
      if (markPart.isNotEmpty) {
        marked.add(value);
      } else if (numberText.contains('.')) {
        plain.add(value);
      }
    }

    Decimal? maxOf(List<Decimal> list) =>
        list.isEmpty ? null : list.reduce((a, b) => a > b ? a : b);

    return maxOf(marked) ?? maxOf(plain);
  }
}
