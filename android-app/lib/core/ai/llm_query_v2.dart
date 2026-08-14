import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'ai_data_trimmer.dart';
import 'ai_exception.dart';
import 'ai_logger.dart';
import 'ai_prompt_templates.dart';
import 'ai_provider_config.dart';
import 'ai_request_manager.dart';

/// AI 查询服务 V2：集成流式响应、日志、异常处理、数据裁剪、并发控制、
/// Token 计数、fallback 等优化。
///
/// 向后兼容原有 LlmQuery API，同时提供新的流式接口。
class LlmQueryV2 {
  LlmQueryV2._();

  static const _defaultTimeoutSeconds = 30;
  static const _reportTimeoutSeconds = 90;
  static const _streamTimeoutSeconds = 60;

  /// 流式问答：逐字返回 AI 回答，实时渲染
  ///
  /// [onChunk] 每收到一个文本片段就调用一次
  /// [onDone] 完整回答接收完毕后调用
  /// [onError] 出错时调用
  static Future<void> askStream({
    required String question,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
    required void Function(String chunk) onChunk,
    required void Function(String fullAnswer) onDone,
    required void Function(AiException error) onError,
    String? taskId,
  }) async {
    final tid = taskId ?? 'ask_stream_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    try {
      final provider = _resolveConfig(apiKey: apiKey, config: config);

      AiLogger.logQueryStart(
        taskType: 'ask_stream',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        estimatedTokens: AiDataTrimmer.estimateTokens(transactionsText),
      );

      await AiRequestManager.execute(
        taskId: tid,
        allowConcurrent: false,
        request: () => _streamChat(
          config: provider,
          messages: [
            {'role': 'system', 'content': AiPromptTemplates.systemPrompt},
            {'role': 'system', 'content': '账目上下文：\n$transactionsText'},
            {'role': 'user', 'content': question},
          ],
          timeoutSeconds: _streamTimeoutSeconds,
          onChunk: onChunk,
          onDone: (fullAnswer) {
            final duration = DateTime.now().difference(startTime).inMilliseconds;
            AiLogger.logQuerySuccess(
              taskType: 'ask_stream',
              provider: provider.providerLabel,
              model: provider.modelCandidates.first,
              durationMs: duration,
            );
            onDone(fullAnswer);
          },
        ),
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final provider = _resolveConfig(apiKey: apiKey, config: config);
      final aiError = AiRequestManager.wrapException(e);

      AiLogger.logQueryFailure(
        taskType: 'ask_stream',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        errorType: aiError.runtimeType.toString(),
        errorMessage: aiError.message,
        durationMs: duration,
        statusCode: aiError.statusCode,
      );

      onError(aiError);
    }
  }

  /// 非流式问答（向后兼容原 LlmQuery.ask）
  static Future<String> ask({
    required String question,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
    String? taskId,
  }) async {
    final tid = taskId ?? 'ask_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    try {
      final provider = _resolveConfig(apiKey: apiKey, config: config);

      AiLogger.logQueryStart(
        taskType: 'ask',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        estimatedTokens: AiDataTrimmer.estimateTokens(transactionsText),
      );

      final result = await AiRequestManager.execute(
        taskId: tid,
        allowConcurrent: false,
        request: () => AiRequestManager.retryWithBackoff(
          maxRetries: 2,
          taskType: 'query',
          provider: provider.providerLabel,
          model: provider.modelCandidates.first,
          request: () => _postWithModelFallback(
            config: provider,
            timeoutSeconds: _defaultTimeoutSeconds,
            bodyForModel: (model) => {
              'model': model,
              'messages': [
                {'role': 'system', 'content': AiPromptTemplates.systemPrompt},
                {'role': 'system', 'content': '账目上下文：\n$transactionsText'},
                {'role': 'user', 'content': question},
              ],
              'stream': false,
            },
          ),
        ),
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AiLogger.logQuerySuccess(
        taskType: 'ask',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        durationMs: duration,
      );

      return result;
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final provider = _resolveConfig(apiKey: apiKey, config: config);
      final aiError = AiRequestManager.wrapException(e);

      AiLogger.logQueryFailure(
        taskType: 'ask',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        errorType: aiError.runtimeType.toString(),
        errorMessage: aiError.message,
        durationMs: duration,
        statusCode: aiError.statusCode,
      );

      rethrow;
    }
  }

