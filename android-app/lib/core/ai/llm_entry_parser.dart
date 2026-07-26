import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../models/transaction_kind.dart';
import '../transaction_time.dart';
import 'ai_provider_config.dart';
import 'entry_sanity.dart';
import 'natural_language_entry_parser.dart';

/// DeepSeek 大模型解析器：把一句话拆成多笔 [ParsedEntry]。
///
/// 接口兼容 OpenAI Chat Completions，强制返回 json_object，
/// 不引入任何第三方 AI SDK，仅依赖 package:http。
class LlmEntryParser {
  LlmEntryParser._();

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
  static Future<LlmParseResult> parseWithLLM({
    required String text,
    String? apiKey,
    AiProviderConfig? config,
    required List<({String key, String name})> expenseCats,
    required List<({String key, String name})> incomeCats,
    List<({String phrase, String categoryKey})> learnedHints = const [],
    DateTime? now,
    bool fromScreenshot = false,
  }) async {
    final provider = _resolveConfig(apiKey: apiKey, config: config);
    final today = now ?? DateTime.now();
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final todayStr = fmt(today);
    final yesterdayStr = fmt(today.subtract(const Duration(days: 1)));
    const wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekdayStr = wd[today.weekday - 1];

    final expenseList = expenseCats.map((c) => '${c.key}:${c.name}').join('、');
    final incomeList = incomeCats.map((c) => '${c.key}:${c.name}').join('、');

    // 用户历史纠正 → few-shot 习惯提示，让模型模仿这个用户的分类选择。
    final hints = learnedHints.take(20).toList();
    final habitBlock = hints.isEmpty
        ? ''
        : '''

【该用户的记账习惯】(备注/商户含左边词时**优先**归右边分类，这是该用户亲自纠正过的，尽量遵循)
${hints.map((h) => '${h.phrase}→${h.categoryKey}').join('、')}''';

    final systemPrompt =
        '''你是专业记账助手。把用户的一句话拆成一笔或多笔账目，只输出JSON对象，不要任何解释、不要Markdown。
今天是 $todayStr（$weekdayStr）。

【可用分类】(categoryKey 只能从这里选)
支出：$expenseList
收入：$incomeList$habitBlock

【输出格式】
{"intent":"record或query","entries":[{"amount":数字,"kind":"expense或income","categoryKey":"最匹配的key","date":"YYYY-MM-DD或YYYY-MM-DDTHH:mm:ss","note":"简短备注","confidence":0到1}]}
- intent="record"：用户在**记一笔账**（描述花了/买了/收到多少钱），哪怕很口语（如"坐公交花了一块""中午吃了碗面15"）。entries 填解析出的账目。
- intent="query"：用户在**问**已有账目或要分析（如"这月吃饭花了多少""最大一笔是哪个""我花得多不多"）。这时 entries 给空数组 []。
- 拿不准时**优先当 record**（这是记账助手，多数输入是在记账）。

【规则】
1. 一句话里有多笔(顿号/逗号/和/还有/分别等)就拆成多条。
2. amount是纯数字(元)，去掉￥/元/块/钱；中文数字要换算，如"三十"→30、"一百二"→120。
3. categoryKey 优先选**最具体的子类**：如"奶茶/咖啡"选 dining_drink 而非 dining，"打车"选 trans_taxi 而非 transport；实在拿不准，支出用 other、收入用 otherIncome。
4. 分清收支：工资/奖金/收到红包/退款/报销/利息/分红=收入(income)；其余绝大多数是支出(expense)。
5. 相对日期换算成具体日期：今天=$todayStr，昨天=$yesterdayStr，前天/大前天/上周X 等同理换算；没提日期就用今天。用户明确说了时分时输出完整时间（如 2026-06-20T12:30:00），没说时分只输出日期，不能猜时间。
6. confidence 是你对(金额+分类+收支)的整体把握：信息明确给0.9以上，靠猜给0.5以下。
7. AA/均摊/平摊：若说了人数N(如"4个人AA""3人均摊")，amount 填**我应承担的那份=总额÷N**；没给人数就按总额，别瞎猜人数。

【示例】
输入：昨天打车28，中午吃饭花了20
输出：{"intent":"record","entries":[{"amount":28,"kind":"expense","categoryKey":"trans_taxi","date":"$yesterdayStr","note":"打车","confidence":0.95},{"amount":20,"kind":"expense","categoryKey":"dining_lunch","date":"$yesterdayStr","note":"午饭","confidence":0.9}]}
输入：发工资了八千
输出：{"intent":"record","entries":[{"amount":8000,"kind":"income","categoryKey":"salary","date":"$todayStr","note":"工资","confidence":0.97}]}
输入：这个月吃饭花了多少
输出：{"intent":"query","entries":[]}''';

    // 截图模式:OCR 文本含界面噪声,加一段专门的提取规则。
    const screenshotExtra = '''

【这是一张支付/账单/订单截图的 OCR 文本，含界面噪声】
- 只提取真实消费；忽略无关数字：余额、订单号、卡号、积分、手机号、商品数量、划线原价/标价、优惠券面额、折扣等。
- 金额取**真实付款额**：优先"实付/支付金额/合计/自动确认收货并付款 ¥X"里**大于0**的数；忽略"实付：¥0"这类先用后付的占位。
- 商品名/店铺名作为分类依据，并写进备注。
- 订单列表（京东/淘宝/拼多多「我的订单」等，多个店铺/商品）：**每个有效订单各记一笔，有几单记几单，一个都别漏**（包括最后一个、被优惠券/权益横幅隔开的）。
- 一个订单的结构通常是：**店铺名 → 商品名 → ¥金额 → 「共N件」→ 状态(完成/已完成/已取消…)**。**金额只配它「同一单内」的商品名（店铺名与「共N件」之间那个），绝不能跨单去配上一单或下一单的商品。**
- **状态是「已取消 / 交易关闭 / 退款 / 退款成功 / 未付款 / 待付款」的订单一律不要记**——不是真实支出。
- 拼多多「先用后付」：金额取"X天后自动确认收货并付款 ¥X"里的数；"实付：¥0"是占位，忽略。
- 忽略界面噪声：搜索框、顶部 tab(全部/购物/外卖/服务)、按钮(再次购买/删除订单/去报销/去领券/退换售后/咨询医生)、优惠券与权益横幅、划线原价、件数、报销百分比。
- **文本若含 ───── 分隔线**：是按版面切好的订单分块，金额只跟同块内紧邻上方的商品配对、不跨块；一块通常=一单。
  例：「舒肤佳沐浴露…¥32.04…维达抽纸…¥15.9」必须记成 舒肤佳=32.04、维达=15.9，**不要**错位成维达=32.04。
- 能识别交易时间（如 2026-06-20 12:30）就输出完整日期和时分；只有日期时只输出日期；识别不到用今天。
- 普通单笔支付页就只记一笔。''';
    final sys = fromScreenshot ? systemPrompt + screenshotExtra : systemPrompt;
    final userContent =
        fromScreenshot ? '下面是支付/账单截图的 OCR 文字，请从中提取交易：\n\n$text' : text;

    // 兼容模型回退（对齐 llm_query 的 _postWithModelFallback）：
    // 首选模型 400/404 或报模型不存在时，换下一个候选模型重试。
    final content = await _postChatContentWithFallback(
      provider: provider,
      bodyForModel: (model) => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': sys},
          {'role': 'user', 'content': userContent},
        ],
        'response_format': {'type': 'json_object'},
        'temperature': 0.2, // 抽取类任务调低，减少同句不同解析的随机性
        'stream': false,
      },
    );

    // 解析 content 里的 entries 数组
    late Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw LlmParseException('模型返回的 JSON 解析失败：$e\n原文：$content');
    }

    // 意图：截图一律记账；否则读模型给的 intent，缺省/拿不准当 record。
    final intentStr = (parsed['intent'] as String?)?.toLowerCase();
    final intent = (!fromScreenshot && intentStr == 'query')
        ? LlmIntent.query
        : LlmIntent.record;

    final result = <ParsedEntry>[];
    final rawEntries = parsed['entries'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is Map<String, dynamic>) {
          final entry = _convertEntry(raw, today);
          if (entry != null) result.add(entry);
        }
      }
    }

    // 不再因 entries 为空而抛错：query 本就无账目；record 为空交给上层礼貌追问。
    return LlmParseResult(intent: intent, entries: result);
  }

  /// 批量给商户归类（导入复核页的「一次 AI 兜底」）：把去重后的商户名
  /// （可带示例商品）一次性发给 DeepSeek，返回 {商户名: categoryKey}。
  /// 一次调用归几十个商户，去重后 token 极省。失败抛 [LlmParseException]。
  static Future<Map<String, String>> classifyMerchants({
    required List<({String merchant, String sample})> items,
    required List<({String key, String name})> categories,
    required TransactionKind kind,
    String? apiKey,
    AiProviderConfig? config,
  }) async {
    if (items.isEmpty) return const {};
    final provider = _resolveConfig(apiKey: apiKey, config: config);
    final catList = categories.map((c) => '${c.key}:${c.name}').join('、');
    final kindName = kind == TransactionKind.income ? '收入' : '支出';
    final fallbackKey =
        kind == TransactionKind.income ? 'otherIncome' : 'other';
    final merchantLines = items
        .map((e) => e.sample.trim().isEmpty
            ? e.merchant
            : '${e.merchant}（例:${e.sample}）')
        .join('\n');
    final sys =
        '''你是记账分类助手。下面每行是一个商户名（可能带示例商品）。把**每个商户**归到最合适的**$kindName**分类，只输出一个JSON对象，键是商户名原文、值是categoryKey，不要解释、不要Markdown。
categoryKey 只能从这里选（拿不准用 $fallbackKey）：
$catList
规则：看商户在卖什么就归哪类；京东/淘宝/拼多多/美团这类万能平台按最可能的大类(购物/餐饮)；个人转账/看不出来源或用途的用 $fallbackKey。''';
    // 兼容模型回退：与 parseWithLLM 共用同一套候选模型重试逻辑。
    final content = await _postChatContentWithFallback(
      provider: provider,
      bodyForModel: (model) => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': sys},
          {'role': 'user', 'content': merchantLines},
        ],
        'response_format': {'type': 'json_object'},
        'temperature': 0.2,
        'stream': false,
      },
    );
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return {
        for (final e in parsed.entries)
          if (e.value is String && (e.value as String).isNotEmpty)
            e.key: e.value as String
      };
    } catch (e) {
      throw LlmParseException('AI 归类结果解析失败：$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 请求（带兼容模型回退）
  // ---------------------------------------------------------------------------

  /// 遍历 [AiProviderConfig.modelCandidates] 发 Chat Completions 请求，
  /// 返回 choices[0].message.content。首选模型报 400/404 或错误信息带
  /// model/unsupported 等字样时换下一个候选重试（对齐 llm_query 的做法）。
  static Future<String> _postChatContentWithFallback({
    required AiProviderConfig provider,
    required Map<String, dynamic> Function(String model) bodyForModel,
  }) async {
    LlmParseException? lastError;
    final models = provider.modelCandidates;
    for (final model in models) {
      try {
        return await _postChatContent(
          provider: provider,
          body: bodyForModel(model),
        );
      } on LlmParseException catch (e) {
        lastError = e;
        if (model == models.last || !_shouldRetryWithCompatModel(e)) rethrow;
      }
    }
    throw lastError ?? const LlmParseException('未知错误');
  }

  static bool _shouldRetryWithCompatModel(LlmParseException e) {
    final statusCode = e.statusCode;
    if (statusCode == 400 || statusCode == 404) return true;
    final m = e.message.toLowerCase();
    return m.contains('model') ||
        m.contains('unsupported') ||
        m.contains('invalid') ||
        m.contains('parameter');
  }

  static Future<String> _postChatContent({
    required AiProviderConfig provider,
    required Map<String, dynamic> body,
  }) async {
    late http.Response response;
    try {
      response = await http
          .post(
            provider.chatCompletionsUri,
            headers: {
              'Authorization': 'Bearer ${provider.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
    } catch (e) {
      throw LlmParseException('网络请求失败：$e');
    }

    // 用 bodyBytes 显式按 UTF-8 解码：响应头不带 charset 时 .body 按
    // latin1 解，中文备注会以乱码入库。
    final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw LlmParseException(
        '${provider.providerLabel} 返回错误 ${response.statusCode}：$bodyText',
        statusCode: response.statusCode,
      );
    }

    // 取 choices[0].message.content
    late Map<String, dynamic> outer;
    try {
      outer = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (e) {
      throw LlmParseException('响应 JSON 解析失败：$e');
    }
    try {
      return (outer['choices'] as List).first['message']['content'] as String;
    } catch (e) {
      throw LlmParseException('响应结构异常，无法取到 content：$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 内部转换
  // ---------------------------------------------------------------------------

  static AiProviderConfig _resolveConfig({
    String? apiKey,
    AiProviderConfig? config,
  }) {
    final provider =
        config ?? AiProviderConfig.deepSeek(apiKey: apiKey?.trim() ?? '');
    if (!provider.hasKey) {
      throw LlmParseException('${provider.providerLabel} API Key 未配置');
    }
    return provider;
  }

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
    final kind =
        kindStr == 'income' ? TransactionKind.income : TransactionKind.expense;

    // categoryKey
    final categoryKey = raw['categoryKey'] as String?;

    // note
    final note = raw['note'] as String? ?? '';

    // date
    final date = parseAiTransactionTime(
      raw['date'] as String? ?? '',
      fallback: fallbackDate,
    );
    final timePrecision =
        aiTransactionTimePrecision(raw['date'] as String? ?? '');

    // confidence（缺省 0.7 → 走确认卡，安全兜底）
    final rawConf = raw['confidence'];
    final confidence = switch (rawConf) {
      num n => n.toDouble().clamp(0.0, 1.0),
      String s => (double.tryParse(s) ?? 0.7).clamp(0.0, 1.0),
      _ => 0.7,
    };

    return EntrySanity.clean(
      ParsedEntry(
        amount: amount,
        kind: kind,
        categoryKey: categoryKey,
        note: note,
        date: date,
        timePrecision: timePrecision,
        confidence: confidence,
      ),
      now: fallbackDate,
    );
  }
}

/// 备注拼进 LLM 上下文（「日期|收支|分类|金额|备注」竖线对齐格式）前的清洗：
/// 换行/回车换成空格、竖线（半角 | 与全角 ｜）换成 ／，防止用户备注里的
/// 换行或竖线伪造出新的账目行/列，注入假数据误导 AI。
String sanitizeNoteForLlm(String note) => note
    .replaceAll('\r', ' ')
    .replaceAll('\n', ' ')
    .replaceAll('|', '／')
    .replaceAll('｜', '／');

/// 用户意图：记一笔账 / 查询已有账目。
enum LlmIntent { record, query }

/// parseWithLLM 的结果：意图 + 解析出的账目（query 时 entries 可为空）。
class LlmParseResult {
  final LlmIntent intent;
  final List<ParsedEntry> entries;
  const LlmParseResult({required this.intent, required this.entries});
}

/// LLM 解析过程中的异常，携带可读中文消息（HTTP 错误时带状态码，
/// 供兼容模型回退判断 400/404）。
class LlmParseException implements Exception {
  final String message;
  final int? statusCode;
  const LlmParseException(this.message, {this.statusCode});

  @override
  String toString() => 'LlmParseException: $message';
}
