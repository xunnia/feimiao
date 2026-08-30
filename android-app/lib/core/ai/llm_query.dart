import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'ai_provider_config.dart';
import 'openai_codex_oauth.dart';
import 'system_network_proxy.dart';
import 'web_search.dart';

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
    List<Map<String, String>> priorTurns = const [],
  }) async {
    final provider = await OpenAiCodexOAuth.ensureFreshConfig(
      _resolveConfig(apiKey: apiKey, config: config),
    );
    final webSearch = await AiWebSearchContext.prepare(
      question: question,
      config: provider,
    );
    final systemPrompt = '''你是「喵助手」，一只蓝白英短猫助手，有账本数据作为参考。
性格：口语化、亲切，可以带一点猫咪语气（偶尔用「喵」）。
能力：可以回答任何问题——记账查账、消费分析、日常聊天、知识问答都可以。
账本相关回答规则：涉及金额要给具体数字（单位元）；算不出或数据里没有就如实说不知道，绝不编造。
**账目里若给了「本期准确合计」「本期分类准确合计」或「分类查询准确合计」，回答总额时必须直接引用那个数，绝不自己把明细一条条加起来（你手算会错）。**
如果账目上下文出现「分类筛选已锁定」，只能使用该分类及其子分类的合计和明细；
禁止把其它分类的数字混进答案，也不要把全月总支出冒充分类支出。若筛选合计为 0，直接如实回答 0。

$transactionsText''';

    final history = [
      for (final turn in priorTurns)
        {'role': turn['role']!, 'content': turn['content']!},
    ];

    final answer = await _postWithModelFallback(
      config: provider,
      timeoutSeconds: _timeoutSeconds,
      bodyForModel: (model) => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          if (webSearch.promptBlock.trim().isNotEmpty)
            {'role': 'system', 'content': webSearch.promptBlock},
          ...history,
          {'role': 'user', 'content': question},
        ],
        'stream': false,
      },
    );
    return webSearch.annotateAnswer(answer);
  }

  static Future<String> askReport({
    required String reportTitle,
    required String reportType,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
  }) async {
    final provider = await OpenAiCodexOAuth.ensureFreshConfig(
      _resolveConfig(apiKey: apiKey, config: config),
    );
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
    var models = config.modelCandidates;
    var activeConfig = config;
    var unauthorizedRetried = false;
    var codexCatalogRetried = false;
    for (var index = 0; index < models.length; index++) {
      final model = models[index];
      try {
        final body = bodyForModel(model);
        if (activeConfig.shouldUseClaudeMessages) {
          return await _postClaudeMessages(
            config: activeConfig,
            body: body,
            timeoutSeconds: timeoutSeconds,
          );
        }
        if (activeConfig.shouldUseResponses) {
          return await _postResponses(
            config: activeConfig,
            body: _responsesBodyFromChatBody(body, activeConfig),
            timeoutSeconds: timeoutSeconds,
          );
        }
        return await _postChat(
          config: activeConfig,
          body: body,
          timeoutSeconds: timeoutSeconds,
        );
      } on LlmQueryException catch (e) {
        if (!unauthorizedRetried &&
            e.statusCode == 401 &&
            activeConfig.isOpenAiCodexOAuth) {
          unauthorizedRetried = true;
          activeConfig = await OpenAiCodexOAuth.service
              .refreshAfterUnauthorized(activeConfig);
          // The access token may be rotated independently of expires_at.
          // Retry the same model once before falling back or surfacing 401.
          index--;
          continue;
        }
        if (!codexCatalogRetried &&
            activeConfig.isOpenAiCodexOAuth &&
            _isUnsupportedModelError(e)) {
          codexCatalogRetried = true;
          final refreshed = await _configWithLiveCodexModel(activeConfig);
          if (refreshed != null && refreshed.model != activeConfig.model) {
            activeConfig = refreshed;
            models = [refreshed.model];
            index = -1;
            continue;
          }
        }
        lastError = e;
        if (index == models.length - 1 || !_shouldRetryWithCompatModel(e)) {
          rethrow;
        }
      }
    }
    throw lastError ?? const LlmQueryException('未知错误');
  }

  static bool _isUnsupportedModelError(LlmQueryException error) {
    final message = error.message.toLowerCase();
    return (error.statusCode == 400 || error.statusCode == 404) &&
        (message.contains('unsupported model') ||
            message.contains('model not found') ||
            message.contains('unknown model') ||
            message.contains('invalid model'));
  }

  static Future<AiProviderConfig?> _configWithLiveCodexModel(
    AiProviderConfig config,
  ) async {
    try {
      final freshConfig = await OpenAiCodexOAuth.ensureFreshConfig(config);
      final catalog = await OpenAiCodexOAuth.service.fetchModels(
        OpenAiCodexOAuthTokens(
          accessToken: freshConfig.apiKey,
          accountId: freshConfig.oauthAccountId,
        ),
      );
      final candidates = catalog
          .map((item) => item.slug.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (candidates.isEmpty) return null;
      final model = candidates.firstWhere(
        (item) => item != freshConfig.model.trim(),
        orElse: () => candidates.first,
      );
      return freshConfig.copyWith(model: model);
    } on OpenAiCodexOAuthException {
      return null;
    } catch (_) {
      return null;
    }
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
    if (config.isOpenAiCodexOAuth) {
      return _codexResponsesBodyFromChatBody(chatBody, config);
    }

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
      // Public Responses defaults to retaining responses; Chats/report data
      // must be explicitly non-persistent at the provider boundary.
      'store': false,
    };
    final instructionText = instructions.join('\n\n').trim();
    if (instructionText.isNotEmpty) body['instructions'] = instructionText;
    final maxTokens = chatBody['max_tokens'];
    if (maxTokens is int && maxTokens > 0) {
      body['max_output_tokens'] = maxTokens;
    }
    final effort = config.reasoningEffort.responsesApiValue;
    if (effort != null) {
      body['reasoning'] = {'effort': effort};
    }
    final webTools = config.responsesWebSearchTools;
    if (webTools.isNotEmpty) body['tools'] = webTools;
    final webIncludes = config.responsesWebSearchIncludes;
    if (webIncludes.isNotEmpty) body['include'] = webIncludes;
    return body;
  }

  static Map<String, dynamic> _codexResponsesBodyFromChatBody(
    Map<String, dynamic> chatBody,
    AiProviderConfig config,
  ) {
    final instructions = <String>[];
    final input = <Map<String, dynamic>>[];
    final messages = chatBody['messages'];
    if (messages is List) {
      for (final item in messages) {
        if (item is! Map) continue;
        final role = (item['role'] as String?)?.trim().toLowerCase() ?? 'user';
        final content = _stringContent(item['content']).trim();
        if (content.isEmpty) continue;
        if (role == 'system' || role == 'developer') {
          instructions.add(content);
          continue;
        }
        input.add({
          'type': 'message',
          'role': role == 'assistant' ? 'assistant' : 'user',
          'content': [
            {
              'type': role == 'assistant' ? 'output_text' : 'input_text',
              'text': content,
            },
          ],
        });
      }
    }
    final instructionText = instructions.join('\n\n').trim();
    final body = <String, dynamic>{
      'model': chatBody['model'],
      'instructions': instructionText.isEmpty
          ? 'You are a helpful assistant.'
          : instructionText,
      'input': input,
      'store': false,
      'stream': true,
    };
    final effort = config.reasoningEffort.codexResponsesApiValue;
    if (effort != null) body['reasoning'] = {'effort': effort};
    final webTools = config.responsesWebSearchTools;
    if (webTools.isNotEmpty) body['tools'] = webTools;
    final webIncludes = config.responsesWebSearchIncludes;
    if (webIncludes.isNotEmpty) body['include'] = webIncludes;
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
    await SystemNetworkProxy.refresh();
    // Resolve PAC/system-proxy routing for this concrete upstream before the
    // request. OAuth/model discovery already does this; chat-completions must
    // use the same per-host route or a proxy VPN can make the first message
    // fail even though the browser and settings test succeed.
    await SystemNetworkProxy.refreshFor(config.chatCompletionsUri);
    late http.Response resp;
    try {
      resp = await http
          .post(
            config.chatCompletionsUri,
            headers: config.authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('网络请求失败：$e');
    }

    // 必须用 bodyBytes 显式按 UTF-8 解码：响应头不带 charset 时
    // http 包的 .body 按 latin1 解，中文全变乱码且会入库。
    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      final snippet = _bodySnippet(bodyText);
      throw LlmQueryException(
        '${config.providerLabel} 返回错误 ${resp.statusCode}'
        '${snippet.isEmpty ? '' : '：$snippet'}',
        statusCode: resp.statusCode,
      );
    }

    try {
      final outer = jsonDecode(bodyText) as Map<String, dynamic>;
      final content =
          (outer['choices'] as List).first['message']['content'] as String;
      final text = content.trim();
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('响应解析失败：$e');
    }
  }

  /// Claude 原生 /v1/messages 端点（带 thinking 参数）
  static Future<String> _postClaudeMessages({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    await SystemNetworkProxy.refresh();
    await SystemNetworkProxy.refreshFor(config.messagesUri);
    // 从 chat-completions 格式转换为 Claude Messages 格式
    final messages = body['messages'] as List? ?? [];
    String? systemPrompt;
    final claudeMessages = <Map<String, dynamic>>[];
    for (final msg in messages) {
      if (msg is! Map) continue;
      final role = (msg['role'] as String?)?.trim() ?? 'user';
      final content = _stringContent(msg['content']).trim();
      if (content.isEmpty) continue;
      if (role == 'system') {
        systemPrompt = content;
      } else {
        claudeMessages.add({'role': role, 'content': content});
      }
    }

    final budget = config.reasoningEffort.claudeBudgetTokens;
    final requestedMaxTokens = (body['max_tokens'] as int?) ?? 4096;
    final maxTokens = budget != null
        ? math.max(requestedMaxTokens, budget + 4096)
        : requestedMaxTokens;

    final claudeBody = <String, dynamic>{
      'model': body['model'],
      'messages': claudeMessages,
      'max_tokens': maxTokens,
    };
    if (systemPrompt != null) claudeBody['system'] = systemPrompt;

    // 思考深度参数
    if (budget != null) {
      claudeBody['thinking'] = {
        'type': 'enabled',
        'budget_tokens': budget,
      };
      // thinking 模式下 temperature 必须为 1
      claudeBody['temperature'] = 1;
    }

    late http.Response resp;
    try {
      resp = await http
          .post(
            config.messagesUri,
            headers: config.authHeaders(),
            body: jsonEncode(claudeBody),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('Claude Messages 请求失败：$e');
    }

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      final snippet = _bodySnippet(bodyText);
      throw LlmQueryException(
        '${config.providerLabel} Messages 返回错误 ${resp.statusCode}'
        '${snippet.isEmpty ? '' : '：$snippet'}',
        statusCode: resp.statusCode,
      );
    }

    try {
      final outer = jsonDecode(bodyText) as Map<String, dynamic>;
      final contentList = outer['content'] as List?;
      if (contentList == null) throw const LlmQueryException('空回答');
      final text = contentList
          .whereType<Map>()
          .where((c) => c['type'] == 'text')
          .map((c) => (c['text'] as String?)?.trim() ?? '')
          .where((t) => t.isNotEmpty)
          .join('\n')
          .trim();
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('Claude Messages 响应解析失败：$e');
    }
  }

  static Future<String> _postResponses({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    await SystemNetworkProxy.refresh();
    await SystemNetworkProxy.refreshFor(config.responsesUri);
    final sessionId =
        config.isOpenAiCodexOAuth ? OpenAiCodexOAuth.generateRequestId() : null;
    // The ChatGPT/Codex subscription endpoint only accepts streamed
    // Responses. Keep this invariant at the transport boundary so report,
    // connection-test, and other non-streaming callers cannot accidentally
    // send `stream: false` and receive the upstream 400 "Stream must be set
    // to true" response.
    final requestBody = sessionId == null
        ? body
        : OpenAiCodexOAuth.prepareCodexResponsesBody(
            {...body, 'stream': true},
            sessionId: sessionId,
          );
    final headers = config.authHeaders();
    if (sessionId != null) {
      headers.addAll(
        OpenAiCodexOAuth.codexRequestHeaders(
          sessionId: sessionId,
          stream: requestBody['stream'] == true,
        ),
      );
    }
    late http.Response resp;
    try {
      resp = await http
          .post(
            config.responsesUri,
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('网络请求失败：$e');
    }

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      final snippet = _bodySnippet(bodyText);
      throw LlmQueryException(
        '${config.providerLabel} Responses 返回错误 ${resp.statusCode}'
        '${snippet.isEmpty ? '' : '：$snippet'}',
        statusCode: resp.statusCode,
      );
    }

    try {
      final String text;
      if (config.isOpenAiCodexOAuth) {
        final raw = _extractCodexSseText(bodyText).trim();
        text = AiWebSearchContext.formatAnswerWithSources(
          raw,
          config.webSearchEnabled ? _extractSseSources(bodyText) : const [],
        );
      } else {
        final outer = jsonDecode(bodyText) as Map<String, dynamic>;
        final raw = _extractResponsesText(outer).trim();
        text = AiWebSearchContext.formatAnswerWithSources(
          raw,
          config.webSearchEnabled ? _extractResponseSources(outer) : const [],
        );
      }
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('Responses 响应解析失败：$e');
    }
  }

  static String _extractCodexSseText(String body) {
    final buffer = StringBuffer();
    String? completed;
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data == '[DONE]') break;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          final event = Map<String, dynamic>.from(decoded);
          final type = event['type']?.toString().toLowerCase() ?? '';
          if (type == 'response.failed') {
            throw LlmQueryException(
              event['response'] is Map
                  ? ((event['response'] as Map)['error']?.toString() ??
                      'Responses 生成失败')
                  : 'Responses 生成失败',
            );
          }
          if (type == 'response.output_text.done') {
            final text = event['text'];
            if (text is String && text.trim().isNotEmpty) completed = text;
          } else if (type == 'response.completed') {
            final response = event['response'];
            if (response is Map) {
              final text = _extractResponsesText(
                Map<String, dynamic>.from(response),
              );
              if (text.isNotEmpty) completed = text;
            }
          }
          final delta = event['delta'];
          if (delta is String && delta.isNotEmpty) buffer.write(delta);
        }
      } on LlmQueryException {
        rethrow;
      } catch (_) {
        // Ignore vendor-specific SSE comments/events that are not JSON.
      }
    }
    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : (completed ?? '');
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

  static List<AiWebSource> _extractResponseSources(Object? outer) =>
      AiWebSearchContext.extractResponseSources(outer);

  static List<AiWebSource> _extractSseSources(String body) {
    final result = <AiWebSource>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data == '[DONE]') break;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          for (final source in _extractResponseSources(
            Map<String, dynamic>.from(decoded),
          )) {
            if (seen.add(source.url)) result.add(source);
          }
        }
      } catch (_) {
        // Ignore non-JSON SSE comments/events.
      }
    }
    return result;
  }

  static String _bodySnippet(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }

  static Future<void> testConnection(AiProviderConfig config) async {
    // 健康检查必须复用 Chats 的端点选择，否则自定义 Responses 中转会
    // 出现“设置页测试成功、喵助手实际失败”的假阳性。
    final provider = _resolveConfig(config: config).forChatStreaming();
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
    if (!provider.hasCredential) {
      throw LlmQueryException(
          '${provider.providerLabel} API Key 或 OAuth 凭据未配置');
    }
    if (!provider.hasBaseUrl) {
      throw LlmQueryException('${provider.providerLabel} 基础地址未配置');
    }
    if (!provider.hasModel) {
      throw LlmQueryException('${provider.providerLabel} 模型未配置');
    }
    return provider;
  }

  /// 从服务商获取可用模型列表（调用 /v1/models 端点）
  static Future<List<String>> fetchModels(
    AiProviderConfig config, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Keep model discovery, PAT identity hydration, and 401 refresh on one
    // OAuth service/client.  Tests and callers that inject a client must not
    // accidentally refresh through the process-global client while discovery
    // uses the injected transport.
    final oauthService = client == null
        ? OpenAiCodexOAuth.service
        : OpenAiCodexOAuthService(client: client);
    var provider = await oauthService.ensureFreshConfig(config);
    if (!provider.hasKey) {
      throw LlmQueryException('${provider.providerLabel} API Key 未配置');
    }
    if (!provider.hasBaseUrl) {
      throw LlmQueryException('${provider.providerLabel} 基础地址未配置');
    }

    if (provider.isOpenAiCodexOAuth) {
      try {
        final models = await oauthService.fetchModels(
          OpenAiCodexOAuthTokens(
            accessToken: provider.apiKey,
            accountId: provider.oauthAccountId,
          ),
        );
        return models.map((model) => model.slug).toList(growable: false);
      } on OpenAiCodexOAuthException catch (error) {
        // A ChatGPT access token can be invalidated before its local expiry
        // timestamp. Refresh once and retry the catalogue request so the
        // settings screen does not make the user authorize again.
        if (error.statusCode == 401 &&
            provider.oauthRefreshToken.trim().isNotEmpty) {
          provider = await oauthService.refreshAfterUnauthorized(provider);
          try {
            final models = await oauthService.fetchModels(
              OpenAiCodexOAuthTokens(
                accessToken: provider.apiKey,
                accountId: provider.oauthAccountId,
              ),
            );
            return models.map((model) => model.slug).toList(growable: false);
          } on OpenAiCodexOAuthException catch (retryError) {
            throw LlmQueryException(
              retryError.message,
              statusCode: retryError.statusCode,
            );
          }
        }
        throw LlmQueryException(error.message, statusCode: error.statusCode);
      }
    }

    final headers = provider.authHeaders()..['Accept'] = 'application/json';

    LlmQueryException? lastFailure;
    final uris = _modelUris(provider);
    for (var index = 0; index < uris.length; index++) {
      final uri = uris[index];
      late http.Response resp;
      try {
        await SystemNetworkProxy.refreshFor(uri);
        final request = client == null
            ? http.get(uri, headers: headers)
            : client.get(uri, headers: headers);
        resp = await request.timeout(timeout);
      } on TimeoutException {
        // Some relays leave /v1/models hanging while exposing the legacy
        // /models route. Keep trying the alternate URI before surfacing the
        // timeout, so a slow/unsupported catalog does not make the model list
        // appear permanently unavailable.
        lastFailure = const LlmQueryException('获取模型列表超时，请检查服务商地址和网络');
        continue;
      } catch (e) {
        // A connection/DNS failure on one catalog route should not prevent a
        // compatible fallback route from being tried.
        lastFailure = LlmQueryException('获取模型列表失败：$e');
        continue;
      }

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw LlmQueryException('API Key 无效或无权限（${resp.statusCode}）');
      }
      // A few OpenAI-compatible relays expose /models instead of /v1/models,
      // or return 405/501 for the unsupported route. Try the alternate path
      // for any non-auth catalog failure; authentication errors remain final.
      if (resp.statusCode != 200 && index + 1 < uris.length) {
        lastFailure = LlmQueryException('获取模型列表失败（${resp.statusCode}）');
        continue;
      }
      if (resp.statusCode != 200) {
        throw LlmQueryException('获取模型列表失败（${resp.statusCode}）');
      }

      return _decodeModelList(resp.body);
    }
    throw lastFailure ?? const LlmQueryException('获取模型列表失败');
  }

  static List<Uri> _modelUris(AiProviderConfig config) {
    final primary = config.modelsUri;
    final path = primary.path;
    const versionedSuffix = '/v1/models';
    final alternate = path.endsWith(versionedSuffix)
        ? primary.replace(
            path:
                '${path.substring(0, path.length - versionedSuffix.length)}/models',
          )
        : null;
    if (alternate == null || alternate == primary) return [primary];
    return [primary, alternate];
  }

  static List<String> _decodeModelList(String body) {
    try {
      final decoded = jsonDecode(body);
      final dynamic raw = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? (decoded['data'] ?? decoded['models'])
              : null;
      if (raw is! List) {
        throw const LlmQueryException('响应格式错误：缺少 data/models 字段');
      }
      final models = raw
          .map((entry) {
            if (entry is String) return entry;
            if (entry is Map) {
              return entry['id'] ??
                  entry['slug'] ??
                  entry['name'] ??
                  entry['model'];
            }
            return null;
          })
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (models.isEmpty) {
        throw const LlmQueryException('未获取到任何模型');
      }
      return models;
    } catch (e) {
      if (e is LlmQueryException) rethrow;
      throw LlmQueryException('解析模型列表失败：$e');
    }
  }
}

class LlmQueryException implements Exception {
  final String message;
  final int? statusCode;
  const LlmQueryException(this.message, {this.statusCode});
  @override
  String toString() => 'LlmQueryException: $message';
}
