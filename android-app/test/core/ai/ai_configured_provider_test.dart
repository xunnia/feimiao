import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';

void main() {
  group('AiConfiguredProvider', () {
    test('normalizes models without losing the selected model', () {
      final provider = AiConfiguredProvider(
        id: 'gateway-a',
        type: AiProviderType.custom,
        displayName: 'Gateway A',
        baseUrl: 'https://example.com',
        apiKey: 'secret',
        model: 'model-b',
        models: const [' model-a ', 'model-b', 'model-a', ''],
      );

      expect(provider.models, const ['model-b', 'model-a']);
      expect(provider.toConfig().model, 'model-b');
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
      expect(restored.apiKey, 'restored-secret');
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
