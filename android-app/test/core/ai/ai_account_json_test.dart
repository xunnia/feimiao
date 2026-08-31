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
      expect(account.model, AiProviderConfig.openAiCodexDefaultModel);
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

    test('type codex plus OPENAI_API_KEY stays an API Key account', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'auth_mode': 'apikey',
        'OPENAI_API_KEY': 'sk-codex-api-key',
      }));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.authMethod, AiAuthMethod.apiKey);
      expect(account.apiKey, 'sk-codex-api-key');
      expect(account.accessToken, isEmpty);
      // The repository applies the official default endpoint when importing;
      // the codec itself preserves the omitted address as empty.
      expect(account.baseUrl, isEmpty);
    });

    test('type codex with only an API key infers API Key mode', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'api_key': 'sk-generic-codex-key',
      }));

      expect(result.accounts.single.authMethod, AiAuthMethod.apiKey);
      expect(result.accounts.single.apiKey, 'sk-generic-codex-key');
    });

    test('parses Cockpit full CodexAccount export with nested tokens', () {
      final result = AiAccountJsonCodec.parse(jsonEncode([
        {
          'id': 'codex-local-account',
          'email': 'cockpit@example.com',
          'account_name': 'Personal workspace',
          'auth_mode': 'OAuth',
          'account_id': 'acct-cockpit',
          'tokens': {
            'id_token': 'id-from-cockpit',
            'access_token': 'access-from-cockpit',
            'refresh_token': 'refresh-from-cockpit',
            'account_id': 'acct-cockpit',
          },
        },
      ]));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.source, AiAccountJsonSource.openAiAuth);
      expect(account.authMethod, AiAuthMethod.oauth);
      expect(account.sourceId, 'codex-local-account');
      expect(account.accountEmail, 'cockpit@example.com');
      expect(account.accountId, 'acct-cockpit');
      expect(account.accessToken, 'access-from-cockpit');
      expect(account.refreshToken, 'refresh-from-cockpit');
      expect(account.idToken, 'id-from-cockpit');
      expect(account.displayName, 'Personal workspace');
    });

    test('parses Cockpit full-backup platform exported_data envelope', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'schema': 'cockpit-backup',
        'version': 1,
        'exported_at': '2026-08-29T00:00:00Z',
        'accounts': {
          'schema': 'cockpit-accounts',
          'summary': {'platform_count': 2, 'account_count': 1},
          'platforms': {
            'codex': {
              'account_count': 1,
              'exported_data': [
                {
                  'id': 'codex-backup-account',
                  'email': 'backup@example.com',
                  'auth_mode': 'OAuth',
                  'tokens': {
                    'access_token': 'backup-access',
                    'refresh_token': 'backup-refresh',
                    'id_token': 'backup-id',
                    'account_id': 'acct-backup',
                  },
                },
              ],
            },
            'claude_manager': {
              'account_count': 1,
              'exported_data': [
                {'email': 'claude@example.com', 'access_token': 'not-gpt'},
              ],
            },
          },
        },
        'config': {},
      }));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.source, AiAccountJsonSource.cockpit);
      expect(account.accountEmail, 'backup@example.com');
      expect(account.accountId, 'acct-backup');
      expect(account.refreshToken, 'backup-refresh');
    });

    test('recognizes a metadata-only Cockpit index without importing it', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'version': 1,
        'detail_schema_version': 1,
        'accounts': [
          {
            'id': 'metadata-only',
            'email': 'index@example.com',
            'plan_type': 'plus',
          },
        ],
        'current_account_id': 'metadata-only',
      }));

      expect(result.accounts, isEmpty);
      expect(result.warnings.join('；'), contains('缺少可用密钥'));
    });

    test('parses a standalone Cockpit platform transfer section', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'schema': 'cockpit-tools.account-transfer',
        'version': 1,
        'exported_at': '2026-08-30T00:00:00Z',
        'account_count': 1,
        'exported_data': [
          {
            'type': 'codex',
            'email': 'standalone@example.com',
            'access_token': 'standalone-access',
            'account_id': 'acct-standalone',
          },
        ],
      }));

      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.source, AiAccountJsonSource.cockpit);
      expect(result.accounts.single.accountId, 'acct-standalone');
    });

    test('accepts string-encoded Cockpit platform data and a single object',
        () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'schema': 'cockpit-tools.account-transfer',
        'version': 1,
        'exported_at': '2026-08-30T00:00:00Z',
        'platforms': jsonEncode({
          'codex': jsonEncode({
            'account_count': 1,
            'exported_data': jsonEncode({
              'type': 'codex',
              'email': 'string-envelope@example.com',
              'access_token': 'string-access',
              'account_id': 'acct-string-envelope',
            }),
          }),
        }),
      }));

      expect(result.accounts, hasLength(1));
      expect(
          result.accounts.single.accountEmail, 'string-envelope@example.com');
      expect(result.accounts.single.accountId, 'acct-string-envelope');
    });

    test('unwraps already-decoded map and list document wrappers', () {
      final mapResult = AiAccountJsonCodec.parse(jsonEncode({
        'data': {
          'type': 'codex',
          'email': 'map-wrapper@example.com',
          'access_token': 'map-access',
        },
      }));
      expect(mapResult.accounts, hasLength(1));
      expect(mapResult.accounts.single.accountEmail, 'map-wrapper@example.com');

      final listResult = AiAccountJsonCodec.parse(jsonEncode({
        'payload': [
          {
            'type': 'codex',
            'email': 'list-wrapper@example.com',
            'access_token': 'list-access',
          },
        ],
      }));
      expect(listResult.accounts, hasLength(1));
      expect(listResult.accounts.single.accountEmail,
          'list-wrapper@example.com');
    });

    test('parses a standalone exported_data credential object', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'exported_data': {
          'type': 'codex',
          'email': 'standalone-object@example.com',
          'access_token': 'standalone-object-access',
          'account_id': 'acct-standalone-object',
        },
      }));

      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.accountEmail,
          'standalone-object@example.com');
      expect(result.accounts.single.accountId, 'acct-standalone-object');
    });

    test('parses the official lowercase openai_api_key field', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'auth_mode': 'apikey',
        'openai_api_key': 'sk-lowercase-field',
      }));
      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.authMethod, AiAuthMethod.apiKey);
      expect(result.accounts.single.apiKey, 'sk-lowercase-field');
    });

    test('explicit apikey mode wins over stale nested OAuth token fields', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'auth_mode': 'apikey',
        'openai_api_key': 'sk-relay-key',
        'tokens': {
          'access_token': 'stale-access-token',
          'refresh_token': 'stale-refresh-token',
        },
        'api_base_url': 'https://relay.example/v1',
        'api_wire_api': 'chat_completions',
      }));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.authMethod, AiAuthMethod.apiKey);
      expect(account.apiKey, 'sk-relay-key');
      expect(account.accessToken, 'stale-access-token');
      expect(account.refreshToken, 'stale-refresh-token');
      expect(account.endpointType, AiEndpointType.chatCompletions);
    });

    test('top-level auth mode remains authoritative over nested auth mode', () {
      final topLevelApiKey = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'auth_mode': 'apikey',
        'api_key': 'top-level-api-key',
        'tokens': {
          'auth_mode': 'oauth',
          'access_token': 'stale-oauth-token',
        },
      }));
      expect(topLevelApiKey.accounts.single.authMethod, AiAuthMethod.apiKey);

      final topLevelOAuth = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'auth_mode': 'oauth',
        'access_token': 'top-level-access-token',
        'credentials': {
          'auth_mode': 'apikey',
          'api_key': 'stale-api-key',
        },
      }));
      expect(topLevelOAuth.accounts.single.authMethod, AiAuthMethod.oauth);
    });

    test(
        'uses Cockpit API model catalog without selecting internal review model',
        () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'auth_mode': 'apikey',
        'openai_api_key': 'sk-cockpit-api',
        'api_base_url': 'https://relay.example/v1',
        'api_model_catalog': ['codex-auto-review', 'gpt-5.4', 'gpt-5.4-mini'],
      }));
      final account = result.accounts.single;
      expect(account.models, ['gpt-5.4', 'gpt-5.4-mini']);
      expect(account.model, 'gpt-5.4');
      expect(account.baseUrl, 'https://relay.example/v1');
    });

    test('decodes UTF-8 BOM and UTF-16 account files', () {
      const json = '{"openai_api_key":"sk-encoded"}';
      final utf8Bom = <int>[0xEF, 0xBB, 0xBF, ...json.codeUnits];
      expect(
        AiAccountJsonCodec.parse(AiAccountJsonCodec.decodeBytes(utf8Bom))
            .accounts
            .single
            .apiKey,
        'sk-encoded',
      );

      final utf16Le = <int>[
        0xFF,
        0xFE,
        for (final unit in json.codeUnits) ...[
          unit & 0xFF,
          (unit >> 8) & 0xFF,
        ],
      ];
      expect(
        AiAccountJsonCodec.parse(AiAccountJsonCodec.decodeBytes(utf16Le))
            .accounts
            .single
            .apiKey,
        'sk-encoded',
      );
    });

    test('parses Cockpit personal access token and bearer header exports', () {
      final personal = AiAccountJsonCodec.parse(jsonEncode({
        'OPENAI_API_KEY': null,
        'personal_access_token': 'at-personal-token',
        'account_id': 'acct-personal',
        'email': 'personal@example.com',
        'type': 'codex',
      }));
      expect(personal.accounts, hasLength(1));
      expect(personal.accounts.single.authMethod, AiAuthMethod.oauth);
      expect(personal.accounts.single.accessToken, 'at-personal-token');
      expect(personal.accounts.single.accountId, 'acct-personal');

      final bearer = AiAccountJsonCodec.parse(jsonEncode({
        'headers': {
          'Authorization': 'Bearer at-header-token',
          'ChatGPT-Account-Id': 'acct-header',
        },
        'type': 'codex',
      }));
      expect(bearer.accounts, hasLength(1));
      expect(bearer.accounts.single.accessToken, 'at-header-token');
      expect(bearer.accounts.single.accountId, 'acct-header');
    });

    test('merges Cockpit provider wire format and catalog by provider id', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'schema': 'cockpit-tools.data-transfer',
        'accounts': {
          'platforms': {
            'codex': {
              'exported_data': [
                {
                  'id': 'relay-account',
                  'auth_mode': 'apikey',
                  'api_provider_id': 'cmp-relay',
                  'openai_api_key': 'sk-relay',
                },
              ],
            },
          },
        },
        'config': {
          'codex_model_providers': [
            {
              'id': 'cmp-relay',
              'name': 'Relay',
              'baseUrl': 'https://relay.example/v1',
              'wireApi': 'responses',
              'modelCatalog': ['gpt-relay'],
            },
          ],
        },
      }));

      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.baseUrl, 'https://relay.example/v1');
      expect(account.endpointType, AiEndpointType.responses);
      expect(account.models, ['gpt-relay']);
      expect(account.model, 'gpt-relay');
    });

    test('parses Cockpit web-session JSON and nested account identity', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'session_json': jsonEncode({
          'user': {'email': 'session@example.com'},
          'account': {'id': 'acct-session'},
          'accessToken': _jwt({'exp': 1800000000}),
          'authProvider': 'openai',
        }),
      }));
      expect(result.accounts, hasLength(1));
      final account = result.accounts.single;
      expect(account.authMethod, AiAuthMethod.oauth);
      expect(account.accessToken, isNotEmpty);
      expect(account.accountId, 'acct-session');
      expect(account.accountEmail, 'session@example.com');
      expect(account.expiresAtMs, 1800000000000);
    });

    test('parses accounts serialized as a keyed object', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'accounts': {
          'first': {
            'type': 'codex',
            'tokens': {
              'access_token': 'access-keyed',
              'refresh_token': 'refresh-keyed',
              'account_id': 'acct-keyed',
            },
          },
        },
      }));
      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.accountId, 'acct-keyed');
      expect(result.accounts.single.accessToken, 'access-keyed');
    });

    test('does not stringify nested token maps as credentials', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'token': {'refresh_token': 'refresh-only'},
      }));
      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.accessToken, isEmpty);
      expect(result.accounts.single.refreshToken, 'refresh-only');
    });

    test('reports Agent Identity exports instead of importing unusable data',
        () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'auth_mode': 'agentIdentity',
        'agent_identity': {
          'agent_runtime_id': 'runtime',
          'agent_private_key': 'private',
        },
      }));
      expect(result.accounts, isEmpty);
      expect(result.warnings.single, contains('Agent Identity'));
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

    test('detects Cockpit and Sub2API entries inside one accounts array', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'accounts': [
          {
            'type': 'codex',
            'email': 'cockpit@example.com',
            'access_token': 'cockpit-access',
          },
          {
            'type': 'oauth',
            'credentials': {
              'email': 'sub2api@example.com',
              'access_token': 'sub2api-access',
            },
          },
        ],
      }));

      expect(result.accounts, hasLength(2));
      expect(result.accounts[0].source, AiAccountJsonSource.cockpit);
      expect(result.accounts[1].source, AiAccountJsonSource.sub2Api);
    });

    test('accepts Cockpit JSON Lines exports', () {
      final result = AiAccountJsonCodec.parse('''
        {"type":"codex","email":"one@example.com","access_token":"one"}
        {"type":"codex","email":"two@example.com","access_token":"two"}
      ''');

      expect(result.accounts, hasLength(2));
      expect(result.accounts.map((account) => account.accountEmail),
          containsAll(<String>['one@example.com', 'two@example.com']));
    });

    test('parses CPA token_data envelope', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'type': 'codex',
        'email': 'cpa@example.com',
        'token_data': {
          'id_token': 'id-cpa',
          'access_token': 'access-cpa',
          'refresh_token': 'refresh-cpa',
          'account_id': 'acct-cpa',
        },
      }));

      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.authMethod, AiAuthMethod.oauth);
      expect(result.accounts.single.accessToken, 'access-cpa');
      expect(result.accounts.single.refreshToken, 'refresh-cpa');
      expect(result.accounts.single.accountId, 'acct-cpa');
    });

    test('unwraps a JSON string payload from a share wrapper', () {
      final result = AiAccountJsonCodec.parse(jsonEncode({
        'payload': jsonEncode({
          'type': 'codex',
          'email': 'wrapped@example.com',
          'access_token': 'wrapped-access',
        }),
      }));

      expect(result.accounts, hasLength(1));
      expect(result.accounts.single.accountEmail, 'wrapped@example.com');
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

    test('keeps distinct emails that share one workspace account id', () {
      final result = AiAccountJsonCodec.parse(jsonEncode([
        {
          'type': 'codex',
          'email': 'one@example.com',
          'account_id': 'shared-workspace',
          'access_token': 'access-one',
        },
        {
          'type': 'codex',
          'email': 'two@example.com',
          'account_id': 'shared-workspace',
          'access_token': 'access-two',
        },
        {
          'type': 'codex',
          'email': 'one@example.com',
          'account_id': 'shared-workspace',
          'access_token': 'access-one-rotated',
        },
      ]));

      expect(result.accounts, hasLength(2));
      expect(
        result.accounts.map((account) => account.accountEmail),
        containsAll(<String>['one@example.com', 'two@example.com']),
      );
      expect(result.warnings, contains(contains('重复账号')));
    });

    test('does not de-duplicate accounts by workspace id alone', () {
      final result = AiAccountJsonCodec.parse(jsonEncode([
        {
          'type': 'codex',
          'account_id': 'shared-workspace',
          'access_token': 'access-one',
        },
        {
          'type': 'codex',
          'account_id': 'shared-workspace',
          'access_token': 'access-two',
        },
      ]));

      expect(result.accounts, hasLength(2));
      expect(result.warnings, isEmpty);
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

String _jwt(Map<String, dynamic> payload) {
  final encoded =
      base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return 'header.$encoded.signature';
}
