import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';

void main() {
  group('LlmQueryV2 模型降级测试', () {
    test('_shouldFallbackToProvider 应该在 Auth 错误时触发降级', () {
      const error = AiAuthException('API key 无效', statusCode: 401);
      final result = LlmQueryV2.shouldFallbackToProviderForTest(error);
      expect(result, true);
    });

    test('_shouldFallbackToProvider 应该在 Server 错误时触发降级', () {
      const error = AiServerException('服务器错误', statusCode: 500);
      final result = LlmQueryV2.shouldFallbackToProviderForTest(error);
      expect(result, true);
    });

    test('_shouldFallbackToProvider 应该在 Network 错误时不触发降级', () {
      const error = AiNetworkException('网络连接失败');
      final result = LlmQueryV2.shouldFallbackToProviderForTest(error);
      expect(result, false);
    });

    test('_shouldFallbackToProvider 应该在 TokenLimit 错误时不触发降级', () {
      const error = AiTokenLimitException('Token 超限', statusCode: 400);
      final result = LlmQueryV2.shouldFallbackToProviderForTest(error);
      expect(result, false);
    });

    test('_shouldRetryWithSameModel 应该在 Network 错误时重试', () {
      const error = AiNetworkException('连接超时');
      final result = LlmQueryV2.shouldRetryWithSameModelForTest(error);
      expect(result, true);
    });

    test('_shouldRetryWithSameModel 应该在 RateLimit 错误时重试', () {
      const error = AiRateLimitException('请求过于频繁', statusCode: 429);
      final result = LlmQueryV2.shouldRetryWithSameModelForTest(error);
      expect(result, true);
    });

    test('_shouldRetryWithSameModel 应该在 Auth 错误时不重试', () {
      const error = AiAuthException('API key 无效', statusCode: 401);
      final result = LlmQueryV2.shouldRetryWithSameModelForTest(error);
      expect(result, false);
    });

    test('_shouldRetryWithCompatibleModel 应该在 ModelNotSupported 时触发', () {
      const error = AiModelNotSupportedException('模型不存在', statusCode: 404);
      final result = LlmQueryV2.shouldRetryWithCompatibleModelForTest(error);
      expect(result, true);
    });

    test('_shouldRetryWithCompatibleModel 应该在 BadRequest 时触发', () {
      const error = AiBadRequestException('请求参数错误', statusCode: 400);
      final result = LlmQueryV2.shouldRetryWithCompatibleModelForTest(error);
      expect(result, true);
    });

    test('_shouldRetryWithCompatibleModel 应该在 Network 错误时不触发', () {
      const error = AiNetworkException('网络连接失败');
      final result = LlmQueryV2.shouldRetryWithCompatibleModelForTest(error);
      expect(result, false);
    });
  });

  group('LlmQueryV2 错误分类测试', () {
    test('Network 错误应标记为 shouldRetry=true', () {
      const error = AiNetworkException('连接失败');
      expect(error.shouldRetry, true);
      expect(error.shouldFallback, false);
    });

    test('Auth 错误应标记为 shouldFallback=true', () {
      const error = AiAuthException('密钥无效', statusCode: 401);
      expect(error.shouldRetry, false);
      expect(error.shouldFallback, true);
    });

    test('Server 错误应同时标记 shouldRetry 和 shouldFallback', () {
      const error = AiServerException('服务器错误', statusCode: 500);
      expect(error.shouldRetry, true);
      expect(error.shouldFallback, true);
    });

    test('TokenLimit 错误应两者都为 false', () {
      const error = AiTokenLimitException('Token 超限', statusCode: 400);
      expect(error.shouldRetry, false);
      expect(error.shouldFallback, false);
    });
  });
}
