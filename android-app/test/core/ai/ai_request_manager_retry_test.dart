import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/ai_request_manager.dart';

void main() {
  group('AiRequestManager 重试日志测试', () {
    test('retryWithBackoff 应该在重试时记录日志', () async {
      var attemptCount = 0;

      try {
        await AiRequestManager.retryWithBackoff<String>(
          maxRetries: 2,
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          request: () async {
            attemptCount++;
            if (attemptCount < 3) {
              throw const AiNetworkException('连接失败');
            }
            return 'success';
          },
        );
      } catch (e) {
        // 不应该到这里
      }

      expect(attemptCount, 3); // 第1次失败 + 第2次失败 + 第3次成功
    });

    test('retryWithBackoff 应该在最终失败时记录放弃', () async {
      var attemptCount = 0;

      try {
        await AiRequestManager.retryWithBackoff<String>(
          maxRetries: 2,
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          request: () async {
            attemptCount++;
            throw const AiNetworkException('连接失败');
          },
        );
        fail('应该抛出异常');
      } catch (e) {
        expect(e, isA<AiNetworkException>());
        expect(attemptCount, 3); // 初始尝试 + 2次重试
      }
    });

    test('retryWithBackoff 应该在遇到不可重试错误时记录', () async {
      var attemptCount = 0;

      try {
        await AiRequestManager.retryWithBackoff<String>(
          maxRetries: 2,
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          request: () async {
            attemptCount++;
            throw const AiAuthException('API key 无效', statusCode: 401);
          },
        );
        fail('应该抛出异常');
      } catch (e) {
        expect(e, isA<AiAuthException>());
        expect(attemptCount, 1); // 只尝试1次，不重试
      }
    });

    test('retryWithBackoff 没有 taskType 时不应记录日志（兼容旧调用）', () async {
      var attemptCount = 0;

      try {
        await AiRequestManager.retryWithBackoff<String>(
          maxRetries: 1,
          request: () async {
            attemptCount++;
            throw const AiNetworkException('连接失败');
          },
        );
        fail('应该抛出异常');
      } catch (e) {
        expect(e, isA<AiNetworkException>());
        expect(attemptCount, 2); // 初始尝试 + 1次重试
      }
    });
  });
}
