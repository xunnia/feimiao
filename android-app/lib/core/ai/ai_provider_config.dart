import 'dart:convert';

typedef OAuthTokenSaver = Future<void> Function(
  String accessToken,
  String? refreshToken,
  int? expiresAtMs,
  String? accountId,
);

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
  anthropicMessages,
}

extension AiEndpointTypeX on AiEndpointType {
  String get storageKey => switch (this) {
        AiEndpointType.auto => 'auto',
        AiEndpointType.chatCompletions => 'chat_completions',
        AiEndpointType.responses => 'responses',
        AiEndpointType.anthropicMessages => 'anthropic_messages',
      };

  String get label => switch (this) {
        AiEndpointType.auto => '自动',
        AiEndpointType.chatCompletions => 'Chat Completions',
        AiEndpointType.responses => 'Responses',
        AiEndpointType.anthropicMessages => 'Anthropic Messages (Claude)',
      };

  static AiEndpointType fromStorage(String? value) {
    for (final type in AiEndpointType.values) {
      if (type.storageKey == value) return type;
    }
    return AiEndpointType.auto;
  }
}

enum AiAuthMethod {
  apiKey,
  oauth,
}

extension AiAuthMethodX on AiAuthMethod {
  String get storageKey => switch (this) {
        AiAuthMethod.apiKey => 'api_key',
        AiAuthMethod.oauth => 'oauth',
      };

  String get label => switch (this) {
        AiAuthMethod.apiKey => 'API Key',
        AiAuthMethod.oauth => 'OAuth 授权',
      };

