enum AiProviderType {
  deepseek,
  custom,
}

extension AiProviderTypeX on AiProviderType {
  String get storageKey => switch (this) {
        AiProviderType.deepseek => 'deepseek',
        AiProviderType.custom => 'custom',
      };

  String get label => switch (this) {
        AiProviderType.deepseek => 'DeepSeek',
        AiProviderType.custom => '自定义',
      };

  static AiProviderType fromStorage(String? value) {
    for (final type in AiProviderType.values) {
      if (type.storageKey == value) return type;
    }
    return AiProviderType.deepseek;
  }
}

enum AiRouteMode {
  auto,
  fixed,
}

extension AiRouteModeX on AiRouteMode {
  String get storageKey => switch (this) {
        AiRouteMode.auto => 'auto',
        AiRouteMode.fixed => 'fixed',
      };

  String get label => switch (this) {
        AiRouteMode.auto => '自动',
        AiRouteMode.fixed => '固定',
      };

  static AiRouteMode fromStorage(String? value) {
    for (final mode in AiRouteMode.values) {
      if (mode.storageKey == value) return mode;
    }
    return AiRouteMode.auto;
  }
}

enum AiEndpointType {
  auto,
  chatCompletions,
  responses,
}

extension AiEndpointTypeX on AiEndpointType {
  String get storageKey => switch (this) {
        AiEndpointType.auto => 'auto',
        AiEndpointType.chatCompletions => 'chat_completions',
        AiEndpointType.responses => 'responses',
      };

  String get label => switch (this) {
        AiEndpointType.auto => '自动',
        AiEndpointType.chatCompletions => 'Chat Completions',
        AiEndpointType.responses => 'Responses',
      };

  static AiEndpointType fromStorage(String? value) {
    for (final type in AiEndpointType.values) {
      if (type.storageKey == value) return type;
    }
    return AiEndpointType.auto;
  }
}

enum AiReasoningEffort {
  none,
  minimal,
  low,
  medium,
  high,
  xhigh,
}

extension AiReasoningEffortX on AiReasoningEffort {
  String get storageKey => switch (this) {
        AiReasoningEffort.none => 'none',
        AiReasoningEffort.minimal => 'minimal',
        AiReasoningEffort.low => 'low',
        AiReasoningEffort.medium => 'medium',
        AiReasoningEffort.high => 'high',
        AiReasoningEffort.xhigh => 'xhigh',
      };

  String get label => switch (this) {
        AiReasoningEffort.none => '关闭',
        AiReasoningEffort.minimal => 'Minimal',
        AiReasoningEffort.low => 'Low',
        AiReasoningEffort.medium => 'Medium',
        AiReasoningEffort.high => 'High',
        AiReasoningEffort.xhigh => 'XHigh',
      };

  String? get apiValue => this == AiReasoningEffort.none ? null : storageKey;

  static AiReasoningEffort fromStorage(
    String? value, {
    AiReasoningEffort fallback = AiReasoningEffort.none,
  }) {
    for (final effort in AiReasoningEffort.values) {
      if (effort.storageKey == value) return effort;
    }
    return fallback;
  }
}

enum AiTaskType {
  recordParse,
  chatQuery,
  report,
}

extension AiTaskTypeX on AiTaskType {
  String get storageKey => switch (this) {
        AiTaskType.recordParse => 'record_parse',
        AiTaskType.chatQuery => 'chat_query',
        AiTaskType.report => 'report',
      };

  String get label => switch (this) {
        AiTaskType.recordParse => '普通记账',
        AiTaskType.chatQuery => '喵助手',
        AiTaskType.report => '报告生成',
      };
}

class AiProviderConfig {
  static const deepSeekBaseUrl = 'https://api.deepseek.com';
  static const deepSeekModel = 'deepseek-v4-flash';
  static const deepSeekCompatModel = 'deepseek-chat';
  static const customDefaultBaseUrl = 'https://api.openai.com/v1';
  static const customDefaultModel = 'gpt-5-mini';
  static const customReportDefaultModel = 'gpt-5';

  final AiProviderType type;
  final String apiKey;
  final String baseUrl;
  final String model;
  final AiEndpointType endpointType;
  final AiReasoningEffort reasoningEffort;
  final String? displayName;

  const AiProviderConfig({
    required this.type,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.endpointType = AiEndpointType.auto,
    this.reasoningEffort = AiReasoningEffort.none,
    this.displayName,
  });

  String get providerLabel {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? type.label : name;
  }

  bool get hasKey => apiKey.trim().isNotEmpty;

  bool get isDeepSeek => type == AiProviderType.deepseek;

  bool get isOpenAiOfficial =>
      baseUrl.trim().toLowerCase().contains('api.openai.com');

  bool get shouldUseResponses {
    if (endpointType == AiEndpointType.responses) return true;
    if (endpointType == AiEndpointType.chatCompletions) return false;
    return !isDeepSeek && isOpenAiOfficial;
  }

  List<String> get modelCandidates {
    final primary = model.trim().isEmpty ? deepSeekModel : model.trim();
    if (!isDeepSeek || primary == deepSeekCompatModel) return [primary];
    return [primary, deepSeekCompatModel];
  }

  Uri get chatCompletionsUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/chat/completions')) return Uri.parse(raw);
    if (raw.endsWith('/v1')) return Uri.parse('$raw/chat/completions');
    return Uri.parse('$raw/v1/chat/completions');
  }

  Uri get responsesUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/responses')) return Uri.parse(raw);
    if (raw.endsWith('/v1')) return Uri.parse('$raw/responses');
    return Uri.parse('$raw/v1/responses');
  }

  AiProviderConfig copyWith({
    AiProviderType? type,
    String? apiKey,
    String? baseUrl,
    String? model,
    AiEndpointType? endpointType,
    AiReasoningEffort? reasoningEffort,
    String? displayName,
  }) =>
      AiProviderConfig(
        type: type ?? this.type,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        endpointType: endpointType ?? this.endpointType,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        displayName: displayName ?? this.displayName,
      );

  factory AiProviderConfig.deepSeek({
    required String apiKey,
    String? displayName,
  }) =>
      AiProviderConfig(
        type: AiProviderType.deepseek,
        apiKey: apiKey,
        baseUrl: deepSeekBaseUrl,
        model: deepSeekModel,
        endpointType: AiEndpointType.chatCompletions,
        reasoningEffort: AiReasoningEffort.none,
        displayName: displayName,
      );

  factory AiProviderConfig.custom({
    required String apiKey,
    required String baseUrl,
    required String model,
    AiEndpointType endpointType = AiEndpointType.auto,
    AiReasoningEffort reasoningEffort = AiReasoningEffort.none,
    String? displayName,
  }) =>
      AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: apiKey,
        baseUrl: baseUrl.trim().isEmpty ? customDefaultBaseUrl : baseUrl.trim(),
        model: model.trim().isEmpty ? customDefaultModel : model.trim(),
        endpointType: endpointType,
        reasoningEffort: reasoningEffort,
        displayName: displayName,
      );
}
