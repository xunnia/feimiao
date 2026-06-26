import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../models/category_seed.dart';
import '../models/transaction_kind.dart';
import 'natural_language_entry_parser.dart';

/// DeepSeek 大模型解析器：把一句话拆成多笔 [ParsedEntry]。
///
/// 接口兼容 OpenAI Chat Completions，强制返回 json_object，
/// 不引入任何第三方 AI SDK，仅依赖 package:http。
class LlmEntryParser {
  LlmEntryParser._();

  static const _endpoint =
      'https://api.deepseek.com/chat/completions';
  static const _model = 'deepseek-chat';
  static const _timeoutSeconds = 20;

  // ---------------------------------------------------------------------------
  // 公开入口
  // ---------------------------------------------------------------------------

  /// 调用 DeepSeek 把 [text] 拆成多笔账目。
  ///
  /// - [apiKey]       DeepSeek API key（sk-...）
  /// - [expenseCats]  可用支出分类列表
  /// - [incomeCats]   可用收入分类列表
  /// - [now]          「今天」的基准时间，默认 DateTime.now()
  ///
  /// 失败时抛出 [LlmParseException]。
  static Future<List<ParsedEntry>> parseWithLLM({
    required String text,
    required String apiKey,
    required List<CategorySeed> expenseCats,
    required List<CategorySeed> incomeCats,
    DateTime? now,
    bool fromScreenshot = false,
  }) async {
    final today = now ?? DateTime.now();
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final todayStr = fmt(today);
    final yesterdayStr = fmt(today.subtract(const Duration(days: 1)));
    const wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekdayStr = wd[today.weekday - 1];

    final expenseList = expenseCats
        .map((c) => '${c.key}:${c.nameZh}')
        .join('、');
    final incomeList = incomeCats
        .map((c) => '${c.key}:${c.nameZh}')
        .join('、');

    final systemPrompt = '''你是专业记账助手。把用户的一句话拆成一笔或多笔账目，只输出JSON对象，不要任何解释、不要Markdown。
今天是 $todayStr（$weekdayStr）。

【可用分类】(categoryKey 只能从这里选)
支出：$expenseList
收入：$incomeList

【输出格式】
{"entries":[{"amount":数字,"kind":"expense或income","categoryKey":"最匹配的key","date":"YYYY-MM-DD","note":"简短备注","confidence":0到1}]}

【规则】
1. 一句话里有多笔(顿号/逗号/和/还有/分别等)就拆成多条。
2. amount是纯数字(元)，去掉￥/元/块/钱；中文数字要换算，如"三十"→30、"一百二"→120。
3. categoryKey 优先选**最具体的子类**：如"奶茶/咖啡"选 dining_drink 而非 dining，"打车"选 trans_taxi 而非 transport；实在拿不准，支出用 other、收入用 otherIncome。
4. 分清收支：工资/奖金/收到红包/退款/报销/利息/分红=收入(income)；其余绝大多数是支出(expense)。
5. 相对日期换算成具体日期：今天=$todayStr，昨天=$yesterdayStr，前天/大前天/上周X 等同理换算；没提日期就用今天。
6. confidence 是你对(金额+分类+收支)的整体把握：信息明确给0.9以上，靠猜给0.5以下。

【示例】
输入：昨天打车28，中午吃饭花了20
输出：{"entries":[{"amount":28,"kind":"expense","categoryKey":"trans_taxi","date":"$yesterdayStr","note":"打车","confidence":0.95},{"amount":20,"kind":"expense","categoryKey":"dining_lunch","date":"$yesterdayStr","note":"午饭","confidence":0.9}]}
输入：发工资了八千
输出：{"entries":[{"amount":8000,"kind":"income","categoryKey":"salary","date":"$todayStr","note":"工资","confidence":0.97}]}''';

    // 截图模式:OCR 文本含界面噪声,加一段专门的提取规则。
    const screenshotExtra = '''

【这是一张支付/账单/订单截图的 OCR 文本，含界面噪声】
- 只提取真实消费；忽略无关数字：余额、订单号、卡号、积分、手机号、商品数量、划线原价/标价、优惠券面额、折扣等。
- 金额取**真实付款额**：优先"实付/支付金额/合计/自动确认收货并付款 ¥X"里**大于0**的数；忽略"实付：¥0"这类先用后付的占位。
- 商品名/店铺名作为分类依据，并写进备注。
- 若是订单列表（多个商品/多个店铺）：**每个订单各记一笔**；并且**每笔的商品名必须与它自己那一单的付款金额严格对应，绝不能错位、绝不能把不同商品合并成一笔**。订单有几个就记几笔。
- 能识别交易时间（如 2026-06-20 12:30）就用其日期；识别不到用今天。
- 普通单笔支付页就只记一笔。''';
    final sys = fromScreenshot ? systemPrompt + screenshotExtra : systemPrompt;
    final userContent = fromScreenshot
        ? '下面是支付/账单截图的 OCR 文字，请从中提取交易：\n\n$text'
        : text;

    final requestBody = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': userContent},
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.2, // 抽取类任务调低，减少同句不同解析的随机性
      'stream': false,
    });

    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
    } catch (e) {
      throw LlmParseException('网络请求失败：$e');
    }

    if (response.statusCode != 200) {
      throw LlmParseException(
          'DeepSeek 返回错误 ${response.statusCode}：${response.body}');
    }

    // 取 choices[0].message.content
    late Map<String, dynamic> outer;
    try {
      outer = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw LlmParseException('响应 JSON 解析失败：$e');
    }

    final content = (() {
      try {
        return (outer['choices'] as List).first['message']['content'] as String;
      } catch (e) {
        throw LlmParseException('响应结构异常，无法取到 content：$e');
      }
    })();

    // 解析 content 里的 entries 数组
    late Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw LlmParseException('模型返回的 JSON 解析失败：$e\n原文：$content');
    }

    final rawEntries = parsed['entries'];
    if (rawEntries == null || rawEntries is! List) {
      throw LlmParseException('模型返回格式异常：缺少 entries 数组');
    }

    final result = <ParsedEntry>[];
    for (final raw in rawEntries) {
      final entry = _convertEntry(raw as Map<String, dynamic>, today);
      if (entry != null) result.add(entry);
    }

    if (result.isEmpty) {
      throw LlmParseException('模型未能解析出任何账目，请换一种说法重试');
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // 内部转换
  // ---------------------------------------------------------------------------

  static ParsedEntry? _convertEntry(
      Map<String, dynamic> raw, DateTime fallbackDate) {
    // amount
    final rawAmount = raw['amount'];
    final Decimal? amount = switch (rawAmount) {
      num n => Decimal.tryParse(n.toString()),
      String s => Decimal.tryParse(s),
      _ => null,
    };

    // kind
    final kindStr = raw['kind'] as String? ?? 'expense';
    final kind = kindStr == 'income'
        ? TransactionKind.income
        : TransactionKind.expense;

    // categoryKey
    final categoryKey = raw['categoryKey'] as String?;

    // note
    final note = raw['note'] as String? ?? '';

    // date
    DateTime date;
    try {
      final dateStr = raw['date'] as String? ?? '';
      date = dateStr.isEmpty ? fallbackDate : DateTime.parse(dateStr);
    } catch (_) {
      date = fallbackDate;
    }

    // confidence（缺省 0.7 → 走确认卡，安全兜底）
    final rawConf = raw['confidence'];
    final confidence = switch (rawConf) {
      num n => n.toDouble().clamp(0.0, 1.0),
      String s => (double.tryParse(s) ?? 0.7).clamp(0.0, 1.0),
      _ => 0.7,
    };

    return ParsedEntry(
      amount: amount,
      kind: kind,
      categoryKey: categoryKey,
      note: note,
      date: date,
      confidence: confidence,
    );
  }
}

/// LLM 解析过程中的异常，携带可读中文消息。
class LlmParseException implements Exception {
  final String message;
  const LlmParseException(this.message);

  @override
  String toString() => 'LlmParseException: $message';
}