  static AiAuthMethod fromStorage(String? value) {
    for (final method in AiAuthMethod.values) {
      if (method.storageKey == value) return method;
    }
    return AiAuthMethod.apiKey;
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

  /// OpenAI Responses 只接受官方枚举值。UI 仍保留 Max/Ultracode 两档，
  /// 传输层把它们映射到当前端点支持的最高档，避免请求直接 400。
  String? get responsesApiValue => switch (this) {
        AiReasoningEffort.none => null,
        AiReasoningEffort.minimal => 'minimal',
        AiReasoningEffort.low => 'low',
        AiReasoningEffort.medium => 'medium',
        AiReasoningEffort.high => 'high',
        AiReasoningEffort.xhigh => 'xhigh',
        AiReasoningEffort.max || AiReasoningEffort.ultra => 'xhigh',
      };

  /// The Codex Responses backend follows the official client's `max` value;
  /// public Responses-compatible relays keep the `xhigh` mapping above.
  String? get codexResponsesApiValue => switch (this) {
        AiReasoningEffort.none => null,
        AiReasoningEffort.minimal => 'minimal',
        AiReasoningEffort.low => 'low',
        AiReasoningEffort.medium => 'medium',
        AiReasoningEffort.high => 'high',
        AiReasoningEffort.xhigh => 'xhigh',
        AiReasoningEffort.max || AiReasoningEffort.ultra => 'max',
      };

  /// Responses 的输出上限包含推理 token。高档位保留更多空间，避免模型
  /// 还没开始输出正文就因固定的 4096 上限进入 incomplete。
  int get responsesMaxOutputTokens => switch (this) {
        AiReasoningEffort.none ||
        AiReasoningEffort.minimal ||
        AiReasoningEffort.low ||
        AiReasoningEffort.medium =>
          4096,
        AiReasoningEffort.high => 8192,
        AiReasoningEffort.xhigh => 12288,
        AiReasoningEffort.max || AiReasoningEffort.ultra => 16384,
      };

  /// DeepSeek 原生 Chat Completions 目前只接受 high/max 两档。
  /// Chats 的 UI 仍保留更细的 Claude 风格档位；这里做有损但可预期的
  /// 映射，避免把不支持的值发送给直连 DeepSeek。
  String? get deepSeekApiValue => switch (this) {
        AiReasoningEffort.none => null,
        AiReasoningEffort.minimal ||
        AiReasoningEffort.low ||
        AiReasoningEffort.medium ||
        AiReasoningEffort.high =>
          'high',
        AiReasoningEffort.xhigh ||
        AiReasoningEffort.max ||
        AiReasoningEffort.ultra =>
          'max',
      };

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
  static const openAiOAuthAuthorizationUrl =
      'https://auth.openai.com/oauth/authorize';
  static const openAiCodexBaseUrl = 'https://chatgpt.com/backend-api';
  static const openAiCodexClientVersion = '0.146.0';

  final AiProviderType type;
  final String apiKey;
  final String baseUrl;
  final String model;
  final AiEndpointType endpointType;
  final AiAuthMethod authMethod;
  final AiReasoningEffort reasoningEffort;

  /// Whether this account may use internet search for chat questions.
  /// Disabled by default so enabling a provider never implicitly sends a
  /// user's question to a third-party search service.
  final bool webSearchEnabled;
  final String? displayName;
  final String? providerId;
  final String oauthAccountId;
  final String oauthRefreshToken;
  final int? oauthExpiresAtMs;
  final OAuthTokenSaver? oauthTokenSaver;

  const AiProviderConfig({
    required this.type,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.endpointType = AiEndpointType.auto,
    this.authMethod = AiAuthMethod.apiKey,
    this.reasoningEffort = AiReasoningEffort.none,
    this.webSearchEnabled = false,
    this.displayName,
    this.providerId,
    this.oauthAccountId = '',
    this.oauthRefreshToken = '',
    this.oauthExpiresAtMs,
    this.oauthTokenSaver,
  });

  String get providerLabel {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? type.label : name;
  }

  bool get hasKey => apiKey.trim().isNotEmpty;

  /// A portable OAuth account may contain only a refresh token (for example
  /// when imported from Cockpit).  It is still a usable credential because the
  /// request layer can exchange it for a fresh access token before sending.
  bool get hasCredential =>
      hasKey ||
      (authMethod == AiAuthMethod.oauth && oauthRefreshToken.trim().isNotEmpty);

  bool get hasBaseUrl => baseUrl.trim().isNotEmpty;

  bool get hasModel => model.trim().isNotEmpty;

  bool get isDeepSeek => type == AiProviderType.deepseek;

  bool get isOpenAiOfficial =>
      baseUrl.trim().toLowerCase().contains('api.openai.com');

  bool get isAnthropicOfficial =>
      baseUrl.trim().toLowerCase().contains('api.anthropic.com');

  bool get isOpenAiCodexOAuth =>
      authMethod == AiAuthMethod.oauth &&
      (baseUrl.trim().toLowerCase().contains('chatgpt.com/backend-api') ||
          oauthAccountId.trim().isNotEmpty);

  /// Stable identity of the party that receives an AI request.
  ///
  /// Privacy consent is intentionally scoped to this value rather than to a
  /// global boolean: changing a provider's endpoint or OAuth account changes
  /// the real recipient and must prompt again, while changing only the model
  /// or reasoning effort does not.  No credential is included here.
  String get privacyReceiverKey {
    final provider = providerId?.trim() ?? '';
    final endpoint =
        baseUrl.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    final account = oauthAccountId.trim();
    if (provider.isEmpty && endpoint.isEmpty && account.isEmpty) return '';
    return [
      'v1',
      provider,
      type.storageKey,
      endpoint,
      endpointType.storageKey,
      authMethod.storageKey,
      account,
    ].join('|');
  }

  bool get shouldUseResponses {
    if (isOpenAiCodexOAuth) return true;
    if (endpointType == AiEndpointType.responses) return true;
    if (endpointType == AiEndpointType.chatCompletions) return false;
    return !isDeepSeek && isOpenAiOfficial;
  }

  /// 是否使用 Claude 原生 /v1/messages 格式（thinking 参数）
  bool get shouldUseClaudeMessages {
    if (endpointType == AiEndpointType.anthropicMessages) return true;
    if (endpointType == AiEndpointType.chatCompletions) return false;
    if (endpointType == AiEndpointType.responses) return false;
    // A Claude-named model on an OpenAI-compatible relay still expects
    // Bearer auth and /v1/chat/completions. Only the official Anthropic
    // endpoint is unambiguously the native Messages API.
    return isAnthropicOfficial && isClaudeModel && !isDeepSeek;
  }

  List<String> get modelCandidates {
    final trimmed = model.trim();
    // A blank custom model means the account is still being configured. Do
    // not silently turn it into a DeepSeek model; callers validate this state
    // before making a request. The built-in DeepSeek entry keeps its legacy
    // fallback for migrated settings created before model validation existed.
    if (trimmed.isEmpty) {
      return isDeepSeek ? [deepSeekModel] : const [];
    }
    final primary = trimmed;
    if (!isDeepSeek || primary == deepSeekCompatModel) return [primary];
    return [primary, deepSeekCompatModel];
  }

  Uri get chatCompletionsUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/chat/completions')) return Uri.parse(raw);
    raw = raw.replaceFirst(RegExp(r'/(?:messages|responses)$'), '');
    if (raw.endsWith('/v1')) return Uri.parse('$raw/chat/completions');
    return Uri.parse('$raw/v1/chat/completions');
  }

