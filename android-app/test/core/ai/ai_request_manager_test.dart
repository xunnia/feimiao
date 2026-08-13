import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/ai_request_manager.dart';

void main() {
  group('AiRequestManager 并发控制测试', () {
    setUp(() {
      AiRequestManager.cancelAll();
    });

    test('execute allowConcurrent=true 应该允许并发', () async {
      var request1Completed = false;
      var request2Completed = false;

      final future1 = AiRequestManager.execute<String>(
        taskId: 'test-task',
        allowConcurrent: true,
        request: () async {
          await Future.delayed(const Duration(milliseconds: 50));
          request1Completed = true;
          return 'request1';
        },
      );

      final future2 = AiRequestManager.execute<String>(
        taskId: 'test-task',
        allowConcurrent: true,
        request: () async {
          await Future.delayed(const Duration(milliseconds: 50));
          request2Completed = true;
          return 'request2';
        },
      );

      await Future.wait([future1, future2]);

      expect(request1Completed, true);
      expect(request2Completed, true);
    });

    test('execute 应该在请求完成后清理 taskId', () async {
      await AiRequestManager.execute<String>(
        taskId: 'cleanup-task',
        request: () async {
          return 'done';
        },
      );

      // 验证可以用相同 taskId 开启新请求（说明已清理）
      final result = await AiRequestManager.execute<String>(
        taskId: 'cleanup-task',
        request: () async {
          return 'done2';
        },
      );

      expect(result, 'done2');
    });
  });

  group('AiRequestManager 异常转换测试', () {
    test('wrapException 应该保留 AiException', () {
      const original = AiNetworkException('test');
      final wrapped = AiRequestManager.wrapException(original);

      expect(wrapped, same(original));
    });

    test('wrapException 应该转换 TimeoutException', () {
      final timeout = TimeoutException('timeout');
      final wrapped = AiRequestManager.wrapException(timeout);

      expect(wrapped, isA<AiNetworkException>());
      expect(wrapped.message, '请求超时');
    });

    test('wrapException 应该根据状态码转换', () {
      final e401 = AiRequestManager.wrapException('Unauthorized', statusCode: 401);
      expect(e401, isA<AiAuthException>());

      final e429 = AiRequestManager.wrapException('Too Many Requests', statusCode: 429);
      expect(e429, isA<AiRateLimitException>());

      final e400 = AiRequestManager.wrapException('token limit exceeded', statusCode: 400);
      expect(e400, isA<AiTokenLimitException>());

      final e404 = AiRequestManager.wrapException('Model not found', statusCode: 404);
      expect(e404, isA<AiModelNotSupportedException>());

      final e500 = AiRequestManager.wrapException('Server Error', statusCode: 500);
      expect(e500, isA<AiServerException>());
    });

    test('wrapException 应该解析 retryAfter（正则需要 retry 关键词）', () {
      // 正则是 r'retry.{0,10}(\d+)'，匹配 "retry" + 0到10个任意字符 + 数字
      final e429 = AiRequestManager.wrapException(
        'Rate limit, retry in 60',
        statusCode: 429,
      ) as AiRateLimitException;

      expect(e429.retryAfterSeconds, 60);
    });

    test('wrapException retryAfter 解析失败时应返回 null', () {
      final e429 = AiRequestManager.wrapException(
        'Too Many Requests without retry hint',
        statusCode: 429,
      ) as AiRateLimitException;

      expect(e429.retryAfterSeconds, null);
    });
  });
}