  /// 生成报告（月报/周报/年报）
  static Future<String> askReport({
    required String reportTitle,
    required String reportType,
    String? apiKey,
    AiProviderConfig? config,
    required String transactionsText,
    String? taskId,
  }) async {
    final tid = taskId ?? 'report_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    try {
      final provider = _resolveConfig(apiKey: apiKey, config: config);
      final typeLabel = switch (reportType) {
        'weekly' => '消费周报',
        'yearly' => '消费年报',
        _ => '消费月报',
      };

      AiLogger.logQueryStart(
        taskType: 'report_$reportType',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        estimatedTokens: AiDataTrimmer.estimateTokens(transactionsText),
        extra: {'report_type': reportType},
      );

      final systemPrompt = '''你是一位专业、克制、懂用户体验的个人财务分析师,正在为用户撰写一份$typeLabel。
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

      final result = await AiRequestManager.execute(
        taskId: tid,
        allowConcurrent: false,
        request: () => AiRequestManager.retryWithBackoff(
          maxRetries: 2,
          taskType: 'report',
          provider: provider.providerLabel,
          model: provider.modelCandidates.first,
          request: () => _postWithModelFallback(
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
          ),
        ),
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AiLogger.logQuerySuccess(
        taskType: 'report_$reportType',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        durationMs: duration,
      );

      return result;
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final provider = _resolveConfig(apiKey: apiKey, config: config);
      final aiError = AiRequestManager.wrapException(e);

      AiLogger.logQueryFailure(
        taskType: 'report_$reportType',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        errorType: aiError.runtimeType.toString(),
        errorMessage: aiError.message,
        durationMs: duration,
        statusCode: aiError.statusCode,
      );

      rethrow;
    }
  }

  /// 测试连接（健康检查）
  static Future<void> testConnection(AiProviderConfig config) async {
    final startTime = DateTime.now();

    try {
      final provider = _resolveConfig(config: config);

      AiLogger.logQueryStart(
        taskType: 'test_connection',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
      );

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

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AiLogger.logQuerySuccess(
        taskType: 'test_connection',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        durationMs: duration,
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final provider = _resolveConfig(config: config);
      final aiError = AiRequestManager.wrapException(e);

      AiLogger.logQueryFailure(
        taskType: 'test_connection',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        errorType: aiError.runtimeType.toString(),
        errorMessage: aiError.message,
        durationMs: duration,
        statusCode: aiError.statusCode,
      );

      rethrow;
    }
  }

  /// 取消查询
  static void cancel(String taskId) {
    AiRequestManager.cancel(taskId);
  }

  // ========== 内部实现 ==========

  static Future<String> _postWithModelFallback({
    required AiProviderConfig config,
    required int timeoutSeconds,
    required Map<String, dynamic> Function(String model) bodyForModel,
  }) async {
    AiException? lastError;
    final models = config.modelCandidates;

    for (int i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        var body = bodyForModel(model);

        // Claude 格式转换
        if (config.isClaudeModel) {
          body = _convertToClaudeFormat(body, config);
        }

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
      } catch (e) {
        lastError = AiRequestManager.wrapException(e);

        // 最后一个模型失败直接抛出
        if (i == models.length - 1) rethrow;

        // 非模型错误不重试
        if (lastError is! AiModelNotSupportedException) rethrow;

        // 记录重试
        AiLogger.logRetry(
          taskType: 'model_fallback',
          provider: config.providerLabel,
          fromModel: model,
          toModel: models[i + 1],
          reason: lastError.message,
        );
      }
    }

    throw lastError ?? const AiUnknownException('未知错误');
  }

  static Future<String> _postChat({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    final isClaude = config.isClaudeModel;
    final uri = isClaude ? config.messagesUri : config.chatCompletionsUri;

    late http.Response resp;

    try {
      final headers = {
        'Content-Type': 'application/json',
      };

      if (isClaude) {
        headers['x-api-key'] = config.apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer ${config.apiKey}';
      }

      resp = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      throw const AiNetworkException('请求超时');
    } catch (e) {
      throw _sanitizeException(AiNetworkException('网络请求失败', originalError: e), config.apiKey);
    }

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);

    if (resp.statusCode != 200) {
      throw _sanitizeException(
        AiRequestManager.wrapException(
          Exception(_bodySnippet(bodyText)),
          statusCode: resp.statusCode,
        ),
        config.apiKey,
      );
    }

    try {
      final outer = jsonDecode(bodyText) as Map<String, dynamic>;

      // 提取 usage 信息
      final usage = outer['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        AiLogger.logQuerySuccess(
          taskType: 'token_usage',
          provider: config.providerLabel,
          model: body['model'] as String,
          durationMs: 0,
          promptTokens: usage['prompt_tokens'] as int? ?? usage['input_tokens'] as int?,
          completionTokens: usage['completion_tokens'] as int? ?? usage['output_tokens'] as int?,
          totalTokens: usage['total_tokens'] as int?,
        );
      }

      // 提取响应文本
      final String text;
      if (isClaude) {
        // Claude 格式: content 是数组
        final content = outer['content'] as List?;
        if (content == null || content.isEmpty) {
          throw const AiEmptyResponseException('Claude 返回空 content');
        }
        final textBlock = content.firstWhere(
          (block) => block['type'] == 'text',
          orElse: () => <String, dynamic>{},
        );
        text = (textBlock['text'] as String? ?? '').trim();
      } else {
        // OpenAI 格式
        final content = (outer['choices'] as List).first['message']['content'] as String;
        text = content.trim();
      }

      if (text.isEmpty) {
        throw const AiEmptyResponseException('AI 返回空内容');
      }

      return text;
    } catch (e) {
      if (e is AiException) rethrow;
      throw _sanitizeException(AiResponseParseException('响应解析失败', originalError: e), config.apiKey);
    }
  }

  static Future<void> _streamChat({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
    required int timeoutSeconds,
    required void Function(String chunk) onChunk,
    required void Function(String fullAnswer) onDone,
  }) async {
    final isClaude = config.isClaudeModel;
    final uri = isClaude ? config.messagesUri : config.chatCompletionsUri;

    final Map<String, dynamic> body;

    if (isClaude) {
      // Claude 原生格式
      final systemMessages = messages.where((m) => m['role'] == 'system').toList();
      final userMessages = messages.where((m) => m['role'] != 'system').toList();

      body = {
        'model': config.modelCandidates.first,
        'messages': userMessages,
        'stream': true,
        'max_tokens': 4096,
      };

      // 合并 system prompt
      if (systemMessages.isNotEmpty) {
        body['system'] = systemMessages.map((m) => m['content']).join('\n\n');
      }

      // thinking 参数映射
      if (config.reasoningEffort != AiReasoningEffort.none) {
        final budgetTokens = switch (config.reasoningEffort) {
          AiReasoningEffort.minimal => 1024,
          AiReasoningEffort.low => 4096,
          AiReasoningEffort.medium => 8192,
          AiReasoningEffort.high => 16384,
          AiReasoningEffort.xhigh => 32768,
          AiReasoningEffort.ultra => 65536,
          _ => 8192,
        };
        body['thinking'] = {
          'type': 'enabled',
          'budget_tokens': budgetTokens,
        };
      }
    } else {
      // OpenAI 兼容格式
      body = {
        'model': config.modelCandidates.first,
        'messages': messages,
        'stream': true,
      };
    }

    late http.StreamedResponse resp;

    try {
      final headers = {
        'Content-Type': 'application/json',
      };

      if (isClaude) {
        headers['x-api-key'] = config.apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer ${config.apiKey}';
      }

      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(body);

      resp = await request.send().timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      throw const AiNetworkException('请求超时');
    } catch (e) {
      throw _sanitizeException(AiNetworkException('网络请求失败', originalError: e), config.apiKey);
    }

    if (resp.statusCode != 200) {
      final bodyText = await resp.stream.bytesToString();
      throw _sanitizeException(
        AiRequestManager.wrapException(
          Exception(_bodySnippet(bodyText)),
          statusCode: resp.statusCode,
        ),
        config.apiKey,
      );
    }

    final fullAnswer = StringBuffer();

    try {
      await resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.isEmpty) return;

            if (isClaude) {
              // Claude SSE 格式: "data: {...}"
              if (!line.startsWith('data: ')) return;
              final data = line.substring(6);

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final type = json['type'] as String?;

                if (type == 'content_block_delta') {
                  final delta = json['delta'];
                  final content = delta?['text'] as String?;

                  if (content != null && content.isNotEmpty) {
                    fullAnswer.write(content);
                    onChunk(content);
                  }
                }
              } catch (e) {
                AiLogger.logWarning(
                  taskType: 'stream_parse_chunk',
                  provider: config.providerLabel,
                  model: config.modelCandidates.first,
                  warning: 'Claude 流式响应单条解析失败: $e',
                  extra: {'chunk_data': data.substring(0, data.length > 100 ? 100 : data.length)},
                );
              }
            } else {
              // OpenAI 格式
              if (!line.startsWith('data: ')) return;
              final data = line.substring(6);
              if (data == '[DONE]') return;

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final delta = json['choices']?[0]?['delta'];
                final content = delta?['content'] as String?;

                if (content != null && content.isNotEmpty) {
                  fullAnswer.write(content);
                  onChunk(content);
                }
              } catch (e) {
                AiLogger.logWarning(
                  taskType: 'stream_parse_chunk',
                  provider: config.providerLabel,
                  model: config.modelCandidates.first,
                  warning: '流式响应单条解析失败: $e',
                  extra: {'chunk_data': data.substring(0, data.length > 100 ? 100 : data.length)},
                );
              }
            }
          })
          .asFuture();

      onDone(fullAnswer.toString());
    } catch (e) {
      throw _sanitizeException(AiResponseParseException('流式响应解析失败', originalError: e), config.apiKey);
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
    } on TimeoutException {
      throw const AiNetworkException('请求超时');
    } catch (e) {
      throw _sanitizeException(AiNetworkException('网络请求失败', originalError: e), config.apiKey);
    }

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);

    if (resp.statusCode != 200) {
      throw _sanitizeException(
        AiRequestManager.wrapException(
          Exception(_bodySnippet(bodyText)),
          statusCode: resp.statusCode,
        ),
        config.apiKey,
      );
    }

    try {
      final outer = jsonDecode(bodyText) as Map<String, dynamic>;
      final text = _extractResponsesText(outer).trim();

      if (text.isEmpty) {
        throw const AiEmptyResponseException('Responses 返回空内容');
      }

      return text;
    } catch (e) {
      if (e is AiException) rethrow;
      throw _sanitizeException(AiResponseParseException('Responses 响应解析失败', originalError: e), config.apiKey);
    }
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

  /// 清理异常消息中的 API Key
  static AiException _sanitizeException(AiException exception, String apiKey) {
    if (apiKey.isEmpty) return exception;

    // 清理异常消息
    final sanitizedMessage = exception.message.replaceAll(apiKey, '[API_KEY_REDACTED]');

    // 清理 originalError 中的 API Key（如果是 Exception）
    Object? sanitizedOriginalError = exception.originalError;
    if (sanitizedOriginalError is Exception) {
      final originalErrorString = sanitizedOriginalError.toString();
      if (originalErrorString.contains(apiKey)) {
        sanitizedOriginalError = Exception(originalErrorString.replaceAll(apiKey, '[API_KEY_REDACTED]'));
      }
    }

    // 根据异常类型重建
    if (exception is AiNetworkException) {
      return AiNetworkException(sanitizedMessage, originalError: sanitizedOriginalError);
    } else if (exception is AiAuthException) {
      return AiAuthException(sanitizedMessage, statusCode: exception.statusCode);
    } else if (exception is AiRateLimitException) {
      return AiRateLimitException(
        sanitizedMessage,
        statusCode: exception.statusCode,
        retryAfterSeconds: exception.retryAfterSeconds,
      );
    } else if (exception is AiTokenLimitException) {
      return AiTokenLimitException(sanitizedMessage, statusCode: exception.statusCode);
    } else if (exception is AiServerException) {
      return AiServerException(sanitizedMessage, statusCode: exception.statusCode);
    } else if (exception is AiResponseParseException) {
      return AiResponseParseException(sanitizedMessage, originalError: sanitizedOriginalError);
    } else if (exception is AiConfigException) {
      return AiConfigException(sanitizedMessage);
    } else if (exception is AiModelNotSupportedException) {
      return AiModelNotSupportedException(sanitizedMessage, statusCode: exception.statusCode);
    } else if (exception is AiEmptyResponseException) {
      return AiEmptyResponseException(sanitizedMessage);
    } else if (exception is AiBadRequestException) {
      return AiBadRequestException(
        sanitizedMessage,
        statusCode: exception.statusCode,
        originalError: sanitizedOriginalError,
      );
    } else if (exception is AiUnknownException) {
      return AiUnknownException(
        sanitizedMessage,
        statusCode: exception.statusCode,
        originalError: sanitizedOriginalError,
      );
    }

    return exception;
  }

  // ========== 测试辅助方法 ==========

  /// 测试辅助：暴露 _sanitizeException 供单测验证
  @visibleForTesting
  static AiException sanitizeExceptionForTest(AiException exception, String apiKey) =>
      _sanitizeException(exception, apiKey);

  /// 测试辅助：判断是否应该降级到其他服务商
  @visibleForTesting
  static bool shouldFallbackToProviderForTest(AiException error) {
    return error.shouldFallback;
  }

  /// 测试辅助：判断是否应该用相同模型重试
  @visibleForTesting
  static bool shouldRetryWithSameModelForTest(AiException error) {
    return error.shouldRetry && !error.shouldFallback;
  }

  /// 测试辅助：判断是否应该用兼容模型重试
  @visibleForTesting
  static bool shouldRetryWithCompatibleModelForTest(AiException error) {
    return error is AiModelNotSupportedException || error is AiBadRequestException;
  }

  /// 将 OpenAI 格式的请求体转换为 Claude 格式
  static Map<String, dynamic> _convertToClaudeFormat(
    Map<String, dynamic> openaiBody,
    AiProviderConfig config,
  ) {
    final messages = openaiBody['messages'] as List<dynamic>?;
    if (messages == null) return openaiBody;

    // 分离 system 和 非 system 消息
    final systemMessages = <String>[];
    final userMessages = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg is! Map<String, dynamic>) continue;
      final role = msg['role'] as String?;
      final content = msg['content'];

      if (role == 'system') {
        systemMessages.add(_stringContent(content));
      } else {
        userMessages.add(msg);
      }
    }

    final claudeBody = <String, dynamic>{
      'model': openaiBody['model'],
      'messages': userMessages,
      'max_tokens': 4096,
    };

    // 合并所有 system prompt
    if (systemMessages.isNotEmpty) {
      claudeBody['system'] = systemMessages.join('\n\n');
    }

    // thinking 参数映射
    if (config.reasoningEffort != AiReasoningEffort.none) {
      final budgetTokens = switch (config.reasoningEffort) {
        AiReasoningEffort.minimal => 1024,
        AiReasoningEffort.low => 4096,
        AiReasoningEffort.medium => 8192,
        AiReasoningEffort.high => 16384,
        AiReasoningEffort.xhigh => 32768,
        AiReasoningEffort.ultra => 65536,
        _ => 8192,
      };
      claudeBody['thinking'] = {
        'type': 'enabled',
        'budget_tokens': budgetTokens,
      };
    }

    return claudeBody;
  }

  static AiProviderConfig _resolveConfig({
    String? apiKey,
    AiProviderConfig? config,
  }) {
    final provider =
        config ?? AiProviderConfig.deepSeek(apiKey: apiKey?.trim() ?? '');
    if (!provider.hasKey) {
      throw AiConfigException('${provider.providerLabel} API Key 未配置');
    }
    return provider;
  }
}