  Uri get messagesUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/messages')) return Uri.parse(raw);
    raw = raw.replaceFirst(RegExp(r'/(?:chat/completions|responses)$'), '');
    if (raw.endsWith('/v1')) return Uri.parse('$raw/messages');
    return Uri.parse('$raw/v1/messages');
  }

  Uri get responsesUri {
    if (isOpenAiCodexOAuth) {
      return Uri.parse('$openAiCodexBaseUrl/codex/responses');
    }
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/responses')) return Uri.parse(raw);
    raw = raw.replaceFirst(RegExp(r'/(?:chat/completions|messages)$'), '');
    if (raw.endsWith('/v1')) return Uri.parse('$raw/responses');
    return Uri.parse('$raw/v1/responses');
  }

  /// 服务商模型目录端点。允许用户粘贴完整的旧式 endpoint，仍归一到
  /// 同一 API 根，避免出现 `/v1/chat/completions/v1/models`。
  Uri get modelsUri {
    if (isOpenAiCodexOAuth) {
      return Uri.parse('$openAiCodexBaseUrl/codex/models').replace(
        queryParameters: const {
          'client_version': openAiCodexClientVersion,
        },
      );
    }
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = isDeepSeek ? deepSeekBaseUrl : customDefaultBaseUrl;
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    raw = raw.replaceFirst(
      RegExp(r'/(?:chat/completions|messages|responses|models)$'),
      '',
    );
    if (raw.endsWith('/v1')) return Uri.parse('$raw/models');
    return Uri.parse('$raw/v1/models');
  }

  Map<String, String> authHeaders({bool json = true}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    if (shouldUseClaudeMessages && authMethod != AiAuthMethod.oauth) {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    if (isOpenAiCodexOAuth) {
      final accountId = oauthAccountId.trim();
      if (accountId.isNotEmpty) headers['ChatGPT-Account-Id'] = accountId;
      headers['originator'] = 'codex_vscode';
      headers['User-Agent'] = 'codex_vscode/0.146.0';
      headers['OpenAI-Beta'] = 'responses=v1';
      // The ChatGPT subscription endpoint is an SSE-only Responses endpoint,
      // even when callers buffer the result before returning it.
      headers['Accept'] = 'text/event-stream';
    }
    return headers;
  }

  /// Web-search tool payload for a Responses provider.
  ///
  /// The public OpenAI API currently documents `web_search_preview`, while
  /// the ChatGPT/Codex subscription endpoint uses `web_search` and exposes
  /// the live-access switch from the open-source Codex client. Keep that
  /// distinction in the provider config so every request path sends the same
  /// contract.
  List<Map<String, dynamic>> get responsesWebSearchTools {
    if (!webSearchEnabled) return const [];
    if (isOpenAiCodexOAuth) {
      return const [
        {
          'type': 'web_search',
          'external_web_access': true,
          'search_context_size': 'high',
        },
      ];
    }
    final type = isOpenAiOfficial ? 'web_search_preview' : 'web_search';
    return [
      {'type': type},
    ];
  }

  /// Public Responses can return structured search sources when this include
  /// field is requested. The private Codex endpoint returns its source items
  /// directly, and some relays reject unknown `include` fields, so only add it
  /// for the official public API.
  List<String> get responsesWebSearchIncludes {
    if (!webSearchEnabled || !isOpenAiOfficial || isOpenAiCodexOAuth) {
      return const [];
    }
    return const ['web_search_call.action.sources'];
  }

  /// 检测是否是 Claude 模型（需要用 /v1/messages）
  bool get isClaudeModel {
    final m = model.toLowerCase();
    final u = baseUrl.toLowerCase();
    return m.contains('claude') ||
        u.contains('anthropic') ||
        u.contains('claude');
  }

  AiProviderConfig copyWith({
    AiProviderType? type,
    String? apiKey,
    String? baseUrl,
    String? model,
    AiEndpointType? endpointType,
    AiAuthMethod? authMethod,
    AiReasoningEffort? reasoningEffort,
    bool? webSearchEnabled,
    String? displayName,
    String? providerId,
    String? oauthAccountId,
    String? oauthRefreshToken,
    int? oauthExpiresAtMs,
    OAuthTokenSaver? oauthTokenSaver,
  }) =>
      AiProviderConfig(
        type: type ?? this.type,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        endpointType: endpointType ?? this.endpointType,
        authMethod: authMethod ?? this.authMethod,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
        displayName: displayName ?? this.displayName,
        providerId: providerId ?? this.providerId,
        oauthAccountId: oauthAccountId ?? this.oauthAccountId,
        oauthRefreshToken: oauthRefreshToken ?? this.oauthRefreshToken,
        oauthExpiresAtMs: oauthExpiresAtMs ?? this.oauthExpiresAtMs,
        oauthTokenSaver: oauthTokenSaver ?? this.oauthTokenSaver,
      );

  /// Chats 默认走 OpenAI Responses SSE，令 reasoning.effort 真正进入
  /// 请求；但不能把直连 DeepSeek/Anthropic 强塞进不支持的端点。
  ///
  /// 显式选过端点的服务商优先遵从用户配置。未指定的自定义中转通常接收
  /// Responses 协议，官方 Anthropic 则保留原生 Messages 协议。
  AiProviderConfig forChatStreaming() {
    if (isDeepSeek ||
        endpointType != AiEndpointType.auto ||
        isAnthropicOfficial) {
      return this;
    }
    return copyWith(endpointType: AiEndpointType.responses);
  }

  factory AiProviderConfig.deepSeek({
    required String apiKey,
    String? displayName,
    bool webSearchEnabled = false,
  }) =>
      AiProviderConfig(
        type: AiProviderType.deepseek,
        apiKey: apiKey,
        baseUrl: deepSeekBaseUrl,
        model: deepSeekModel,
        endpointType: AiEndpointType.chatCompletions,
        authMethod: AiAuthMethod.apiKey,
        reasoningEffort: AiReasoningEffort.none,
        webSearchEnabled: webSearchEnabled,
        displayName: displayName,
      );

  factory AiProviderConfig.custom({
    required String apiKey,
    required String baseUrl,
    required String model,
    AiEndpointType endpointType = AiEndpointType.auto,
    AiAuthMethod authMethod = AiAuthMethod.apiKey,
    AiReasoningEffort reasoningEffort = AiReasoningEffort.none,
    bool webSearchEnabled = false,
    String? displayName,
  }) =>
      AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: apiKey,
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        endpointType: endpointType,
        authMethod: authMethod,
        reasoningEffort: reasoningEffort,
        webSearchEnabled: webSearchEnabled,
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

  /// Models explicitly removed from the upstream catalogue by the user.
  /// Keeping this separate from [models] prevents refreshes from resurrecting
  /// models the user intentionally removed.
  final List<String> excludedModels;
  final AiEndpointType endpointType;
  final AiAuthMethod authMethod;
  final AiReasoningEffort reasoningEffort;
  final bool webSearchEnabled;
  final bool builtIn;
  final bool enabled;
  final String oauthAuthorizationUrl;
  final String oauthAccountId;

  /// Non-secret account identity used when exporting portable account files.
  final String accountEmail;

  /// ID token is sensitive and is persisted in SecureKeyStore, never in the
  /// provider metadata JSON.
  final String oauthIdToken;
  final String oauthRefreshToken;
  final int? oauthExpiresAtMs;

  AiConfiguredProvider({
    required this.id,
    required this.type,
    required this.displayName,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    Iterable<String> models = const [],
    Iterable<String> excludedModels = const [],
    this.endpointType = AiEndpointType.auto,
    this.authMethod = AiAuthMethod.apiKey,
    this.reasoningEffort = AiReasoningEffort.none,
    this.webSearchEnabled = false,
    this.builtIn = false,
    this.enabled = true,
    this.oauthAuthorizationUrl = '',
    this.oauthAccountId = '',
    this.accountEmail = '',
    this.oauthIdToken = '',
    this.oauthRefreshToken = '',
    this.oauthExpiresAtMs,
  })  : models = _normalizeModels(models, model),
        excludedModels = _normalizeExcludedModels(excludedModels);

  String get label =>
      displayName.trim().isEmpty ? type.label : displayName.trim();

  bool get hasKey => apiKey.trim().isNotEmpty;

  bool get hasBaseUrl => baseUrl.trim().isNotEmpty;

  /// The model selected for this account. A fetched catalogue can contain
  /// models even when older metadata did not persist the primary separately.
  String get selectedModel {
    final primary = model.trim();
    if (primary.isNotEmpty && !excludedModels.contains(primary)) {
      return primary;
    }
    return models
            .where((candidate) => !excludedModels.contains(candidate))
            .firstOrNull ??
        '';
  }

  bool get hasModel => selectedModel.isNotEmpty;

  /// OAuth access tokens are kept in the same secure slot as API keys, but
  /// remain distinguishable in metadata so the request layer can choose the
  /// correct auth header.  An account is usable only when it is enabled and
  /// has a credential.
  bool get hasCredential =>
      hasKey ||
      (authMethod == AiAuthMethod.oauth && oauthRefreshToken.trim().isNotEmpty);

  bool get isConfigured => hasCredential && hasBaseUrl && hasModel;

  bool get isUsable => enabled && isConfigured;

  AiProviderConfig toConfig({
    String? modelOverride,
    AiReasoningEffort? effortOverride,
    bool? webSearchEnabled,
  }) {
    final requested = (modelOverride ?? model).trim();
    final chosen = requested.isNotEmpty && !excludedModels.contains(requested)
        ? requested
        : selectedModel;
    return AiProviderConfig(
      type: type,
      apiKey: apiKey,
      baseUrl: baseUrl.trim(),
      model: chosen,
      endpointType: endpointType,
      authMethod: authMethod,
      reasoningEffort: effortOverride ?? reasoningEffort,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      displayName: label,
      providerId: id,
      oauthAccountId: oauthAccountId,
      oauthRefreshToken: oauthRefreshToken,
      oauthExpiresAtMs: oauthExpiresAtMs,
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
    Iterable<String>? excludedModels,
    AiEndpointType? endpointType,
    AiAuthMethod? authMethod,
    AiReasoningEffort? reasoningEffort,
    bool? webSearchEnabled,
    bool? builtIn,
    bool? enabled,
    String? oauthAuthorizationUrl,
    String? oauthAccountId,
    String? accountEmail,
    String? oauthIdToken,
    String? oauthRefreshToken,
    int? oauthExpiresAtMs,
  }) =>
      AiConfiguredProvider(
        id: id ?? this.id,
        type: type ?? this.type,
        displayName: displayName ?? this.displayName,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        models: models ?? this.models,
        excludedModels: excludedModels ?? this.excludedModels,
        endpointType: endpointType ?? this.endpointType,
        authMethod: authMethod ?? this.authMethod,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
        builtIn: builtIn ?? this.builtIn,
        enabled: enabled ?? this.enabled,
        oauthAuthorizationUrl:
            oauthAuthorizationUrl ?? this.oauthAuthorizationUrl,
        oauthAccountId: oauthAccountId ?? this.oauthAccountId,
        accountEmail: accountEmail ?? this.accountEmail,
        oauthIdToken: oauthIdToken ?? this.oauthIdToken,
        oauthRefreshToken: oauthRefreshToken ?? this.oauthRefreshToken,
        oauthExpiresAtMs: oauthExpiresAtMs ?? this.oauthExpiresAtMs,
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
        'excludedModels': excludedModels,
        'endpointType': endpointType.storageKey,
        'authMethod': authMethod.storageKey,
        'reasoningEffort': reasoningEffort.storageKey,
        'webSearchEnabled': webSearchEnabled,
        'builtIn': builtIn,
        'enabled': enabled,
        'oauthAuthorizationUrl': oauthAuthorizationUrl,
        'oauthAccountId': oauthAccountId,
        'accountEmail': accountEmail,
        'oauthExpiresAtMs': oauthExpiresAtMs,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AiConfiguredProvider.fromJson(
    Map<String, dynamic> json, {
    String apiKey = '',
    String oauthIdToken = '',
    String oauthRefreshToken = '',
  }) {
    final type = AiProviderTypeX.fromStorage(json['type'] as String?);
    final rawModels = json['models'];
    final models =
        rawModels is List ? rawModels.whereType<String>() : const <String>[];
    final rawExcludedModels = json['excludedModels'];
    final excludedModels = rawExcludedModels is List
        ? rawExcludedModels.whereType<String>()
        : const <String>[];
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
      excludedModels: excludedModels,
      endpointType:
          AiEndpointTypeX.fromStorage(json['endpointType'] as String?),
      authMethod: AiAuthMethodX.fromStorage(json['authMethod'] as String?),
      reasoningEffort: AiReasoningEffortX.fromStorage(
        json['reasoningEffort'] as String?,
      ),
      webSearchEnabled: json['webSearchEnabled'] == true,
      builtIn: json['builtIn'] == true,
      enabled: json['enabled'] != false,
      oauthAuthorizationUrl:
          (json['oauthAuthorizationUrl'] as String? ?? '').trim(),
      oauthAccountId: (json['oauthAccountId'] as String? ?? '').trim(),
      accountEmail: (json['accountEmail'] as String? ?? '').trim(),
      oauthIdToken: oauthIdToken,
      oauthRefreshToken: oauthRefreshToken,
      oauthExpiresAtMs: json['oauthExpiresAtMs'] is num
          ? (json['oauthExpiresAtMs'] as num).toInt()
          : int.tryParse(json['oauthExpiresAtMs']?.toString() ?? ''),
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

  static List<String> _normalizeExcludedModels(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
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
