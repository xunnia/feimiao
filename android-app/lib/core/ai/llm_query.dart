import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider_config.dart';

/// 查账问答：把账目数据 + 用户问题发给 DeepSeek，返回一段口语化回答。
///
/// 与 [LlmEntryParser] 共用 DeepSeek OpenAI 兼容接口，但这里要的是自由文本回答
/// （非 JSON），用于「喵助手」的查账 / 消费分析。
class LlmQuery {
  LlmQuery._();

  static const _timeoutSeconds = 30;
  static const _reportTimeoutSeconds = 90;

  /// 根据 [transactionsText]（账目上下文）回答 [question]。
  /// 失败抛 [LlmQueryException]。
  static Future<String> ask({
    required String question,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
  }) async {
    final provider = _resolveConfig(apiKey: apiKey, config: config);
    final systemPrompt = '''你是「喵助手」，一只蓝白英短猫记账助理。根据下面的账目数据回答用户的问题。
要求：口语化、简短亲切、可以带一点猫咪语气（偶尔用「喵」）；涉及金额要给具体数字（单位元）；
算不出或数据里没有就如实说不知道，绝不编造。
**账目里若给了「本期准确合计」，回答总额时必须直接引用那个数，绝不自己把明细一条条加起来（你手算会错）。**

排版（对齐 Claude 的可读性，结构清晰有层次）：
- 先给**一句话结论**，再展开细节；
- 分几块时用 `## 小标题` 起头（如「## 大头在哪」），标题上下各空一行；
- 段落之间空一行；同一段别超过两句，别一大坨；
- 并列信息用「- 」列表，每条一行；关键结论和重要数字用 **双星号加粗**（如 **¥128.50**、**餐饮**）；
- 只允许 `##标题`、**加粗**、「- 」列表这几种 Markdown，不要表格、引用、代码块。

$transactionsText''';

    return _postWithModelFallback(
      config: provider,
      timeoutSeconds: _timeoutSeconds,
      bodyForModel: (model) => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': question},
        ],
        'stream': false,
      },
    );
  }

  static Future<String> askReport({
    required String reportTitle,
    required String reportType,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
  }) async {
    final provider = _resolveConfig(apiKey: apiKey, config: config);
    final typeLabel = switch (reportType) {
      'weekly' => '消费周报',
      'yearly' => '消费年报',
      _ => '消费月报',
    };
    final systemPrompt = '''你是一位专业、克制、懂用户体验的个人财务分析师，正在为用户撰写一份$typeLabel。
目标不是写一篇很长的审计报告，而是帮助用户在手机上快速看懂：这个周期花得是否稳定、主要变化来自哪里、下阶段应该做什么。

总原则：
1. 结论先行：先判断「整体稳定 / 有结构变化 / 需要确认」，再解释证据。
2. 不制造焦虑：小幅波动、周期性支出、一次性大额、人情往来、学费/保险/房租/还款等都可能正常。不要把正常波动写成失控。
3. 必须区分三类支出：
   - 固定/周期支出：房租、保险、还款、会员、学费等，说明它们对总额的影响，但不要当成日常消费失控。
   - 一次性大额支出：维修、校园支付、礼物、设备、旅行等，说明是否只是本期事件。
   - 日常可控支出：餐饮、购物、交通、娱乐等，才适合给预算建议。
4. 如果分类可能影响判断，必须明确写「建议确认分类」，例如校园支付被归到食品餐饮时，不能直接断言餐饮习惯恶化。
5. 建议必须具体可执行，包含金额、阈值、触发条件或分类动作。禁止写「理性消费」「合理规划」这类空话。
6. 语气像懂财务的朋友：专业、平和、短句，不恐吓，不夸大，不做道德评价。
7. 金额和合计优先使用账目上下文里「本期准确合计」等本地计算结果，不要自己重新加总。

长度与排版：
- 全文控制在 900-1300 个中文字符；宁可少讲，也不要堆满所有流水。
- 每段最多 2 句话；列表每条尽量 1 行到 2 行。
- 只使用 Markdown 二级标题、段落、列表和加粗；禁止 Markdown 表格、代码块、引用块。
- 避免高压词：除非证据非常明确，否则不要使用「恶化」「暴跌」「暴涨」「紧张」「风险很大」「严重」等措辞。

输出结构必须严格使用：
# $reportTitle

## 本月一句话
用 2-3 句话、120-180 个中文字符概括。必须包含：总支出/环比或同比、最主要变化来源、一个最值得确认或优化的点。不要超过 180 字。

## 一、核心指标
用 4 条短列表即可：
- **总支出**：本期金额、对比金额、变化幅度，并判断是否属于小幅波动。
- **收入与结余**：说明收入/结余对本期现金流的影响。
- **固定/周期支出**：列出影响最大的 1-2 项。
- **日常可控支出**：只讲最需要看的 1-2 类。
随后用 1 个短段解释组合信号。

## 二、支出结构
只分析前三个一级分类，必须说明它们分别更像「固定/周期」「一次性大额」还是「日常可控」。
如果某笔大额可能放错分类，直接写「这会影响该分类占比判断，建议确认」。

## 三、值得确认的账单
最多列 3-5 笔，必须包含日期、分类、金额或备注。标题下先写一句：以下不是一定有问题，而是会影响报告判断准确性的条目。
没有明显条目时，写「本期没有特别需要确认的单笔」。

## 四、下阶段建议
只给 3 条建议：
- 一条分类/记账口径建议；
- 一条预算或金额阈值建议；
- 一条下月观察建议。
每条必须包含具体动作或数字。

$transactionsText''';

    return _postWithModelFallback(
      config: provider,
      timeoutSeconds: _reportTimeoutSeconds,
      bodyForModel: (model) => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '请生成：$reportTitle'},
        ],
        'stream': false,
        'temperature': 0.25,
        'max_tokens': 2400,
      },
    );
  }

  static Future<String> _postWithModelFallback({
    required AiProviderConfig config,
    required int timeoutSeconds,
    required Map<String, dynamic> Function(String model) bodyForModel,
  }) async {
    LlmQueryException? lastError;
    final models = config.modelCandidates;
    for (final model in models) {
      try {
        final body = bodyForModel(model);
        if (config.shouldUseResponses) {
          return await _postResponses(
            config: config,
            body: _responsesBodyFromChatBody(body, config),
            timeoutSeconds: timeoutSeconds,
          );
        }
        return await _postChat(
          config: config,
          body: body,
          timeoutSeconds: timeoutSeconds,
        );
      } on LlmQueryException catch (e) {
        lastError = e;
        if (model == models.last || !_shouldRetryWithCompatModel(e)) rethrow;
      }
    }
    throw lastError ?? const LlmQueryException('未知错误');
  }

  static bool _shouldRetryWithCompatModel(LlmQueryException e) {
    final statusCode = e.statusCode;
    if (statusCode == 400 || statusCode == 404) return true;
    final m = e.message.toLowerCase();
    return m.contains('model') ||
        m.contains('unsupported') ||
        m.contains('invalid') ||
        m.contains('parameter');
  }

  static Map<String, dynamic> _responsesBodyFromChatBody(
    Map<String, dynamic> chatBody,
    AiProviderConfig config,
  ) {
    final instructions = <String>[];
    final inputParts = <String>[];
    final messages = chatBody['messages'];
    if (messages is List) {
      for (final item in messages) {
        if (item is! Map) continue;
        final role = (item['role'] as String?)?.trim().toLowerCase() ?? 'user';
        final content = _stringContent(item['content']).trim();
        if (content.isEmpty) continue;
        if (role == 'system' || role == 'developer') {
          instructions.add(content);
        } else if (role == 'assistant') {
          inputParts.add('assistant: $content');
        } else {
          inputParts.add(content);
        }
      }
    }
    final body = <String, dynamic>{
      'model': chatBody['model'],
      'input': inputParts.join('\n\n').trim(),
    };
    final instructionText = instructions.join('\n\n').trim();
    if (instructionText.isNotEmpty) body['instructions'] = instructionText;
    final maxTokens = chatBody['max_tokens'];
    if (maxTokens is int && maxTokens > 0) {
      body['max_output_tokens'] = maxTokens;
    }
    final effort = config.reasoningEffort.apiValue;
    if (effort != null) {
      body['reasoning'] = {'effort': effort};
    }
    return body;
  }

  static String _stringContent(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) {
            if (part is String) return part;
            if (part is Map) return part['text']?.toString() ?? '';
            return '';
          })
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
    }
    return content?.toString() ?? '';
  }

  static Future<String> _postChat({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    late http.Response resp;
    try {
      resp = await http
          .post(
            config.chatCompletionsUri,
            headers: {
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('网络请求失败：$e');
    }

    if (resp.statusCode != 200) {
      final snippet = _bodySnippet(resp.body);
      throw LlmQueryException(
        '${config.providerLabel} 返回错误 ${resp.statusCode}'
        '${snippet.isEmpty ? '' : '：$snippet'}',
        statusCode: resp.statusCode,
      );
    }

    try {
      final outer = jsonDecode(resp.body) as Map<String, dynamic>;
      final content =
          (outer['choices'] as List).first['message']['content'] as String;
      final text = content.trim();
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('响应解析失败：$e');
    }
  }

  static Future<String> _postResponses({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    late http.Response resp;
    try {
      resp = await http
          .post(
            config.responsesUri,
            headers: {
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('网络请求失败：$e');
    }

    if (resp.statusCode != 200) {
      final snippet = _bodySnippet(resp.body);
      throw LlmQueryException(
        '${config.providerLabel} Responses 返回错误 ${resp.statusCode}'
        '${snippet.isEmpty ? '' : '：$snippet'}',
        statusCode: resp.statusCode,
      );
    }

    try {
      final outer = jsonDecode(resp.body) as Map<String, dynamic>;
      final text = _extractResponsesText(outer).trim();
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('Responses 响应解析失败：$e');
    }
  }

  static String _extractResponsesText(Map<String, dynamic> outer) {
    final outputText = outer['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }
    final buffer = StringBuffer();
    void walk(Object? value) {
      if (value is Map) {
        final type = value['type']?.toString();
        final text = value['text'];
        if ((type == 'output_text' || type == 'text') && text is String) {
          if (text.trim().isNotEmpty) buffer.writeln(text.trim());
        }
        final content = value['content'];
        if (content != null) walk(content);
        final output = value['output'];
        if (output != null) walk(output);
      } else if (value is List) {
        for (final item in value) {
          walk(item);
        }
      }
    }

    walk(outer['output']);
    return buffer.toString().trim();
  }

  static String _bodySnippet(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }

  static Future<void> testConnection(AiProviderConfig config) async {
    final provider = _resolveConfig(config: config);
    await _postWithModelFallback(
      config: provider,
      timeoutSeconds: 15,
      bodyForModel: (model) => {
        'model': model,
        'messages': const [
          {'role': 'system', 'content': '只回复 OK。'},
          {'role': 'user', 'content': 'ping'},
        ],
        'stream': false,
        'temperature': 0,
        'max_tokens': 8,
      },
    );
  }

  static AiProviderConfig _resolveConfig({
    String? apiKey,
    AiProviderConfig? config,
  }) {
    final provider =
        config ?? AiProviderConfig.deepSeek(apiKey: apiKey?.trim() ?? '');
    if (!provider.hasKey) {
      throw LlmQueryException('${provider.providerLabel} API Key 未配置');
    }
    return provider;
  }
}

class LlmQueryException implements Exception {
  final String message;
  final int? statusCode;
  const LlmQueryException(this.message, {this.statusCode});
  @override
  String toString() => 'LlmQueryException: $message';
}
