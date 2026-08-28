import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';

void main() {
  group('AiConfiguredProvider', () {
    test('custom relays keep Bearer auth even when the model is Claude-named',
        () {
      final compatible = AiProviderConfig.custom(
        apiKey: 'key',
        baseUrl: 'https://relay.example/v1',
        model: 'claude-sonnet',
        endpointType: AiEndpointType.chatCompletions,
      );
      expect(compatible.shouldUseClaudeMessages, isFalse);

      final native = compatible.copyWith(endpointType: AiEndpointType.auto);
      expect(native.shouldUseClaudeMessages, isFalse);

      final explicit = compatible.copyWith(
        endpointType: AiEndpointType.anthropicMessages,
      );
      expect(explicit.shouldUseClaudeMessages, isTrue);
      expect(explicit.messagesUri.path, '/v1/messages');
    });

    test(
        'refresh-only OAuth accounts count as credentials before first refresh',
        () {
      final refreshOnly = AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: '',
        baseUrl: AiProviderConfig.openAiCodexBaseUrl,
        model: 'gpt-5.4',
        endpointType: AiEndpointType.responses,
        authMethod: AiAuthMethod.oauth,
        oauthAccountId: 'acct-refresh-only',
        oauthRefreshToken: 'refresh-token',
      );

      expect(refreshOnly.hasKey, isFalse);
      expect(refreshOnly.hasCredential, isTrue);
      expect(refreshOnly.hasBaseUrl, isTrue);
      expect(refreshOnly.hasModel, isTrue);
    });

    test('Claude budget mapping keeps the new Max and Ultra levels', () {
      expect(AiReasoningEffort.xhigh.claudeBudgetTokens, 24576);
      expect(AiReasoningEffort.max.claudeBudgetTokens, 32768);
      expect(AiReasoningEffort.ultra.claudeBudgetTokens, 65536);
    });

    test('Chats choose Responses by default without breaking native providers',
        () {
      final relay = AiProviderConfig.custom(
        apiKey: 'key',
        baseUrl: 'https://relay.example/v1',
        model: 'gpt-5',
      );
      expect(
        relay.forChatStreaming().endpointType,
        AiEndpointType.responses,
      );

      final directClaude = AiProviderConfig.custom(
        apiKey: 'key',
        baseUrl: 'https://api.anthropic.com/v1',
        model: 'claude-sonnet',
      );
      expect(
        directClaude.forChatStreaming().shouldUseClaudeMessages,
        isTrue,
      );

      final deepSeek = AiProviderConfig.deepSeek(apiKey: 'key').copyWith(
        reasoningEffort: AiReasoningEffort.high,
      );
      expect(
        deepSeek.forChatStreaming().endpointType,
        AiEndpointType.chatCompletions,
      );
      expect(deepSeek.reasoningEffort.deepSeekApiValue, 'high');
    });

    test('normalizes models without losing the selected model', () {
      final provider = AiConfiguredProvider(
        id: 'gateway-a',
        type: AiProviderType.custom,
        displayName: 'Gateway A',
        baseUrl: 'https://example.com',
        apiKey: 'secret',
        model: 'model-b',
        models: const [' model-a ', 'model-b', 'model-a', ''],
        excludedModels: const [' model-old ', 'model-old', ''],
      );

      expect(provider.models, const ['model-b', 'model-a']);
      expect(provider.excludedModels, const ['model-old']);
      expect(provider.toConfig().model, 'model-b');
    });

    test('incomplete custom accounts never inherit OpenAI or DeepSeek defaults',
        () {
      final provider = AiConfiguredProvider(
        id: 'unfinished',
        type: AiProviderType.custom,
        displayName: '',
        baseUrl: '',
        apiKey: 'secret',
        model: '',
      );

      expect(provider.isConfigured, isFalse);
      expect(provider.isUsable, isFalse);
      expect(provider.toConfig().baseUrl, isEmpty);
      expect(provider.toConfig().model, isEmpty);
      expect(provider.toConfig().modelCandidates, isEmpty);
    });

    test('a fetched model can complete an account whose primary was blank', () {
      final provider = AiConfiguredProvider(
        id: 'catalogued',
        type: AiProviderType.custom,
        displayName: 'Gateway',
        baseUrl: 'https://gateway.example/v1',
        apiKey: 'secret',
        model: '',
        models: const ['gateway-chat'],
      );

      expect(provider.selectedModel, 'gateway-chat');
      expect(provider.isUsable, isTrue);
      expect(provider.toConfig().model, 'gateway-chat');
    });

    test('excluded models cannot become the effective primary', () {
      final provider = AiConfiguredProvider(
        id: 'excluded-primary',
        type: AiProviderType.custom,
        displayName: 'Gateway',
        baseUrl: 'https://gateway.example/v1',
        apiKey: 'secret',
        model: 'old-model',
        models: const ['old-model', 'new-model'],
        excludedModels: const ['old-model'],
      );

      expect(provider.selectedModel, 'new-model');
      expect(provider.toConfig().model, 'new-model');
    });

    test('metadata round trip never serializes the api key', () {
      final provider = AiConfiguredProvider(
        id: 'gateway-a',
        type: AiProviderType.custom,
        displayName: 'Gateway A',
        baseUrl: 'https://example.com/v1',
        apiKey: 'must-not-leak',
        model: 'model-a',
        models: const ['model-a', 'model-b'],
        excludedModels: const ['model-old'],
        enabled: false,
      );

      final metadata = provider.toJson();
      expect(metadata.containsKey('apiKey'), isFalse);
      expect(provider.toJsonString(), isNot(contains('must-not-leak')));

      final restored = AiConfiguredProvider.fromJson(
        metadata,
        apiKey: 'restored-secret',
      );
      expect(restored.id, provider.id);
      expect(restored.models, provider.models);
      expect(restored.excludedModels, provider.excludedModels);
      expect(restored.apiKey, 'restored-secret');
      expect(restored.enabled, isFalse);
    });

    test('same model name from two providers keeps distinct identity', () {
      const first = AiModelOption(
        providerId: 'one',
        providerLabel: 'One',
        model: 'shared-model',
      );
      const second = AiModelOption(
        providerId: 'two',
        providerLabel: 'Two',
        model: 'shared-model',
      );

      expect(first, isNot(second));
      expect(first.key, isNot(second.key));
      expect({first, second}, hasLength(2));
    });
  });
}
