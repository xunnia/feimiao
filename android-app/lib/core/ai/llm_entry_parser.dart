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
  }) async {
    final today = now ?? DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final expenseList = expenseCats
        .map((c) => '${c.key}:${c.nameZh}')
        .join('、');
    final incomeList = incomeCats
        .map((c) => '${c.key}:${c.nameZh}')
        .join('、');

    final systemPrompt = '''你是记账助手。把用户的一句话拆成一笔或多笔账目，只输出JSON对象，不要任何解释和Markdown。
今天是 $todayStr。
可用分类(key:名称)——支出：$expenseList；收入：$incomeList。
输出格式：{"entries":[{"amount":数字,"kind":"expense或income","categoryKey":"从上面列表选最匹配的key，拿不准支出用other、收入用otherIncome","date":"YYYY-MM-DD","note":"简短备注"}]}
规则：句子里有多笔就拆成多条；amount是纯数字(元)，不含货币符号；相对日期(今天/昨天/前天/大前天/上周等)换算成具体日期，没提日期用今天；分清收支(工资/红包/退款/报销等是收入，其余多为支出)。''';

    final requestBody = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': text},
      ],
      'response_format': {'type': 'json_object'},
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

    return ParsedEntry(
      amount: amount,
      kind: kind,
      categoryKey: categoryKey,
      note: note,
      date: date,
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
