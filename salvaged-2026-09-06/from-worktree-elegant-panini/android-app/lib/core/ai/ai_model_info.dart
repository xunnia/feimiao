/// AI 模型信息封装：id、显示名、推理能力、emoji。
///
/// 提供内置模型列表常量 [builtInModels]（DeepSeek / OpenAI / Claude 系列），
/// 支持从 API 返回的模型 ID 动态补充到列表。
class AiModelInfo {
  final String id;
  final String displayName;
  final bool supportsReasoning;
  final String emoji;

  const AiModelInfo({
    required this.id,
    required this.displayName,
    required this.supportsReasoning,
    required this.emoji,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiModelInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// 内置模型列表：DeepSeek / OpenAI / Claude 系列。
  static const List<AiModelInfo> builtInModels = [
    // DeepSeek
    AiModelInfo(
      id: 'deepseek-chat',
      displayName: 'DeepSeek Chat',
      supportsReasoning: false,
      emoji: '🤖',
    ),
    AiModelInfo(
      id: 'deepseek-reasoner',
      displayName: 'DeepSeek Reasoner',
      supportsReasoning: true,
      emoji: '🧠',
    ),

    // OpenAI
    AiModelInfo(
      id: 'gpt-4o',
      displayName: 'GPT-4o',
      supportsReasoning: false,
      emoji: '🟢',
    ),
    AiModelInfo(
      id: 'gpt-4o-mini',
      displayName: 'GPT-4o Mini',
      supportsReasoning: false,
      emoji: '🟢',
    ),
    AiModelInfo(
      id: 'o1',
      displayName: 'o1',
      supportsReasoning: true,
      emoji: '🔵',
    ),
    AiModelInfo(
      id: 'o1-mini',
      displayName: 'o1-mini',
      supportsReasoning: true,
      emoji: '🔵',
    ),
    AiModelInfo(
      id: 'o3-mini',
      displayName: 'o3-mini',
      supportsReasoning: true,
      emoji: '🔵',
    ),

    // Claude
    AiModelInfo(
      id: 'claude-3-5-sonnet-20241022',
      displayName: 'Claude 3.5 Sonnet',
      supportsReasoning: false,
      emoji: '🟣',
    ),
    AiModelInfo(
      id: 'claude-3-5-haiku-20241022',
      displayName: 'Claude 3.5 Haiku',
      supportsReasoning: false,
      emoji: '🟣',
    ),
    AiModelInfo(
      id: 'claude-3-opus-20240229',
      displayName: 'Claude 3 Opus',
      supportsReasoning: false,
      emoji: '🟣',
    ),
  ];

  /// 从 [id] 查找模型信息：优先匹配 [builtInModels]，未找到则动态创建兜底对象。
  static AiModelInfo fromId(String id) {
    for (final model in builtInModels) {
      if (model.id == id) return model;
    }
    // 动态补充：未知模型返回通用占位
    return AiModelInfo(
      id: id,
      displayName: id,
      supportsReasoning: false,
      emoji: '🤖',
    );
  }
}
