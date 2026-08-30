import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query.dart';
import 'package:qingji/core/ai/openai_codex_oauth.dart';

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

  test('fetchModels refuses a blank custom base URL before making a request',
      () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });

    await expectLater(
      LlmQuery.fetchModels(
        config.copyWith(baseUrl: ''),
        client: client,
      ),
      throwsA(
        isA<LlmQueryException>().having(
          (error) => error.message,
          'message',
          contains('基础地址未配置'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('fetchModels uses native Claude headers', () async {
    const claude = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'anthropic-key',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-sonnet-5',
    );
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.anthropic.com/v1/models');
      expect(request.headers['x-api-key'], 'anthropic-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers['authorization'], isNull);
      return http.Response('{"data":[{"id":"claude-sonnet-5"}]}', 200);
    });

    expect(
      await LlmQuery.fetchModels(claude, client: client),
      const ['claude-sonnet-5'],
    );
  });

  test('fetchModels keeps Bearer auth for Claude-named custom relays',
      () async {
    final relay = config.copyWith(model: 'claude-sonnet-5');
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://o10.top/v1/models');
      expect(request.headers['authorization'], 'Bearer test-key');
      expect(request.headers['x-api-key'], isNull);
      expect(request.headers['anthropic-version'], isNull);
      return http.Response('{"data":[{"id":"claude-sonnet-5"}]}', 200);
    });

    expect(
      await LlmQuery.fetchModels(relay, client: client),
      const ['claude-sonnet-5'],
    );
  });

  test('fetchModels honors explicit Claude Messages on a custom relay',
      () async {
    final relay = config.copyWith(
      model: 'claude-sonnet-5',
      endpointType: AiEndpointType.anthropicMessages,
    );
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://o10.top/v1/models');
      expect(request.headers['x-api-key'], 'test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers['authorization'], isNull);
      return http.Response('{"data":[{"id":"claude-sonnet-5"}]}', 200);
    });

    expect(
      await LlmQuery.fetchModels(relay, client: client),
      const ['claude-sonnet-5'],
    );
  });

  test('OAuth Claude relay uses Bearer instead of x-api-key', () async {
    final relay = config.copyWith(
      model: 'claude-sonnet-5',
      endpointType: AiEndpointType.anthropicMessages,
      authMethod: AiAuthMethod.oauth,
    );
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer test-key');
      expect(request.headers['x-api-key'], isNull);
      return http.Response('{"data":[{"id":"claude-sonnet-5"}]}', 200);
    });
    expect(
      await LlmQuery.fetchModels(relay, client: client),
      const ['claude-sonnet-5'],
    );
  });

  test('fetchModels accepts a models array and string entries', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://o10.top/v1/models');
      return http.Response(
        jsonEncode({
          'models': [
            'model-a',
            {'name': 'model-b'}
          ]
        }),
        200,
      );
    });

    expect(
      await LlmQuery.fetchModels(config, client: client),
      const ['model-a', 'model-b'],
    );
  });

  test('fetchModels shares the injected client for PAT identity and catalog',
      () async {
    var calls = 0;
    String? savedAccountId;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        expect(
          request.url.toString(),
          OpenAiCodexOAuth.personalAccessTokenWhoAmIEndpoint,
        );
        return http.Response(
          '{"email":"pat@example.com","chatgpt_user_id":"u-1",'
          '"chatgpt_account_id":"acct-pat","chatgpt_plan_type":"pro",'
          '"chatgpt_account_is_fedramp":false}',
          200,
        );
      }
      expect(request.url.path, '/backend-api/codex/models');
      expect(request.headers['chatgpt-account-id'], 'acct-pat');
      return http.Response('{"models":[{"slug":"gpt-pat"}]}', 200);
    });
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'at-personal-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-pat',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthTokenSaver: (access, refresh, expiresAt, accountId) async {
        savedAccountId = accountId;
      },
    );

    expect(
      await LlmQuery.fetchModels(config, client: client),
      const ['gpt-pat'],
    );
    expect(calls, 2);
    expect(savedAccountId, 'acct-pat');
  });

  test('fetchModels tries a non-v1 models path after a 404', () async {
    final client = MockClient((request) async {
      if (request.url.toString() == 'https://o10.top/v1/models') {
        return http.Response('{}', 404);
      }
      expect(request.url.toString(), 'https://o10.top/models');
      return http.Response('{"data":[{"id":"model-a"}]}', 200);
    });

    expect(
      await LlmQuery.fetchModels(config, client: client),
      const ['model-a'],
    );
  });

  test('fetchModels tries the alternate path after a primary timeout',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.url.toString() == 'https://o10.top/v1/models') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }
      expect(request.url.toString(), 'https://o10.top/models');
      return http.Response('{"data":[{"id":"model-a"}]}', 200);
    });

    expect(
      await LlmQuery.fetchModels(
        config,
        client: client,
        timeout: const Duration(milliseconds: 1),
      ),
      const ['model-a'],
    );
    expect(calls, 2);
  });
}
