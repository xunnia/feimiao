import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';

void main() {
  group('LlmQueryV2 API Key 保护测试', () {
    const testApiKey = 'sk-1234567890abcdef';
    const sanitizedKey = '[API_KEY_REDACTED]';

    test('_sanitizeException 应该替换 AiNetworkException 消息中的 API Key', () {
      final exception = AiNetworkException('请求失败: $testApiKey 无效');
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      expect(sanitized.message, contains(sanitizedKey));
      expect(sanitized.message, isNot(contains(testApiKey)));
    });

    test('_sanitizeException 应该替换 AiAuthException 消息中的 API Key', () {
      final exception =
          AiAuthException('认证失败: API key $testApiKey', statusCode: 401);
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      expect(sanitized.message, contains(sanitizedKey));
      expect(sanitized.message, isNot(contains(testApiKey)));
      expect((sanitized as AiAuthException).statusCode, 401);
    });

    test('_sanitizeException 应该替换 AiRateLimitException 消息中的 API Key', () {
      final exception = AiRateLimitException(
        '限流: $testApiKey 超限',
        statusCode: 429,
        retryAfterSeconds: 60,
      );
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      expect(sanitized.message, contains(sanitizedKey));
      expect(sanitized.message, isNot(contains(testApiKey)));
      expect((sanitized as AiRateLimitException).statusCode, 429);
      expect(sanitized.retryAfterSeconds, 60);
    });

    test('_sanitizeException 应该替换 AiResponseParseException 的 originalError',
        () {
      final originalError = Exception('解析失败: $testApiKey 相关错误');
      final exception =
          AiResponseParseException('响应解析失败', originalError: originalError);
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      final sanitizedOriginal = sanitized.originalError.toString();
      expect(sanitizedOriginal, contains(sanitizedKey));
      expect(sanitizedOriginal, isNot(contains(testApiKey)));
    });

    test('_sanitizeException 应该保留没有 API Key 的异常不变', () {
      final exception = AiNetworkException('普通网络错误');
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      expect(sanitized.message, '普通网络错误');
    });

    test('_sanitizeException 空 API Key 时应返回原异常', () {
      final exception = AiNetworkException('错误包含 sk-test');
      final sanitized = LlmQueryV2.sanitizeExceptionForTest(exception, '');

      expect(sanitized.message, '错误包含 sk-test');
    });

    test('_sanitizeException 应该处理 AiUnknownException', () {
      final originalError = Exception('未知错误: $testApiKey');
      final exception = AiUnknownException(
        '查询失败: $testApiKey',
        statusCode: 500,
        originalError: originalError,
      );
      final sanitized =
          LlmQueryV2.sanitizeExceptionForTest(exception, testApiKey);

      expect(sanitized.message, contains(sanitizedKey));
      expect(sanitized.message, isNot(contains(testApiKey)));
      expect((sanitized as AiUnknownException).statusCode, 500);
      expect(sanitized.originalError.toString(), contains(sanitizedKey));
    });
  });
}
