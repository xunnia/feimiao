import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_account_json.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';

void main() {
  group('AiAccountJsonCodec', () {
    test('parses Cockpit flat OAuth account and normalizes expiry', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'id': 'cockpit-1',
        'type': 'codex',
        'email': 'person@example.com',
        'account_id': 'acct-1',
        'access_token': 'access-secret',
        'refresh_token': 'refresh-secret',
        'id_token': 'id-secret',
        'expired': 1750000000,
      }));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.source, AiAccountJsonSource.cockpit);
      expect(account.authMethod, AiAuthMethod.oauth);
      expect(account.baseUrl, AiProviderConfig.openAiCodexBaseUrl);
      expect(account.accountEmail, 'person@example.com');
      expect(account.expiresAtMs, 1750000000000);
      expect(account.maskedIdentity, 'pe***@example.com');
    });

    test('parses official auth.json token envelope and OPENAI_API_KEY', () {
      final oauth = AiAccountJsonCodec.parse(jsonEncode({
        'tokens': {
          'access_token': 'access',
          'refresh_token': 'refresh',
          'account_id': 'acct',
        },
      }));
      expect(oauth.accounts.single.authMethod, AiAuthMethod.oauth);
      expect(oauth.accounts.single.accessToken, 'access');

      final api = AiAccountJsonCodec.parse(jsonEncode({
        'OPENAI_API_KEY': 'sk-test',
      }));
      expect(api.accounts.single.authMethod, AiAuthMethod.apiKey);
      expect(api.accounts.single.apiKey, 'sk-test');
    });

    test('parses Sub2API credentials and model catalogue', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'accounts': [
          {
            'id': 'sub-1',
            'name': '中转站',
            'base_url': 'https://relay.example/v1',
            'model': 'claude-3-7-sonnet',
            'credentials': {'api_key': 'relay-key'},
          },
        ],
      }));
      final account = result.accounts.single;
      expect(account.source, AiAccountJsonSource.sub2Api);
      expect(account.baseUrl, 'https://relay.example/v1');
      expect(account.model, 'claude-3-7-sonnet');
      expect(account.apiKey, 'relay-key');
    });

    test('supports arrays and de-duplicates by account identity', () {
      final result = AiAccountJsonCodec.parse(jsonEncode([
        {
          'type': 'codex',
          'email': 'same@example.com',
          'access_token': 'access-1',
        },
        {
          'type': 'codex',
          'email': 'same@example.com',
          'access_token': 'access-2',
        },
      ]));
      expect(result.accounts, hasLength(1));
      expect(result.warnings, contains(contains('重复账号')));
    });

    test('Cockpit export includes credentials but metadata JSON does not', () {
      final provider = AiConfiguredProvider(
        id: 'oauth-1',
        type: AiProviderType.custom,
        displayName: 'GPT',
        baseUrl: AiProviderConfig.openAiCodexBaseUrl,
        apiKey: 'access-secret',
        model: 'gpt-5',
        models: const ['gpt-5'],
        authMethod: AiAuthMethod.oauth,
        endpointType: AiEndpointType.responses,
        oauthAccountId: 'acct-1',
        accountEmail: 'person@example.com',
        oauthIdToken: 'id-secret',
        oauthRefreshToken: 'refresh-secret',
      );
      final exported = AiAccountJsonCodec.encodeCockpit([provider]);
      expect(exported, contains('access-secret'));
      expect(exported, contains('refresh-secret'));
      expect(provider.toJsonString(), isNot(contains('access-secret')));
      expect(provider.toJsonString(), isNot(contains('id-secret')));
    });

    test('invalid and credential-less JSON fail closed', () {
      expect(AiAccountJsonCodec.parse('{bad').accounts, isEmpty);
      expect(
        AiAccountJsonCodec.parse('{"email":"a@example.com"}').accounts,
        isEmpty,
      );
    });
  });
}
