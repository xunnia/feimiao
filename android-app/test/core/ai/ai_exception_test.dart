import 'package:flutter_test/flutter_test.dart';

import 'package:qingji/core/ai/ai_exception.dart';

void main() {
  group('AiException', () {
    test('AiNetworkException 应该建议重试', () {
      const error = AiNetworkException('连接超时');

      expect(error.shouldRetry, true);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, '网络连接失败');
    });

    test('AiAuthException 应该建议 fallback', () {
      const error = AiAuthException('API key 无效', statusCode: 401);

      expect(error.shouldRetry, false);
      expect(error.shouldFallback, true);
      expect(error.userFriendlyMessage, 'API 密钥无效');
    });

    test('AiRateLimitException 应该显示等待时间', () {
      const error = AiRateLimitException(
        '请求过于频繁',
        statusCode: 429,
        retryAfterSeconds: 60,
      );

      expect(error.shouldRetry, true);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, contains('60 秒'));
    });

    test('AiRateLimitException 无等待时间时给通用提示', () {
      const error = AiRateLimitException('请求过于频繁', statusCode: 429);

      expect(error.userFriendlyMessage, '请求过于频繁，请稍后再试');
    });

    test('AiTokenLimitException 不应重试', () {
      const error = AiTokenLimitException('Token 超限', statusCode: 400);

      expect(error.shouldRetry, false);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, '账目数据太多，喵暂时看不过来');
    });

    test('AiServerException 应该重试和 fallback', () {
      const error = AiServerException('服务器错误', statusCode: 500);

      expect(error.shouldRetry, true);
      expect(error.shouldFallback, true);
      expect(error.userFriendlyMessage, 'AI 服务暂时不可用，请稍后再试');
    });

    test('AiModelNotSupportedException 不应重试和 fallback', () {
      const error = AiModelNotSupportedException('模型不存在', statusCode: 404);

      expect(error.shouldRetry, false);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, '当前模型不可用，正在尝试备用模型');
    });

    test('AiEmptyResponseException 应该重试', () {
      const error = AiEmptyResponseException('返回空内容');

      expect(error.shouldRetry, true);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, 'AI 未返回有效内容，请重试');
    });

    test('AiConfigException 不应重试', () {
      const error = AiConfigException('API key 未配置');

      expect(error.shouldRetry, false);
      expect(error.shouldFallback, false);
      expect(error.userFriendlyMessage, 'API key 未配置');
    });

    test('toString 应该包含错误类型和消息', () {
      const error = AiNetworkException('连接失败');

      expect(error.toString(), 'AiNetworkException: 连接失败');
    });
  });
}
