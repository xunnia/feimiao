import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/ai/ai_account_verification.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';

void main() {
  test('does not attempt network for an incomplete imported account', () async {
    final result = await const AiAccountVerificationService().verify(
      const AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: '',
        baseUrl: '',
        model: '',
      ),
    );

    expect(result.status, AiAccountVerificationStatus.configurationError);
    expect(result.models, isEmpty);
  });

  test('verifies OAuth catalogue and minimal Responses probe together',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/backend-api/codex/models') {
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(request.headers['chatgpt-account-id'], 'acct-test');
        return http.Response(
          jsonEncode({
            'models': [
              {'slug': 'gpt-test'},
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/backend-api/codex/responses') {
        expect(request.headers['authorization'], 'Bearer access-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'gpt-test');
        expect(body['stream'], true);
        expect(body['store'], false);
        final input = body['input'] as List;
        expect(input.last, isA<Map>());
        expect(
          ((input.last as Map)['content'] as List).first['text'],
          'ping',
        );
        return http.Response(
          'data: {"type":"response.output_text.done","text":"OK"}\n'
          'data: {"type":"response.completed","response":{"output":[]}}\n'
          'data: [DONE]\n',
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }
      fail('unexpected URL: ${request.url}');
    });

    final result = await AiAccountVerificationService(client: client).verify(
      const AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'access-token',
        baseUrl: AiProviderConfig.openAiCodexBaseUrl,
        model: 'gpt-fallback',
        endpointType: AiEndpointType.responses,
        authMethod: AiAuthMethod.oauth,
        oauthAccountId: 'acct-test',
      ),
    );

    expect(result.status, AiAccountVerificationStatus.available);
    expect(result.models, ['gpt-test']);
    expect(result.isAvailable, isTrue);
  });

  test('discovers a missing API-key model before the minimal probe', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/models') {
        expect(request.headers['authorization'], 'Bearer relay-key');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'relay-model'},
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/v1/chat/completions') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'relay-model');
        expect(body['messages'], isA<List>());
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'OK'},
              },
            ],
          }),
          200,
        );
      }
      fail('unexpected URL: ${request.url}');
    });

    final result = await AiAccountVerificationService(client: client).verify(
      const AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'relay-key',
        baseUrl: 'https://relay.example/v1',
        model: '',
        endpointType: AiEndpointType.chatCompletions,
      ),
    );

    expect(result.status, AiAccountVerificationStatus.available);
    expect(result.models, ['relay-model']);
  });

  test('classifies authorization and proxy failures without exposing secrets',
      () async {
    final authClient = MockClient((_) async => http.Response(
          '{"error":"invalid_grant","access_token":"sk-secret-value"}',
          401,
        ));
    final authResult =
        await AiAccountVerificationService(client: authClient).verify(
      const AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'access-token',
        baseUrl: AiProviderConfig.openAiCodexBaseUrl,
        model: 'gpt-test',
        endpointType: AiEndpointType.responses,
        authMethod: AiAuthMethod.oauth,
        oauthAccountId: 'acct-test',
      ),
    );
    expect(authResult.status, AiAccountVerificationStatus.invalidCredential);
    expect(authResult.message, isNot(contains('sk-secret-value')));
  });
}
