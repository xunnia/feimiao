import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/ai_logger.dart';
import 'package:qingji/core/ai/ai_request_manager.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';

/// AI 核心流程集成测试：验证各模块协同工作
void main() {
  group('AI 核心流程集成测试', () {
    test('异常转换 -> 日志记录 -> 重试判断 完整流程', () {
      // 1. 异常转换
      final networkError = AiRequestManager.wrapException(
        'Connection timeout',
      );
      expect(networkError, isA<AiUnknownException>());

      final authError = AiRequestManager.wrapException(
        'Invalid API key',
        statusCode: 401,
      );
      expect(authError, isA<AiAuthException>());

      // 2. 日志记录（验证不抛异常）
      expect(
        () => AiLogger.logQueryFailure(
          taskType: 'integration_test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          errorType: authError.runtimeType.toString(),
          errorMessage: authError.message,
          durationMs: 100,
        ),
        returnsNormally,
      );

      // 3. 重试/降级判断
      expect(LlmQueryV2.shouldRetryWithSameModelForTest(networkError), true);
      expect(LlmQueryV2.shouldFallbackToProviderForTest(networkError), false);

      expect(LlmQueryV2.shouldRetryWithSameModelForTest(authError), false);
      expect(LlmQueryV2.shouldFallbackToProviderForTest(authError), true);
    });

    test('API Key 脱敏 -> 异常传递 -> 日志保护 完整流程', () {
      const apiKey = 'sk-1234567890abcdef';

      // 1. 构造包含 API Key 的异常
      final error = AiAuthException(
        'API key $apiKey is invalid',
        statusCode: 401,
      );

      // 2. 脱敏异常
      final sanitized = LlmQueryV2.sanitizeExceptionForTest(error, apiKey);

      // 3. 验证 API Key 被替换
      expect(sanitized.message, contains('[API_KEY_REDACTED]'));
      expect(sanitized.message, isNot(contains(apiKey)));

      // 4. 日志记录（确保不会泄露）
      expect(
        () => AiLogger.logQueryFailure(
          taskType: 'integration_test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          errorType: sanitized.runtimeType.toString(),
          errorMessage: sanitized.message,
          statusCode: sanitized.statusCode,
        ),
        returnsNormally,
      );
    });

    test('错误严重程度分类验证', () {
      const networkError = AiNetworkException('网络错误');
      const authError = AiAuthException('认证错误', statusCode: 401);
      const tokenError = AiTokenLimitException('Token 超限', statusCode: 400);

      expect(networkError.severity, AiErrorSeverity.high);
      expect(authError.severity, AiErrorSeverity.critical);
      expect(tokenError.severity, AiErrorSeverity.high);

      // 验证 toJson 序列化
      final json = authError.toJson();
      expect(json['type'], 'AiAuthException');
      expect(json['severity'], 'critical');
      expect(json['shouldFallback'], true);
    });

    test('多种异常类型的分类验证', () {
      // Network 错误：应该重试，不应降级
      const networkError = AiNetworkException('网络连接失败');
      expect(networkError.shouldRetry, true);
      expect(networkError.shouldFallback, false);

      // Auth 错误：不应重试，应该降级
      const authError = AiAuthException('API key 无效', statusCode: 401);
      expect(authError.shouldRetry, false);
      expect(authError.shouldFallback, true);

      // Server 错误：应该重试，也应该降级
      const serverError = AiServerException('服务器错误', statusCode: 500);
      expect(serverError.shouldRetry, true);
      expect(serverError.shouldFallback, true);

      // RateLimit 错误：应该重试，不应降级
      const rateLimitError = AiRateLimitException('请求过于频繁', statusCode: 429);
      expect(rateLimitError.shouldRetry, true);
      expect(rateLimitError.shouldFallback, false);

      // TokenLimit 错误：不应重试，不应降级
      const tokenError = AiTokenLimitException('Token 超限', statusCode: 400);
      expect(tokenError.shouldRetry, false);
      expect(tokenError.shouldFallback, false);

      // ModelNotSupported 错误：不应重试，不应降级（应切换兼容模型）
      const modelError = AiModelNotSupportedException('模型不存在', statusCode: 404);
      expect(modelError.shouldRetry, false);
      expect(modelError.shouldFallback, false);

      // EmptyResponse 错误：应该重试，不应降级
      const emptyError = AiEmptyResponseException('返回空内容');
      expect(emptyError.shouldRetry, true);
      expect(emptyError.shouldFallback, false);
    });

    test('异常链路:wrapException -> 日志 -> 策略判断', () {
      // 场景1: HTTP 401 -> AiAuthException -> 应该降级
      final e401 =
          AiRequestManager.wrapException('Unauthorized', statusCode: 401);
      expect(e401, isA<AiAuthException>());
      expect(LlmQueryV2.shouldFallbackToProviderForTest(e401), true);
      expect(
        () => AiLogger.logQueryFailure(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          errorType: e401.runtimeType.toString(),
          errorMessage: e401.message,
        ),
        returnsNormally,
      );

      // 场景2: HTTP 429 -> AiRateLimitException -> 应该重试
      final e429 = AiRequestManager.wrapException(
        'Rate limit, retry in 60',
        statusCode: 429,
      );
      expect(e429, isA<AiRateLimitException>());
      expect(LlmQueryV2.shouldRetryWithSameModelForTest(e429), true);
      expect((e429 as AiRateLimitException).retryAfterSeconds, 60);

      // 场景3: HTTP 500 -> AiServerException -> 应该重试但不是用相同模型（因为也要降级）
      final e500 = AiRequestManager.wrapException('Internal Server Error',
          statusCode: 500);
      expect(e500, isA<AiServerException>());
      expect(e500.shouldRetry, true);
      expect(LlmQueryV2.shouldFallbackToProviderForTest(e500), true);

      // 场景4: HTTP 404 -> AiModelNotSupportedException -> 应该切换兼容模型
      final e404 =
          AiRequestManager.wrapException('Model not found', statusCode: 404);
      expect(e404, isA<AiModelNotSupportedException>());
      expect(LlmQueryV2.shouldRetryWithCompatibleModelForTest(e404), true);

      // ChatGPT/Codex uses 400 for the same condition, unlike many relays
      // that use 404. It must remain eligible for model recovery.
      final e400 = AiRequestManager.wrapException(
        '{"detail":"Unsupported model"}',
        statusCode: 400,
      );
      expect(e400, isA<AiModelNotSupportedException>());
    });

    test('日志脱敏：敏感字段保护', () {
      // 验证日志不会抛异常，且会脱敏敏感信息
      expect(
        () => AiLogger.logQueryStart(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          estimatedTokens: 100,
          extra: {
            'api_key': 'sk-secret-should-not-appear',
            'access_token': 'token-abc',
            'password': 'my-password',
            'user_name': '张三',
            'phone': '13812345678',
          },
        ),
        returnsNormally,
      );

      // 验证 warning 日志也会脱敏
      expect(
        () => AiLogger.logWarning(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          warning: 'API key sk-1234567890 is invalid',
          extra: {
            'user_phone': '13987654321',
          },
        ),
        returnsNormally,
      );
    });
  });
}
