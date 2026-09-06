/// AI 配置管理：多服务商 + 用途分配 + 模型选择
///
/// 架构：
/// - AiProvider：服务商配置（DeepSeek / Claude / 自定义）
/// - AiTaskType：任务类型枚举（报告/预算/聊天/长文）
/// - AiConfig：配置管理器，持久化到 SQLite
library;

import 'package:flutter/foundation.dart';

/// AI 服务商
@immutable
class AiProvider {
  final String id; // deepseek / claude / custom-xxx
  final String name; // 显示名称
  final String emoji; // 图标
  final String? apiKey;
  final String? baseUrl; // 自定义服务商必填
  final String? defaultModel; // 默认模型
  final bool isCustom;
  final bool enabled;

  const AiProvider({
    required this.id,
    required this.name,
    required this.emoji,
    this.apiKey,
    this.baseUrl,
    this.defaultModel,
    this.isCustom = false,
    this.enabled = true,
  });

  factory AiProvider.fromMap(Map<String, dynamic> map) {
    return AiProvider(
      id: map['id'] as String,
      name: map['name'] as String,
      emoji: map['emoji'] as String? ?? '🤖',
      apiKey: map['api_key'] as String?,
      baseUrl: map['base_url'] as String?,
      defaultModel: map['default_model'] as String?,
      isCustom: (map['is_custom'] as int? ?? 0) == 1,
      enabled: (map['enabled'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'api_key': apiKey,
      'base_url': baseUrl,
      'default_model': defaultModel,
      'is_custom': isCustom ? 1 : 0,
      'enabled': enabled ? 1 : 0,
    };
  }

  AiProvider copyWith({
    String? id,
    String? name,
    String? emoji,
    String? apiKey,
    String? baseUrl,
    String? defaultModel,
    bool? isCustom,
    bool? enabled,
  }) {
    return AiProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      isCustom: isCustom ?? this.isCustom,
      enabled: enabled ?? this.enabled,
    );
  }

  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;
}

/// AI 任务类型
enum AiTaskType {
  report('report', '生成报告', '📊'),
  budget('budget', '预算建议', '💰'),
  chat('chat', '喵助手聊天', '💬'),
  longText('long_text', '长文总结', '📝');

  final String id;
  final String displayName;
  final String emoji;

  const AiTaskType(this.id, this.displayName, this.emoji);

  static AiTaskType? fromId(String id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

/// 任务分配规则
@immutable
class TaskAllocation {
  final AiTaskType taskType;
  final String providerId;
  final String model;

  const TaskAllocation({
    required this.taskType,
    required this.providerId,
    required this.model,
  });

  factory TaskAllocation.fromMap(Map<String, dynamic> map) {
    final taskType = AiTaskType.fromId(map['task_type'] as String);
    if (taskType == null) {
      throw ArgumentError('Unknown task_type: ${map['task_type']}');
    }
    return TaskAllocation(
      taskType: taskType,
      providerId: map['provider_id'] as String,
      model: map['model'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'task_type': taskType.id,
      'provider_id': providerId,
      'model': model,
    };
  }
}

/// 预设服务商（工厂方法）
class AiProviderPresets {
  AiProviderPresets._();

  static const deepseek = AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    emoji: '🧠',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-chat',
  );

  static const claude = AiProvider(
    id: 'claude',
    name: 'Claude',
    emoji: '🤖',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-3-5-sonnet-20241022',
  );

  static List<AiProvider> get allPresets => [deepseek, claude];
}

/// 模型选项（每个服务商支持的模型列表）
class ModelOptions {
  ModelOptions._();

  static const deepseekModels = [
    ('deepseek-chat', 'DeepSeek Chat（推荐）'),
    ('deepseek-reasoner', 'DeepSeek R1（深度推理）'),
  ];

  static const claudeModels = [
    ('claude-3-5-sonnet-20241022', 'Claude 3.5 Sonnet（推荐）'),
    ('claude-3-5-haiku-20241022', 'Claude 3.5 Haiku（快速）'),
    ('claude-3-opus-20240229', 'Claude 3 Opus（旗舰）'),
  ];

  static List<(String, String)> forProvider(String providerId) {
    switch (providerId) {
      case 'deepseek':
        return deepseekModels;
      case 'claude':
        return claudeModels;
      default:
        return []; // 自定义服务商由用户手填
    }
  }
}
