import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'ai_data_trimmer.dart';
import 'ai_exception.dart';
import 'ai_http_transport.dart';
import 'ai_logger.dart';
import 'ai_prompt_templates.dart';
import 'ai_provider_config.dart';
import 'ai_request_manager.dart';
import 'openai_codex_oauth.dart';
import 'web_search.dart';
import '../media/chat_attachment.dart';

/// AI 查询服务 V2：集成流式响应、日志、异常处理、数据裁剪、并发控制、
/// Token 计数、fallback 等优化。
///
/// 向后兼容原有 LlmQuery API，同时提供新的流式接口。
class LlmQueryV2 {
  LlmQueryV2._();

  // Keep the shared transport lazy so Android's proxy/VPN bridge installed in
  // main() is applied before the first non-streaming request. Streaming turns
  // create a short-lived transport below to avoid reusing a poisoned socket.
  static AiHttpTransport? _sharedTransport;

  static AiHttpTransport get _transport =>
      _sharedTransport ??= AiHttpTransport();

  static const _defaultTimeoutSeconds = 30;
  static const _reportTimeoutSeconds = 90;
  static const _streamTimeoutSeconds = 60;
  static const _streamIdleTimeoutSeconds = 75;

  static Future<String?> _imageDataUri(String? imagePath) async {
    final path = imagePath?.trim() ?? '';
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) {
      throw const AiNetworkException('图片文件不存在');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const AiNetworkException('图片文件为空');
    final ext = path.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static Future<List<Map<String, dynamic>>> _attachmentParts(
    Iterable<ChatAttachment> attachments,
  ) async {
    final parts = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      final file = File(attachment.path);
      if (!await file.exists()) throw const AiNetworkException('附件文件不存在');
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const AiNetworkException('附件文件为空');
      final dataUri =
          'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
      if (attachment.isImage) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': dataUri},
        });
      } else {
        parts.add({
          'type': 'file',
          'file': {
            'filename': attachment.name,
            'file_data': dataUri,
          },
        });
      }
    }
    return parts;
  }

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
    void Function(Iterable<AiWebSource> sources)? onSources,
    void Function(String summary)? onReasoningSummary,
    String? taskId,
    List<Map<String, String>> priorTurns = const [],
    String? imagePath,
    List<ChatAttachment> attachments = const [],
  }) async {
    final tid = taskId ?? 'ask_stream_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    try {
      final provider = await OpenAiCodexOAuth.ensureFreshConfig(
        _resolveConfig(apiKey: apiKey, config: config),
      );
      final webSearch = await AiWebSearchContext.prepare(
        question: question,
        config: provider,
      );

      AiLogger.logQueryStart(
        taskType: 'ask_stream',
        provider: provider.providerLabel,
        model: provider.modelCandidates.first,
        estimatedTokens: AiDataTrimmer.estimateTokens(transactionsText),
      );

      final imageDataUri = await _imageDataUri(imagePath);
      final attachmentParts = await _attachmentParts(attachments);
      if (imageDataUri != null) {
        attachmentParts.insert(0, {
          'type': 'image_url',
          'image_url': {'url': imageDataUri},
        });
      }
      final userContent = attachmentParts.isEmpty
          ? question
          : <Map<String, dynamic>>[
              {'type': 'text', 'text': question},
              ...attachmentParts,
            ];
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': AiPromptTemplates.systemPrompt},
        if (transactionsText.trim().isNotEmpty)
          {'role': 'system', 'content': '账目上下文：\n$transactionsText'},
        if (webSearch.promptBlock.trim().isNotEmpty)
          {'role': 'system', 'content': webSearch.promptBlock},
        ...priorTurns.map(
          (turn) => <String, dynamic>{
            'role': turn['role'] ?? 'user',
            'content': turn['content'] ?? '',
          },
        ),
        {'role': 'user', 'content': userContent},
      ];
      var requestProvider = provider;
      var unauthorizedRetried = false;
      var transientNetworkRetried = false;
      var codexCatalogRetried = false;
      var streamProducedOutput = false;

      void handleChunk(String chunk) {
        if (chunk.isNotEmpty) streamProducedOutput = true;
        onChunk(chunk);
      }

      void handleSources(Iterable<AiWebSource> sources) {
        final sourceList = sources.toList(growable: false);
        if (sourceList.isNotEmpty) streamProducedOutput = true;
        final combined = <AiWebSource>[];
        final seen = <String>{};
        for (final source in [
          ...?webSearch.response?.sources,
          ...sourceList,
        ]) {
          if (source.url.trim().isNotEmpty && seen.add(source.url.trim())) {
            combined.add(source);
          }
        }
        onSources?.call(combined);
      }

      void handleReasoningSummary(String summary) {
        if (summary.trim().isNotEmpty) streamProducedOutput = true;
        onReasoningSummary?.call(summary);
      }

      void handleDone(String fullAnswer) {
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        AiLogger.logQuerySuccess(
          taskType: 'ask_stream',
          provider: requestProvider.providerLabel,
          model: requestProvider.modelCandidates.first,
          durationMs: duration,
        );
        onDone(webSearch.annotateAnswer(fullAnswer));
      }

      Future<void> performStream() => _streamChat(
            config: requestProvider,
            messages: messages,
            timeoutSeconds: _streamTimeoutSeconds,
            onChunk: handleChunk,
            onSources: handleSources,
            onReasoningSummary: handleReasoningSummary,
            onDone: handleDone,
          );

      await AiRequestManager.execute(
        taskId: tid,
        allowConcurrent: false,
        request: () async {
          while (true) {
            try {
              return await performStream();
            } catch (error) {
              final aiError = AiRequestManager.wrapException(error);
              if (!unauthorizedRetried &&
                  !streamProducedOutput &&
                  aiError.statusCode == 401 &&
                  requestProvider.isOpenAiCodexOAuth) {
                unauthorizedRetried = true;
                requestProvider = await OpenAiCodexOAuth.service
                    .refreshAfterUnauthorized(requestProvider);
                continue;
              }
              if (!codexCatalogRetried &&
                  requestProvider.isOpenAiCodexOAuth &&
                  _isUnsupportedModelError(aiError)) {
                codexCatalogRetried = true;
                final refreshed = await _configWithLiveCodexModel(
                  requestProvider,
                );
                if (refreshed != null &&
                    refreshed.model != requestProvider.model) {
                  requestProvider = refreshed;
                  continue;
                }
              }
              // Android may hand the first request to a stale keep-alive
              // socket immediately after app resume or provider hydration.
              // Retry exactly once only before any text, reasoning, or source
              // event has reached the UI. Replaying after visible output would
              // duplicate an answer the user has already started reading.
              if (_shouldRetryFirstPacket(
                aiError,
                streamProducedOutput: streamProducedOutput,
                alreadyRetried: transientNetworkRetried,
              )) {
                transientNetworkRetried = true;
                AiLogger.logRetry(
                  taskType: 'ask_stream_first_packet',
                  provider: requestProvider.providerLabel,
                  fromModel: requestProvider.modelCandidates.first,
                  toModel: requestProvider.modelCandidates.first,
                  reason: aiError.message,
                );
                await Future<void>.delayed(const Duration(milliseconds: 180));
                continue;
              }
              rethrow;
            }
          }
        },
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
      final provider = await OpenAiCodexOAuth.ensureFreshConfig(
        _resolveConfig(apiKey: apiKey, config: config),
      );
      final webSearch = await AiWebSearchContext.prepare(
        question: question,
        config: provider,
      );

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
                if (webSearch.promptBlock.trim().isNotEmpty)
                  {'role': 'system', 'content': webSearch.promptBlock},
                {'role': 'user', 'content': question},
              ],
              'stream': false,
            },
          ).then(webSearch.annotateAnswer),
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
      final provider = await OpenAiCodexOAuth.ensureFreshConfig(
        _resolveConfig(apiKey: apiKey, config: config),
      );
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
      final provider = await OpenAiCodexOAuth.ensureFreshConfig(
        _resolveConfig(config: config),
      );

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
    var models = config.modelCandidates;
    var activeConfig = config;
    var unauthorizedRetried = false;
    var codexCatalogRetried = false;

    for (int i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        var body = bodyForModel(model);

        // Claude 原生端点必须先转换格式，并绕过 Responses 分支。
        if (activeConfig.shouldUseClaudeMessages) {
          body = _convertToClaudeFormat(body, activeConfig);
          return await _postChat(
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
      } catch (e) {
        lastError = AiRequestManager.wrapException(e);

        if (!unauthorizedRetried &&
            lastError.statusCode == 401 &&
            activeConfig.isOpenAiCodexOAuth) {
          unauthorizedRetried = true;
          activeConfig = await OpenAiCodexOAuth.service
              .refreshAfterUnauthorized(activeConfig);
          i--;
          continue;
        }

        if (!codexCatalogRetried &&
            activeConfig.isOpenAiCodexOAuth &&
            _isUnsupportedModelError(lastError)) {
          codexCatalogRetried = true;
          final refreshed = await _configWithLiveCodexModel(activeConfig);
          if (refreshed != null && refreshed.model != activeConfig.model) {
            activeConfig = refreshed;
            models = [refreshed.model];
            i = -1;
            continue;
          }
        }

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

  static bool _isUnsupportedModelError(AiException error) {
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
      // Resolve refresh-only/expired imports through the same config path as
      // normal requests first. Calling fetchModels with a bare access token
      // would discover the catalogue but leave the subsequent retry with an
      // empty or stale bearer token.
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
      // Preserve the original model error; the caller will surface the more
      // useful unsupported-model/authorization response when discovery also
      // cannot reach the official catalogue.
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _postChat({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    final isClaude = config.shouldUseClaudeMessages;
    final uri = isClaude ? config.messagesUri : config.chatCompletionsUri;

    late http.Response resp;

    try {
      final headers = config.authHeaders();

      resp = await _transport.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
        timeout: Duration(seconds: timeoutSeconds),
      );
    } on TimeoutException {
      throw const AiNetworkException('请求超时');
    } catch (e) {
      throw _sanitizeException(
          AiNetworkException('网络请求失败', originalError: e), config.apiKey);
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
          promptTokens:
              usage['prompt_tokens'] as int? ?? usage['input_tokens'] as int?,
          completionTokens: usage['completion_tokens'] as int? ??
              usage['output_tokens'] as int?,
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
        final content =
            (outer['choices'] as List).first['message']['content'] as String;
        text = content.trim();
      }

      if (text.isEmpty) {
        throw const AiEmptyResponseException('AI 返回空内容');
      }

      return text;
    } catch (e) {
      if (e is AiException) rethrow;
      throw _sanitizeException(
          AiResponseParseException('响应解析失败', originalError: e), config.apiKey);
    }
  }

  static Future<void> _streamChat({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
    required int timeoutSeconds,
    required void Function(String chunk) onChunk,
    required void Function(String fullAnswer) onDone,
    void Function(Iterable<AiWebSource> sources)? onSources,
    void Function(String summary)? onReasoningSummary,
  }) async {
    final isClaude = config.shouldUseClaudeMessages;
    final isResponses = !isClaude && config.shouldUseResponses;
    final uri = _streamUri(config);

    final Map<String, dynamic> body;

    if (isClaude) {
      // Claude 原生格式
      final systemMessages =
          messages.where((m) => m['role'] == 'system').toList();
      final userMessages =
          messages.where((m) => m['role'] != 'system').toList();

      final budgetTokens = config.reasoningEffort.claudeBudgetTokens;
      final maxTokens =
          budgetTokens == null ? 4096 : math.max(4096, budgetTokens + 4096);
      body = {
        'model': config.modelCandidates.first,
        'messages': [
          for (final message in userMessages) _messageForClaude(message),
        ],
        'stream': true,
        'max_tokens': maxTokens,
      };

      // 合并 system prompt
      if (systemMessages.isNotEmpty) {
        body['system'] = systemMessages.map((m) => m['content']).join('\n\n');
      }

      // thinking 参数映射
      if (budgetTokens != null) {
        body['thinking'] = {
          'type': 'enabled',
          'budget_tokens': budgetTokens,
        };
        body['temperature'] = 1;
      }
    } else if (isResponses) {
      // Responses API 的流式格式使用 input/instructions，而不是
      // Chat Completions 的 messages。转换器同时注入 reasoning.effort。
      body = _responsesStreamBody(config: config, messages: messages);
    } else {
      body = _chatCompletionsStreamBody(config: config, messages: messages);
    }

    // A stream owns its client for the complete response lifetime. This avoids
    // reusing a poisoned keep-alive socket on the first request after resume;
    // a bounded first-packet retry in askStream therefore gets a fresh socket.
    final streamTransport = AiHttpTransport();
    try {
      late http.StreamedResponse resp;
      try {
        final headers = config.authHeaders();
        var requestBody = body;
        if (config.isOpenAiCodexOAuth) {
          final sessionId = OpenAiCodexOAuth.generateRequestId();
          requestBody = OpenAiCodexOAuth.prepareCodexResponsesBody(
            body,
            sessionId: sessionId,
          );
          headers.addAll(
            OpenAiCodexOAuth.codexRequestHeaders(
              sessionId: sessionId,
              stream: true,
            ),
          );
        }
        final request = http.Request('POST', uri)
          ..headers.addAll(headers)
          ..body = jsonEncode(requestBody);
        resp = await streamTransport.send(
          request,
          timeout: Duration(seconds: timeoutSeconds),
          forceRouteRefresh: true,
        );
      } on TimeoutException {
        throw const AiNetworkException('请求超时');
      } catch (e) {
        throw _sanitizeException(
            AiNetworkException('网络请求失败', originalError: e), config.apiKey);
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
      final webSources = <AiWebSource>[];
      final webSourceUrls = <String>{};
      String? completedAnswer;
      var streamCompleted = false;

      try {
        await for (final line in resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: _streamIdleTimeoutSeconds))) {
          // SSE 用空行分隔事件；它不是流的结束信号。
          if (line.isEmpty) continue;

          if (isClaude) {
            // Claude SSE 格式: "data: {...}"
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6);

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final type = json['type'] as String?;

              if (type == 'content_block_delta') {
                final delta = json['delta'];
                final content = delta?['text'] as String?;
                final thinking = delta?['thinking'] as String?;

                if (thinking != null && thinking.trim().isNotEmpty) {
                  onReasoningSummary?.call(thinking);
                }

                if (content != null && content.isNotEmpty) {
                  fullAnswer.write(content);
                  onChunk(content);
                }
              }
              if (type == 'message_stop') streamCompleted = true;
            } catch (e) {
              if (e is AiException) rethrow;
              AiLogger.logWarning(
                taskType: 'stream_parse_chunk',
                provider: config.providerLabel,
                model: config.modelCandidates.first,
                warning: 'Claude 流式响应单条解析失败: $e',
                extra: {
                  'chunk_data':
                      data.substring(0, data.length > 100 ? 100 : data.length)
                },
              );
            }
          } else if (isResponses) {
            // Responses SSE: response.output_text.delta 携带增量文本。
            // 标准 SSE 会先发 event/注释行，再发 data 行；这些行不是流结束
            // 信号，不能 return 整个 _streamChat，否则上层 Completer 会永久等
            // 不到 onDone/onError。兼容 `data:` 后没有空格的网关。
            if (!line.startsWith('data:')) continue;
            final data = line.substring(5).trimLeft();
            if (data == '[DONE]') {
              streamCompleted = true;
              break;
            }
            try {
              final decoded = jsonDecode(data.trim());
              if (decoded is Map) {
                final event = Map<String, dynamic>.from(decoded);
                for (final source in _extractResponsesSources(event)) {
                  if (webSourceUrls.add(source.url)) webSources.add(source);
                }
                final type = event['type']?.toString().toLowerCase() ?? '';
                final reasoningSummary = _responsesReasoningSummaryDelta(event);
                if (reasoningSummary != null) {
                  onReasoningSummary?.call(reasoningSummary);
                }
                if (type == 'response.failed') {
                  final response = event['response'];
                  final error = response is Map ? response['error'] : null;
                  final message = error is Map
                      ? error['message']?.toString()
                      : error?.toString();
                  throw AiServerException(
                    (message == null || message.trim().isEmpty)
                        ? 'Responses 生成失败'
                        : message.trim(),
                  );
                }
                if (type == 'response.incomplete') {
                  final response = event['response'];
                  final details =
                      response is Map ? response['incomplete_details'] : null;
                  final reason = details is Map
                      ? details['reason']?.toString()
                      : details?.toString();
                  throw AiTokenLimitException(
                    reason == null || reason.trim().isEmpty
                        ? 'Responses 输出未完成'
                        : 'Responses 输出未完成：${reason.trim()}',
                  );
                }
                if (type == 'response.output_text.done') {
                  final text = event['text'];
                  if (text is String && text.trim().isNotEmpty) {
                    completedAnswer = text;
                  }
                } else if (type == 'response.completed') {
                  final response = event['response'];
                  if (response is Map) {
                    final text = _extractResponsesText(
                      Map<String, dynamic>.from(response),
                    );
                    if (text.isNotEmpty) completedAnswer = text;
                  }
                  streamCompleted = true;
                }
              }
              final content = _responsesStreamDelta(data);
              if (content != null) {
                fullAnswer.write(content);
                onChunk(content);
              }
            } catch (e) {
              if (e is AiException) rethrow;
              AiLogger.logWarning(
                taskType: 'stream_parse_chunk',
                provider: config.providerLabel,
                model: config.modelCandidates.first,
                warning: 'Responses 流式响应单条解析失败: $e',
                extra: {
                  'chunk_data':
                      data.substring(0, data.length > 100 ? 100 : data.length)
                },
              );
            }
          } else {
            // OpenAI 格式
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6);
            if (data == '[DONE]') {
              streamCompleted = true;
              break;
            }

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
                extra: {
                  'chunk_data':
                      data.substring(0, data.length > 100 ? 100 : data.length)
                },
              );
            }
          }

          // 服务端可能在业务终止事件后保持 HTTP 连接；无需等物理断连。
          if (streamCompleted) break;
        }

        final streamedAnswer = fullAnswer.toString();
        // `response.output_text.done`/`response.completed` may carry the
        // provider's canonical full text after a gateway emitted only part of
        // the deltas. Prefer it when it is at least as complete; otherwise
        // retain the longer accumulated stream so a malformed final event
        // cannot erase text the user already saw.
        final finalAnswer = completedAnswer?.trim() ?? '';
        final rawAnswer = finalAnswer.isNotEmpty &&
                finalAnswer.length >= streamedAnswer.trim().length
            ? finalAnswer
            : streamedAnswer;
        final answer = AiWebSearchContext.formatAnswerWithSources(
          rawAnswer,
          config.webSearchEnabled ? webSources : const [],
        );
        if (answer.trim().isEmpty) {
          throw const AiEmptyResponseException('Responses 流式响应为空');
        }
        onSources?.call(webSources);
        onDone(answer);
      } on TimeoutException {
        throw const AiNetworkException('流式响应超时，服务端长时间没有返回内容');
      } on AiException {
        rethrow;
      } catch (e) {
        throw _sanitizeException(
            AiResponseParseException('流式响应解析失败', originalError: e),
            config.apiKey);
      }
    } finally {
      streamTransport.close();
    }
  }

  static Future<String> _postResponses({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
    required int timeoutSeconds,
  }) async {
    final isCodex = config.isOpenAiCodexOAuth;
    final sessionId = isCodex ? OpenAiCodexOAuth.generateRequestId() : null;
    // Official ChatGPT/Codex Responses rejects buffered requests with
    // `Stream must be set to true`. Reports, connection tests, and regular
    // `ask()` calls all share this method, so enforce the Codex wire contract
    // here instead of relying on each caller to remember the flag.
    final codexBody = _responsesTransportBody(
      config: config,
      body: body,
    );
    final requestBody = sessionId == null
        ? codexBody
        : OpenAiCodexOAuth.prepareCodexResponsesBody(
            codexBody,
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
      resp = await _transport.post(
        config.responsesUri,
        headers: headers,
        body: jsonEncode(requestBody),
        timeout: Duration(seconds: timeoutSeconds),
        forceRouteRefresh: true,
      );
    } on TimeoutException {
      throw const AiNetworkException('请求超时');
    } catch (e) {
      throw _sanitizeException(
          AiNetworkException('网络请求失败', originalError: e), config.apiKey);
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
      final String text;
      if (config.isOpenAiCodexOAuth) {
        final raw = _extractResponsesSseText(bodyText).trim();
        text = AiWebSearchContext.formatAnswerWithSources(
          raw,
          config.webSearchEnabled
              ? _extractResponsesSseSources(bodyText)
              : const [],
        );
      } else {
        final outer = jsonDecode(bodyText) as Map<String, dynamic>;
        final raw = _extractResponsesText(outer).trim();
        text = AiWebSearchContext.formatAnswerWithSources(
          raw,
          config.webSearchEnabled ? _extractResponsesSources(outer) : const [],
        );
      }

      if (text.isEmpty) {
        throw const AiEmptyResponseException('Responses 返回空内容');
      }

      return text;
    } catch (e) {
      if (e is AiException) rethrow;
      throw _sanitizeException(
          AiResponseParseException('Responses 响应解析失败', originalError: e),
          config.apiKey);
    }
  }

  static String _extractResponsesSseText(String body) {
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
            final response = event['response'];
            final error = response is Map ? response['error'] : null;
            final message =
                error is Map ? error['message']?.toString() : error?.toString();
            throw AiServerException(
              message == null || message.trim().isEmpty
                  ? 'Responses 生成失败'
                  : message.trim(),
            );
          }
          if (type == 'response.incomplete') {
            throw const AiTokenLimitException('Responses 输出未完成');
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
        }
        final delta = _responsesStreamDelta(data);
        if (delta != null) buffer.write(delta);
      } on AiException {
        rethrow;
      } catch (_) {
        // Ignore non-JSON SSE comments and vendor-specific events.
      }
    }
    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : (completed ?? '');
  }

  static List<AiWebSource> _extractResponsesSseSources(String body) {
    final result = <AiWebSource>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data == '[DONE]') break;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          for (final source in _extractResponsesSources(
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

  static Map<String, dynamic> _messageForClaude(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is! List) return message;
    return {
      ...message,
      'content': [
        for (final part in content)
          if (part is Map && part['type'] == 'text')
            {'type': 'text', 'text': part['text']?.toString() ?? ''}
          else if (part is Map && part['type'] == 'image_url')
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': _mimeFromDataUri(
                  (part['image_url'] is Map ? part['image_url']['url'] : null)
                      ?.toString(),
                ),
                'data': _base64FromDataUri(
                  (part['image_url'] is Map ? part['image_url']['url'] : null)
                      ?.toString(),
                ),
              },
            }
          else if (part is Map && part['type'] == 'file')
            {
              'type': 'document',
              'source': {
                'type': 'base64',
                'media_type': _mimeFromDataUri(
                  (part['file'] is Map ? part['file']['file_data'] : null)
                      ?.toString(),
                ),
                'data': _base64FromDataUri(
                  (part['file'] is Map ? part['file']['file_data'] : null)
                      ?.toString(),
                ),
              },
              'title': (part['file'] is Map ? part['file']['filename'] : null)
                  ?.toString(),
            },
      ],
    };
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
        final rawContent = item['content'];
        final content = _stringContent(rawContent).trim();
        if (content.isEmpty && rawContent is! List) continue;

        if (role == 'system' || role == 'developer') {
          instructions.add(content);
        } else if (role == 'assistant') {
          inputParts.add('assistant: $content');
        } else {
          inputParts.add(content);
        }
      }
    }

    final imageMessage = messages is List
        ? messages.whereType<Map>().where((item) {
            final content = item['content'];
            return content is List &&
                content.any((part) =>
                    part is Map &&
                    (part['type'] == 'image_url' || part['type'] == 'file'));
          }).toList()
        : const <Map>[];
    final body = <String, dynamic>{
      'model': chatBody['model'],
      'input': imageMessage.isEmpty
          ? inputParts.join('\n\n').trim()
          : _responsesInputFromMessages(messages),
      // Ledger context is user data; never opt into the Responses service's
      // server-side retention default for public OpenAI or compatible relays.
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

  static List<Map<String, dynamic>> _responsesInputFromMessages(
    Object? rawMessages,
  ) {
    if (rawMessages is! List) return const [];
    final input = <Map<String, dynamic>>[];
    for (final item in rawMessages) {
      if (item is! Map) continue;
      final role = (item['role']?.toString().trim().toLowerCase() ?? 'user');
      if (role == 'system' || role == 'developer') continue;
      final content = item['content'];
      final parts = <Map<String, dynamic>>[];
      if (content is List) {
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            parts.add({
              'type': role == 'assistant' ? 'output_text' : 'input_text',
              'text': part['text']?.toString() ?? '',
            });
          } else if (part is Map && part['type'] == 'image_url') {
            parts.add({
              'type': 'input_image',
              'image_url':
                  (part['image_url'] is Map ? part['image_url']['url'] : null)
                      ?.toString(),
            });
          } else if (part is Map && part['type'] == 'file') {
            parts.add({
              'type': 'input_file',
              'filename':
                  (part['file'] is Map ? part['file']['filename'] : null)
                      ?.toString(),
              'file_data':
                  (part['file'] is Map ? part['file']['file_data'] : null)
                      ?.toString(),
            });
          }
        }
      } else if (content != null) {
        parts.add({
          'type': role == 'assistant' ? 'output_text' : 'input_text',
          'text': content.toString(),
        });
      }
      if (parts.isNotEmpty) {
        input.add({
          'type': 'message',
          'role': role == 'assistant' ? 'assistant' : 'user',
          'content': parts,
        });
      }
    }
    return input;
  }

  static String _mimeFromDataUri(String? uri) {
    final match = RegExp(r'^data:([^;]+);base64,').firstMatch(uri ?? '');
    return match?.group(1) ?? 'image/jpeg';
  }

  static String _base64FromDataUri(String? uri) {
    final value = uri ?? '';
    final comma = value.indexOf(',');
    return comma < 0 ? value : value.substring(comma + 1);
  }

  /// ChatGPT subscription OAuth is backed by the Codex Responses endpoint,
  /// whose wire contract is stricter than the public OpenAI Responses API:
  /// instructions must be non-empty, input must be a message array, and the
  /// endpoint only accepts streamed, non-stored responses.
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
        final rawContent = item['content'];
        final content = _stringContent(rawContent).trim();
        if (content.isEmpty && rawContent is! List) continue;
        if (role == 'system' || role == 'developer') {
          instructions.add(content);
          continue;
        }
        final outputType = role == 'assistant' ? 'output_text' : 'input_text';
        input.add(
          rawContent is List &&
                  rawContent.any(
                    (part) =>
                        part is Map &&
                        (part['type'] == 'image_url' || part['type'] == 'file'),
                  )
              ? _responsesInputFromMessages([item]).single
              : {
                  'type': 'message',
                  'role': role == 'assistant' ? 'assistant' : 'user',
                  'content': [
                    {'type': outputType, 'text': content},
                  ],
                },
        );
      }
    }

    final body = <String, dynamic>{
      'model': chatBody['model'],
      'instructions': instructions.join('\n\n').trim().isEmpty
          ? 'You are a helpful assistant.'
          : instructions.join('\n\n').trim(),
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

  static Map<String, dynamic> _responsesStreamBody({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
  }) {
    return _responsesBodyFromChatBody(
      {
        'model': config.modelCandidates.first,
        'messages': messages,
        'max_tokens': config.reasoningEffort.responsesMaxOutputTokens,
      },
      config,
    )..['stream'] = true;
  }

  static Map<String, dynamic> _chatCompletionsStreamBody({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
  }) {
    final body = <String, dynamic>{
      'model': config.modelCandidates.first,
      'messages': messages,
      'stream': true,
    };
    // DeepSeek 的原生 SSE 是 Chat Completions，但当前模型支持
    // reasoning_effort。显式开启 thinking，以免服务端默认策略改变时
    // Effort 滑条变成只有视觉反馈。
    final effort =
        config.isDeepSeek ? config.reasoningEffort.deepSeekApiValue : null;
    if (effort != null) {
      body['thinking'] = const {'type': 'enabled'};
      body['reasoning_effort'] = effort;
    }
    return body;
  }

  static Uri _streamUri(AiProviderConfig config) {
    if (config.shouldUseClaudeMessages) return config.messagesUri;
    if (config.shouldUseResponses) return config.responsesUri;
    return config.chatCompletionsUri;
  }

  /// 从一条 Responses SSE data 负载中提取真正的文本增量。
  ///
  /// 官方会在 `response.output_text.done` 里重发完整文本；该事件不能
  /// 当作增量写入，否则流式回答会在结束时重复一遍。
  static String? _responsesStreamDelta(String data) {
    final payload = data.trim();
    if (payload.isEmpty || payload == '[DONE]') return null;

    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);
    final type = json['type']?.toString().toLowerCase() ?? '';

    // 标准 Responses 协议：`delta` 是唯一可追加的文本字段。
    final delta = json['delta'];
    if (delta is String &&
        delta.isNotEmpty &&
        (type.contains('output_text.delta') ||
            type.contains('content_part.delta') ||
            type.isEmpty)) {
      return delta;
    }

    // 部分兼容网关未标注 event type，直接用 text/output_text 放增量。
    // 正式 `*.done`/`*.completed` 会带完整文本，必须过滤以避免重复。
    final isTerminal = type.endsWith('.done') || type.contains('completed');
    if (isTerminal ||
        (!type.contains('output_text') &&
            !type.contains('content_part') &&
            type.isNotEmpty)) {
      return null;
    }
    final fallback = json['text'] ?? json['output_text'];
    return fallback is String && fallback.isNotEmpty ? fallback : null;
  }

  /// Only provider-authored, user-displayable reasoning summary deltas are
  /// surfaced. App-side phase labels are deliberately excluded so the UI does
  /// not invent a process such as “organising the answer”. `done` events often
  /// repeat the full summary after deltas and therefore must not be appended.
  static String? _responsesReasoningSummaryDelta(
    Map<String, dynamic> event,
  ) {
    final type = event['type']?.toString().trim().toLowerCase() ?? '';
    if (!type.contains('reasoning') || !type.contains('summary')) return null;
    if (type.endsWith('.done')) return null;

    final delta = event['delta'];
    if (delta is String && delta.trim().isNotEmpty) return delta;
    if (delta is Map) {
      final text = (delta['text'] ?? delta['content'])?.toString() ?? '';
      if (text.trim().isNotEmpty) return text;
    }
    final part = event['part'];
    if (part is Map) {
      final text = (part['text'] ?? part['content'])?.toString() ?? '';
      if (text.trim().isNotEmpty) return text;
    }
    return null;
  }

  static String? _responsesCompletedText(String data) {
    final payload = data.trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final event = Map<String, dynamic>.from(decoded);
    if (event['type']?.toString().toLowerCase() != 'response.completed') {
      return null;
    }
    final response = event['response'];
    if (response is! Map) return null;
    return _extractResponsesText(Map<String, dynamic>.from(response));
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

  /// Responses places web citations in `annotations` on output text parts.
  /// Walk the complete response because gateways differ in whether they put
  /// the annotations on the output item, content part, or terminal event.
  static List<AiWebSource> _extractResponsesSources(Object? outer) =>
      AiWebSearchContext.extractResponseSources(outer);

  static String _bodySnippet(String body) {
    final text = AiLogger.sanitizeErrorForDisplay(body)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return '';
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }

  /// 清理异常消息中的 API Key
  static AiException _sanitizeException(AiException exception, String apiKey) {
    // 清理异常消息
    var sanitizedMessage = exception.message;
    if (apiKey.isNotEmpty) {
      sanitizedMessage = sanitizedMessage.replaceAll(
        apiKey,
        '[API_KEY_REDACTED]',
      );
    }
    sanitizedMessage = AiLogger.sanitizeErrorForDisplay(sanitizedMessage);

    // 清理 originalError 中的 API Key（如果是 Exception）
    Object? sanitizedOriginalError = exception.originalError;
    if (sanitizedOriginalError is Exception) {
      final originalErrorString = sanitizedOriginalError.toString();
      var sanitizedOriginal = originalErrorString;
      if (apiKey.isNotEmpty) {
        sanitizedOriginal = sanitizedOriginal.replaceAll(
          apiKey,
          '[API_KEY_REDACTED]',
        );
      }
      sanitizedOriginal = AiLogger.sanitizeErrorForDisplay(sanitizedOriginal);
      if (sanitizedOriginal != originalErrorString) {
        sanitizedOriginalError = Exception(sanitizedOriginal);
      }
    }

    // 根据异常类型重建
    if (exception is AiNetworkException) {
      return AiNetworkException(sanitizedMessage,
          originalError: sanitizedOriginalError);
    } else if (exception is AiAuthException) {
      return AiAuthException(sanitizedMessage,
          statusCode: exception.statusCode);
    } else if (exception is AiRateLimitException) {
      return AiRateLimitException(
        sanitizedMessage,
        statusCode: exception.statusCode,
        retryAfterSeconds: exception.retryAfterSeconds,
      );
    } else if (exception is AiTokenLimitException) {
      return AiTokenLimitException(sanitizedMessage,
          statusCode: exception.statusCode);
    } else if (exception is AiServerException) {
      return AiServerException(sanitizedMessage,
          statusCode: exception.statusCode);
    } else if (exception is AiResponseParseException) {
      return AiResponseParseException(sanitizedMessage,
          originalError: sanitizedOriginalError);
    } else if (exception is AiConfigException) {
      return AiConfigException(sanitizedMessage);
    } else if (exception is AiModelNotSupportedException) {
      return AiModelNotSupportedException(sanitizedMessage,
          statusCode: exception.statusCode);
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
  static AiException sanitizeExceptionForTest(
          AiException exception, String apiKey) =>
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

  static bool _shouldRetryFirstPacket(
    AiException error, {
    required bool streamProducedOutput,
    required bool alreadyRetried,
  }) =>
      error is AiNetworkException && !streamProducedOutput && !alreadyRetried;

  /// 测试辅助：首包网络重试只允许发生一次，且任何可见输出后禁止重放。
  @visibleForTesting
  static bool shouldRetryFirstPacketForTest(
    AiException error, {
    required bool streamProducedOutput,
    required bool alreadyRetried,
  }) =>
      _shouldRetryFirstPacket(
        error,
        streamProducedOutput: streamProducedOutput,
        alreadyRetried: alreadyRetried,
      );

  /// 测试辅助：判断是否应该用兼容模型重试
  @visibleForTesting
  static bool shouldRetryWithCompatibleModelForTest(AiException error) {
    return error is AiModelNotSupportedException ||
        error is AiBadRequestException;
  }

  /// 测试辅助：构造喵助手实际使用的 Responses 流式请求体。
  @visibleForTesting
  static Map<String, dynamic> responsesStreamBodyForTest({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
  }) =>
      _responsesStreamBody(config: config, messages: messages);

  /// Test the final buffered-Responses transport invariant without opening a
  /// network connection. The official ChatGPT/Codex endpoint rejects
  /// `stream: false`, including when the caller is the non-streaming `ask()`
  /// or connection-test path.
  @visibleForTesting
  static Map<String, dynamic> responsesTransportBodyForTest({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
  }) =>
      _responsesTransportBody(config: config, body: body);

  static Map<String, dynamic> _responsesTransportBody({
    required AiProviderConfig config,
    required Map<String, dynamic> body,
  }) =>
      config.isOpenAiCodexOAuth ? {...body, 'stream': true} : body;

  /// 测试辅助：构造 Chat Completions 流式请求体（含 DeepSeek Effort 映射）。
  @visibleForTesting
  static Map<String, dynamic> chatCompletionsStreamBodyForTest({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
  }) =>
      _chatCompletionsStreamBody(config: config, messages: messages);

  /// 测试辅助：确认 Claude Messages 的图片/文件 block wire format。
  @visibleForTesting
  static Map<String, dynamic> messageForClaudeForTest(
          Map<String, dynamic> message) =>
      _messageForClaude(message);

  /// 测试辅助：从一条 SSE `data:` 负载取出可追加的文本增量。
  @visibleForTesting
  static String? responsesStreamDeltaForTest(String data) =>
      _responsesStreamDelta(data);

  @visibleForTesting
  static String? responsesCompletedTextForTest(String data) =>
      _responsesCompletedText(data);

  @visibleForTesting
  static String? responsesReasoningSummaryDeltaForTest(
          Map<String, dynamic> event) =>
      _responsesReasoningSummaryDelta(event);

  /// 测试辅助：确认喵助手流式请求选用的服务端端点。
  @visibleForTesting
  static Uri streamUriForTest(AiProviderConfig config) => _streamUri(config);

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

    final budgetTokens = config.reasoningEffort.claudeBudgetTokens;
    final requestedMaxTokens = (openaiBody['max_tokens'] as int?) ?? 4096;
    final maxTokens = budgetTokens == null
        ? requestedMaxTokens
        : math.max(requestedMaxTokens, budgetTokens + 4096);
    final claudeBody = <String, dynamic>{
      'model': openaiBody['model'],
      'messages': userMessages,
      'max_tokens': maxTokens,
    };

    // 合并所有 system prompt
    if (systemMessages.isNotEmpty) {
      claudeBody['system'] = systemMessages.join('\n\n');
    }

    // thinking 参数映射
    if (budgetTokens != null) {
      claudeBody['thinking'] = {
        'type': 'enabled',
        'budget_tokens': budgetTokens,
      };
      claudeBody['temperature'] = 1;
    }

    return claudeBody;
  }

  static AiProviderConfig _resolveConfig({
    String? apiKey,
    AiProviderConfig? config,
  }) {
    final provider =
        config ?? AiProviderConfig.deepSeek(apiKey: apiKey?.trim() ?? '');
    if (!provider.hasCredential) {
      throw AiConfigException(
          '${provider.providerLabel} API Key 或 OAuth 凭据未配置');
    }
    if (!provider.hasBaseUrl) {
      throw AiConfigException('${provider.providerLabel} 基础地址未配置');
    }
    if (!provider.hasModel) {
      throw AiConfigException('${provider.providerLabel} 模型未配置');
    }
    return provider;
  }
}
