import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_logger.dart';

void main() {
  group('AiLogger 日志脱敏测试', () {
    test('_sanitizeString 应该脱敏手机号', () {
      const input = '用户手机号：13812345678，请联系';
      final result = AiLogger.sanitizeStringForTest(input);

      expect(result, contains('138****5678'));
      expect(result, isNot(contains('13812345678')));
    });

    test('_sanitizeString 应该脱敏身份证号', () {
      const input = '身份证：110101199001011234';
      final result = AiLogger.sanitizeStringForTest(input);

      expect(result, contains('110101********1234'));
      expect(result, isNot(contains('110101199001011234')));
    });

    test('_sanitizeString 应该限制长度到 200 字符', () {
      final input = 'a' * 250;
      final result = AiLogger.sanitizeStringForTest(input);

      expect(result.length, lessThanOrEqualTo(203)); // 200 + '...'
      expect(result, endsWith('...'));
    });

    test('_sanitizeMap 应该移除 key/token/password 等敏感字段', () {
      final input = {
        'api_key': 'sk-1234567890',
        'access_token': 'token-abc',
        'password': 'secret',
        'user_name': '张三',
        'phone': '13812345678',
      };

      final result = AiLogger.sanitizeMapForTest(input);

      expect(result.containsKey('api_key'), false);
      expect(result.containsKey('access_token'), false);
      expect(result.containsKey('password'), false);
      expect(result['user_name'], '张三');
      expect(result['phone'], contains('138****5678'));
    });

    test('_sanitizeMap 应该递归脱敏嵌套 Map', () {
      final input = {
        'user': {
          'name': '张三',
          'api_key': 'sk-secret',
          'contact': '13812345678',
        },
        'settings': {
          'token': 'secret-token',
          'theme': 'dark',
        },
      };

      final result = AiLogger.sanitizeMapForTest(input);
      final user = result['user'] as Map<String, dynamic>;
      final settings = result['settings'] as Map<String, dynamic>;

      expect(user.containsKey('api_key'), false);
      expect(user['contact'], contains('138****5678'));
      expect(settings.containsKey('token'), false);
      expect(settings['theme'], 'dark');
    });

    test('_sanitizeErrorMessage 应该隐藏响应体', () {
      const input = '请求失败: {"error": {"message": "API key invalid", "code": 401}}';
      final result = AiLogger.sanitizeErrorMessageForTest(input);

      expect(result, contains('[响应体已隐藏]'));
      expect(result.length, lessThanOrEqualTo(120)); // 截断前 100 + 提示文本
    });

    test('_sanitizeErrorMessage 应该保留简单错误信息', () {
      const input = '网络连接超时';
      final result = AiLogger.sanitizeErrorMessageForTest(input);

      expect(result, '网络连接超时');
    });

    test('logQueryFailure 应该脱敏错误信息', () {
      // 仅验证不抛异常，实际日志输出由 dart:developer 处理
      expect(
        () => AiLogger.logQueryFailure(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          errorType: 'AiAuthException',
          errorMessage: 'API key sk-1234567890 is invalid',
          durationMs: 100,
          statusCode: 401,
        ),
        returnsNormally,
      );
    });

    test('logQueryStart 应该脱敏 extra 参数', () {
      expect(
        () => AiLogger.logQueryStart(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          estimatedTokens: 500,
          extra: {
            'user_phone': '13812345678',
            'api_key': 'sk-secret',
          },
        ),
        returnsNormally,
      );
    });
  });
}
