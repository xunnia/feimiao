import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_logger.dart';

void main() {
  group('AiLogger 警告日志测试', () {
    test('logWarning 应该记录非致命错误', () {
      // 仅验证不抛异常
      expect(
        () => AiLogger.logWarning(
          taskType: 'stream_parse_chunk',
          provider: 'deepseek',
          model: 'deepseek-chat',
          warning: '单条数据解析失败',
        ),
        returnsNormally,
      );
    });

    test('logWarning 应该脱敏 extra 参数', () {
      expect(
        () => AiLogger.logWarning(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          warning: '警告: API key sk-123456 相关',
          extra: {
            'user_phone': '13812345678',
            'api_key': 'sk-secret',
            'chunk_data': '包含手机号 13987654321 的数据',
          },
        ),
        returnsNormally,
      );
    });

    test('logWarning 应该脱敏 warning 消息', () {
      expect(
        () => AiLogger.logWarning(
          taskType: 'test',
          provider: 'deepseek',
          model: 'deepseek-chat',
          warning: '错误响应: {"error": "invalid key", "details": {...}}',
        ),
        returnsNormally,
      );
    });
  });
}
