import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_config.dart';

void main() {
  group('AiProvider', () {
    test('fromMap 应该正确解析数据库行', () {
      final map = {
        'id': 'deepseek',
        'name': 'DeepSeek',
        'emoji': '🧠',
        'api_key': 'sk-test',
        'base_url': 'https://api.deepseek.com',
        'default_model': 'deepseek-chat',
        'is_custom': 0,
        'enabled': 1,
      };

      final provider = AiProvider.fromMap(map);

      expect(provider.id, 'deepseek');
      expect(provider.name, 'DeepSeek');
      expect(provider.emoji, '🧠');
      expect(provider.apiKey, 'sk-test');
      expect(provider.baseUrl, 'https://api.deepseek.com');
      expect(provider.defaultModel, 'deepseek-chat');
      expect(provider.isCustom, false);
      expect(provider.enabled, true);
    });

    test('toMap 应该返回可存入数据库的 Map', () {
      const provider = AiProvider(
        id: 'claude',
        name: 'Claude',
        emoji: '🤖',
        apiKey: 'sk-ant-test',
        baseUrl: 'https://api.anthropic.com',
        defaultModel: 'claude-3-5-sonnet-20241022',
        isCustom: false,
        enabled: true,
      );

      final map = provider.toMap();

      expect(map['id'], 'claude');
      expect(map['name'], 'Claude');
      expect(map['emoji'], '🤖');
      expect(map['api_key'], 'sk-ant-test');
      expect(map['base_url'], 'https://api.anthropic.com');
      expect(map['default_model'], 'claude-3-5-sonnet-20241022');
      expect(map['is_custom'], 0);
      expect(map['enabled'], 1);
    });

    test('isConfigured 应该检查 API Key 是否有效', () {
      const configured = AiProvider(
        id: 'test',
        name: 'Test',
        emoji: '🧪',
        apiKey: 'sk-valid',
      );
      const unconfigured = AiProvider(
        id: 'test2',
        name: 'Test2',
        emoji: '🧪',
      );
      const empty = AiProvider(
        id: 'test3',
        name: 'Test3',
        emoji: '🧪',
        apiKey: '',
      );

      expect(configured.isConfigured, true);
      expect(unconfigured.isConfigured, false);
      expect(empty.isConfigured, false);
    });

    test('copyWith 应该只更新指定字段', () {
      const original = AiProvider(
        id: 'test',
        name: 'Test',
        emoji: '🧪',
        apiKey: 'sk-old',
        enabled: true,
      );

      final updated = original.copyWith(
        apiKey: 'sk-new',
        enabled: false,
      );

      expect(updated.id, 'test');
      expect(updated.name, 'Test');
      expect(updated.emoji, '🧪');
      expect(updated.apiKey, 'sk-new');
      expect(updated.enabled, false);
    });
  });

  group('AiTaskType', () {
    test('fromId 应该正确查找枚举值', () {
      expect(AiTaskType.fromId('report'), AiTaskType.report);
      expect(AiTaskType.fromId('budget'), AiTaskType.budget);
      expect(AiTaskType.fromId('chat'), AiTaskType.chat);
      expect(AiTaskType.fromId('long_text'), AiTaskType.longText);
      expect(AiTaskType.fromId('unknown'), null);
    });

    test('枚举值应该包含正确的属性', () {
      expect(AiTaskType.report.id, 'report');
      expect(AiTaskType.report.displayName, '生成报告');
      expect(AiTaskType.report.emoji, '📊');

      expect(AiTaskType.chat.id, 'chat');
      expect(AiTaskType.chat.displayName, '喵助手聊天');
      expect(AiTaskType.chat.emoji, '💬');
    });
  });

  group('TaskAllocation', () {
    test('fromMap 应该正确解析数据库行', () {
      final map = {
        'task_type': 'report',
        'provider_id': 'deepseek',
        'model': 'deepseek-chat',
      };

      final allocation = TaskAllocation.fromMap(map);

      expect(allocation.taskType, AiTaskType.report);
      expect(allocation.providerId, 'deepseek');
      expect(allocation.model, 'deepseek-chat');
    });

    test('fromMap 应该对未知任务类型抛异常', () {
      final map = {
        'task_type': 'unknown_task',
        'provider_id': 'deepseek',
        'model': 'deepseek-chat',
      };

      expect(() => TaskAllocation.fromMap(map), throwsArgumentError);
    });

    test('toMap 应该返回可存入数据库的 Map', () {
      const allocation = TaskAllocation(
        taskType: AiTaskType.budget,
        providerId: 'claude',
        model: 'claude-3-5-sonnet-20241022',
      );

      final map = allocation.toMap();

      expect(map['task_type'], 'budget');
      expect(map['provider_id'], 'claude');
      expect(map['model'], 'claude-3-5-sonnet-20241022');
    });
  });

  group('AiProviderPresets', () {
    test('应该包含 DeepSeek 和 Claude 预设', () {
      expect(AiProviderPresets.deepseek.id, 'deepseek');
      expect(AiProviderPresets.deepseek.name, 'DeepSeek');
      expect(AiProviderPresets.deepseek.emoji, '🧠');
      expect(AiProviderPresets.deepseek.baseUrl, 'https://api.deepseek.com');
      expect(AiProviderPresets.deepseek.defaultModel, 'deepseek-chat');

      expect(AiProviderPresets.claude.id, 'claude');
      expect(AiProviderPresets.claude.name, 'Claude');
      expect(AiProviderPresets.claude.emoji, '🤖');
      expect(AiProviderPresets.claude.baseUrl, 'https://api.anthropic.com');
      expect(
        AiProviderPresets.claude.defaultModel,
        'claude-3-5-sonnet-20241022',
      );
    });

    test('allPresets 应该返回所有预设服务商', () {
      final presets = AiProviderPresets.allPresets;

      expect(presets.length, 2);
      expect(presets[0].id, 'deepseek');
      expect(presets[1].id, 'claude');
    });
  });

  group('ModelOptions', () {
    test('forProvider 应该返回 DeepSeek 模型列表', () {
      final models = ModelOptions.forProvider('deepseek');

      expect(models.length, 2);
      expect(models[0].$1, 'deepseek-chat');
      expect(models[0].$2, 'DeepSeek Chat（推荐）');
      expect(models[1].$1, 'deepseek-reasoner');
      expect(models[1].$2, 'DeepSeek R1（深度推理）');
    });

    test('forProvider 应该返回 Claude 模型列表', () {
      final models = ModelOptions.forProvider('claude');

      expect(models.length, 3);
      expect(models[0].$1, 'claude-3-5-sonnet-20241022');
      expect(models[0].$2, 'Claude 3.5 Sonnet（推荐）');
      expect(models[1].$1, 'claude-3-5-haiku-20241022');
      expect(models[2].$1, 'claude-3-opus-20240229');
    });

    test('forProvider 应该对未知服务商返回空列表', () {
      final models = ModelOptions.forProvider('unknown');

      expect(models, isEmpty);
    });

    test('forProvider 应该对自定义服务商返回空列表', () {
      final models = ModelOptions.forProvider('custom-my-api');

      expect(models, isEmpty);
    });
  });
}
