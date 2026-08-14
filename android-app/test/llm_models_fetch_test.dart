import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query.dart';

void main() {
  const config = AiProviderConfig(
    type: AiProviderType.custom,
    apiKey: 'test-key',
    baseUrl: 'https://o10.top',
    model: 'model-a',
  );

  test('fetchModels uses v1 endpoint, bearer auth, trim and dedupe', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://o10.top/v1/models');
      expect(request.headers['authorization'], 'Bearer test-key');
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'model-a'},
            {'id': ' model-b '},
            {'id': 'model-a'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    expect(
      await LlmQuery.fetchModels(config, client: client),
      const ['model-a', 'model-b'],
    );
  });

  test('fetchModels does not duplicate v1 already in base URL', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://o10.top/v1/models');
      return http.Response('{"data":[{"id":"model-a"}]}', 200);
    });

    await LlmQuery.fetchModels(
      config.copyWith(baseUrl: 'https://o10.top/v1/'),
      client: client,
    );
  });

  test('fetchModels reports authentication failures', () async {
    final client = MockClient((_) async => http.Response('{}', 401));

    await expectLater(
      LlmQuery.fetchModels(config, client: client),
      throwsA(
        isA<LlmQueryException>().having(
          (error) => error.message,
          'message',
          contains('API Key 无效'),
        ),
      ),
    );
  });
}
