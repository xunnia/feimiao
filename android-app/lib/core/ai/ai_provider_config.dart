import 'dart:convert';

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
  max,
  ultra,
}

extension AiReasoningEffortX on AiReasoningEffort {
  String get storageKey => switch (this) {
        AiReasoningEffort.none => 'none',
        AiReasoningEffort.minimal => 'minimal',
        AiReasoningEffort.low => 'low',
        AiReasoningEffort.medium => 'medium',
        AiReasoningEffort.high => 'high',
        AiReasoningEffort.xhigh => 'xhigh',
        AiReasoningEffort.max => 'max',
        AiReasoningEffort.ultra => 'ultra',
      };

  String get label => switch (this) {
        AiReasoningEffort.none => '关闭',
        AiReasoningEffort.minimal => 'Minimal',
        AiReasoningEffort.low => 'Low',
        AiReasoningEffort.medium => 'Medium',
        AiReasoningEffort.high => 'High',
        AiReasoningEffort.xhigh => 'Extra',
        AiReasoningEffort.max => 'Max',
        AiReasoningEffort.ultra => 'Ultra',
      };

  String? get apiValue => this == AiReasoningEffort.none ? null : storageKey;

  /// Claude 原生 /v1/messages 的 thinking budget_tokens 映射
  int? get claudeBudgetTokens => switch (this) {
        AiReasoningEffort.none => null,
        AiReasoningEffort.minimal => 1024,
        AiReasoningEffort.low => 4096,
        AiReasoningEffort.medium => 8192,
        AiReasoningEffort.high => 16384,
        AiReasoningEffort.xhigh => 24576,
        AiReasoningEffort.max => 32768,
        AiReasoningEffort.ultra => 65536,
      };

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

  /// 是否使用 Claude 原生 /v1/messages 格式（thinking 参数）
  bool get shouldUseClaudeMessages {
    if (endpointType == AiEndpointType.chatCompletions) return false;
    if (endpointType == AiEndpointType.responses) return false;
    return isClaudeModel && !isDeepSeek;
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

  Uri get messagesUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/messages')) return Uri.parse(raw);
    if (raw.endsWith('/v1')) return Uri.parse('$raw/messages');
    return Uri.parse('$raw/v1/messages');
  }

  Uri get responsesUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/responses')) return Uri.parse(raw);
    if (raw.endsWith('/v1')) return Uri.parse('$raw/responses');
    return Uri.parse('$raw/v1/responses');
  }

  /// 检测是否是 Claude 模型（需要用 /v1/messages）
  bool get isClaudeModel {
    final m = model.toLowerCase();
    final u = baseUrl.toLowerCase();
    return m.contains('claude') || u.contains('anthropic') || u.contains('claude');
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

/// A configured provider instance.  The provider type is only a compatibility
/// hint; [id] makes it possible to keep multiple custom gateways at once.
/// API keys intentionally do not participate in JSON serialization.
class AiConfiguredProvider {
  final String id;
  final AiProviderType type;
  final String displayName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<String> models;
  final AiEndpointType endpointType;
  final AiReasoningEffort reasoningEffort;
  final bool builtIn;

  AiConfiguredProvider({
    required this.id,
    required this.type,
    required this.displayName,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    Iterable<String> models = const [],
    this.endpointType = AiEndpointType.auto,
    this.reasoningEffort = AiReasoningEffort.none,
    this.builtIn = false,
  }) : models = _normalizeModels(models, model);

  String get label =>
      displayName.trim().isEmpty ? type.label : displayName.trim();

  bool get hasKey => apiKey.trim().isNotEmpty;

  AiProviderConfig toConfig({
    String? modelOverride,
    AiReasoningEffort? effortOverride,
  }) {
    final chosen = (modelOverride ?? model).trim();
    return AiProviderConfig(
      type: type,
      apiKey: apiKey,
      baseUrl: baseUrl.trim().isEmpty
          ? (type == AiProviderType.deepseek
              ? AiProviderConfig.deepSeekBaseUrl
              : AiProviderConfig.customDefaultBaseUrl)
          : baseUrl.trim(),
      model: chosen.isEmpty
          ? (type == AiProviderType.deepseek
              ? AiProviderConfig.deepSeekModel
              : AiProviderConfig.customDefaultModel)
          : chosen,
      endpointType: endpointType,
      reasoningEffort: effortOverride ?? reasoningEffort,
      displayName: label,
    );
  }

  AiConfiguredProvider copyWith({
    String? id,
    AiProviderType? type,
    String? displayName,
    String? baseUrl,
    String? apiKey,
    String? model,
    Iterable<String>? models,
    AiEndpointType? endpointType,
    AiReasoningEffort? reasoningEffort,
    bool? builtIn,
  }) =>
      AiConfiguredProvider(
        id: id ?? this.id,
        type: type ?? this.type,
        displayName: displayName ?? this.displayName,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        models: models ?? this.models,
        endpointType: endpointType ?? this.endpointType,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        builtIn: builtIn ?? this.builtIn,
      );

  /// Metadata persisted in app_settings.  The secret key is stored separately
  /// under a provider-specific SecureKeyStore key.
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.storageKey,
        'displayName': displayName,
        'baseUrl': baseUrl,
        'model': model,
        'models': models,
        'endpointType': endpointType.storageKey,
        'reasoningEffort': reasoningEffort.storageKey,
        'builtIn': builtIn,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AiConfiguredProvider.fromJson(
    Map<String, dynamic> json, {
    String apiKey = '',
  }) {
    final type = AiProviderTypeX.fromStorage(json['type'] as String?);
    final rawModels = json['models'];
    final models =
        rawModels is List ? rawModels.whereType<String>() : const <String>[];
    final defaultName = type == AiProviderType.deepseek ? 'DeepSeek' : '自定义';
    final defaultBase = type == AiProviderType.deepseek
        ? AiProviderConfig.deepSeekBaseUrl
        : AiProviderConfig.customDefaultBaseUrl;
    final defaultModel = type == AiProviderType.deepseek
        ? AiProviderConfig.deepSeekModel
        : AiProviderConfig.customDefaultModel;
    return AiConfiguredProvider(
      id: (json['id'] as String? ?? '').trim(),
      type: type,
      displayName: (json['displayName'] as String? ?? defaultName).trim(),
      baseUrl: (json['baseUrl'] as String? ?? defaultBase).trim(),
      apiKey: apiKey,
      model: (json['model'] as String? ?? defaultModel).trim(),
      models: models,
      endpointType:
          AiEndpointTypeX.fromStorage(json['endpointType'] as String?),
      reasoningEffort: AiReasoningEffortX.fromStorage(
        json['reasoningEffort'] as String?,
      ),
      builtIn: json['builtIn'] == true,
    );
  }

  static List<String> _normalizeModels(
      Iterable<String> values, String primary) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in [primary, ...values]) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) result.add(trimmed);
    }
    return List.unmodifiable(result);
  }
}

class AiModelOption {
  final String providerId;
  final String providerLabel;
  final String model;

  const AiModelOption({
    required this.providerId,
    required this.providerLabel,
    required this.model,
  });

  String get key => '$providerId\u0000$model';

  @override
  bool operator ==(Object other) =>
      other is AiModelOption &&
      other.providerId == providerId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(providerId, model);
}
