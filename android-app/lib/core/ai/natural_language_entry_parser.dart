import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';

/// 一句话记账的解析结果。
class ParsedEntry {
  final Decimal? amount;
  final TransactionKind kind;

  /// 匹配到的分类 key（对应 CategorySeed.key），null 表示没识别出来。
  final String? categoryKey;
  final String note;
  final DateTime date;

  const ParsedEntry({
    required this.amount,
    required this.kind,
    required this.categoryKey,
    required this.note,
    required this.date,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedEntry &&
          amount == other.amount &&
          kind == other.kind &&
          categoryKey == other.categoryKey &&
          note == other.note &&
          date == other.date;

  @override
  int get hashCode =>
      Object.hash(amount, kind, categoryKey, note, date);
}

/// 本地规则版「一句话记账」解析器：
/// 「昨天打车23块」→ 支出 / 交通 / 23 元 / 昨天。
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
    return ParsedEntry(
      amount: extractAmount(trimmed),
      kind: kind,
      categoryKey: _detectCategory(trimmed, kind: kind),
      note: trimmed,
      date: _detectDate(trimmed, now: now),
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

    // 兜底：最后一个数字（"买了2杯咖啡58" -> 58）
    final allPattern = RegExp(r'(\d+(?:\.\d{1,2})?)');
    final allMatches = allPattern.allMatches(text).toList();
    if (allMatches.isNotEmpty) {
      return Decimal.tryParse(allMatches.last.group(1)!);
    }

    return null;
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

  static const _expenseKeywords = [
    ('groceries', ['买菜', '超市', '菜市场', '生鲜', 'grocery']),
    ('dining', ['早餐', '午餐', '晚餐', '夜宵', '外卖', '吃', '饭', '餐', '咖啡', '奶茶', '火锅', '烧烤', '面', 'lunch', 'dinner', 'coffee']),
    ('transport', ['打车', '滴滴', '出租', '地铁', '公交', '高铁', '火车', '加油', '油费', '停车', 'taxi', 'uber', 'metro']),
    ('travel', ['机票', '酒店', '门票', '旅游', '旅行', '民宿', 'flight', 'hotel']),
    ('housing', ['房租', '物业', '房贷', 'rent']),
    ('utilities', ['水费', '电费', '燃气', '网费', '话费', '宽带', '流量']),
    ('medical', ['医院', '挂号', '药', '体检', '看病', '牙', 'hospital']),
    ('education', ['学费', '课', '培训', '书', '网课', 'course']),
    ('entertainment', ['电影', '游戏', 'KTV', '演唱会', '音乐会', '剧本杀', '桌游', 'movie', 'game']),
    ('pets', ['猫', '狗', '宠物', '猫粮', '狗粮', 'pet']),
    ('gifts', ['随礼', '份子', '礼物', '发红包', '给红包', 'gift']),
    ('subscription', ['会员', '订阅', '续费', 'subscription']),
    ('shopping', ['买', '购物', '淘宝', '京东', '拼多多', '网购', '衣服', '鞋', 'shopping']),
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
}

/// 支付截图 OCR 文本的金额提取（微信/支付宝支付完成页、账单详情页）。
class PaymentScreenshotParser {
  PaymentScreenshotParser._();

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
