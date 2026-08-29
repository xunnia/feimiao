import 'dart:convert';

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/openai_codex_oauth.dart';

String _jwtPayload(Map<String, dynamic> payload) {
  final encoded =
      base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return 'header.$encoded.signature';
}

String _oauthState(String authorizationUrl) {
  final outer = Uri.parse(authorizationUrl);
  final nested = outer.queryParameters['authorize_url'];
  final inner = nested == null ? outer : Uri.parse(nested);
  return inner.queryParameters['state']!;
}

void main() {
  test('GPT OAuth authorization URL keeps the official scope and redirect', () {
    final url = Uri.parse(
      OpenAiCodexOAuth.buildAuthorizationUrl(
        codeChallenge: 'challenge',
        state: 'state',
      ),
    );

    expect(url.host, 'auth.openai.com');
    expect(url.path, '/oauth/authorize');
    expect(url.queryParameters['redirect_uri'], OpenAiCodexOAuth.redirectUri);
    expect(
      url.queryParameters['scope'],
      contains('api.connectors.read api.connectors.invoke'),
    );
    expect(url.queryParameters['code_challenge_method'], 'S256');
  });

  test('GPT OAuth hosted URL matches Cockpit desktop login envelope', () {
    final url = Uri.parse(
      OpenAiCodexOAuth.buildAuthorizationUrl(
        codeChallenge: 'challenge',
        state: 'state',
        hosted: true,
        stableId: 'stable-id',
      ),
    );
    expect(url.host, 'chatgpt.com');
    expect(url.path, '/codex/desktop-auth');
    expect(url.queryParameters['codex_streamlined_login'], 'true');
    expect(url.queryParameters['no_universal_links'], '1');
    final inner = Uri.parse(url.queryParameters['authorize_url']!);
    expect(inner.host, 'auth.openai.com');
    expect(inner.queryParameters['codex_streamlined_login'], 'true');
    expect(inner.queryParameters['codex_app_version'],
        OpenAiCodexOAuth.authorizationAppVersion);
    expect(inner.queryParameters['prompt'], 'select_account');
    expect(inner.queryParameters['source_surface_stable_id'], 'stable-id');
    expect(inner.queryParameters['codex_origin_stable_id'], 'stable-id');
    expect(OpenAiCodexOAuth.isAuthorizationUrl(url.toString()), isTrue);
  });

  test('JWT account id supports namespaced, direct and organization claims',
      () {
    expect(
      OpenAiCodexOAuth.accountIdFromIdToken(_jwtPayload({
        'https://api.openai.com/auth': {'chatgpt_account_id': 'acct-ns'},
      })),
      'acct-ns',
    );
    expect(
      OpenAiCodexOAuth.accountIdFromIdToken(
        _jwtPayload({'chatgpt_account_id': 'acct-direct'}),
      ),
      'acct-direct',
    );
    expect(
      OpenAiCodexOAuth.accountIdFromIdToken(
        _jwtPayload({
          'organizations': [
            {'id': 'acct-org'}
          ]
        }),
      ),
      'acct-org',
    );
  });

  test('JWT expiry is converted to milliseconds', () {
    expect(
      OpenAiCodexOAuth.expiresAtFromJwt(_jwtPayload({'exp': 1800000000})),
      1800000000000,
    );
    expect(OpenAiCodexOAuth.expiresAtFromJwt('not-a-jwt'), isNull);
  });

  test('GPT model catalog keeps visible subscription models', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://chatgpt.com/backend-api/codex/models?client_version=0.146.0',
      );
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(request.headers['chatgpt-account-id'], 'acct-1');
      expect(request.headers['originator'], 'codex_vscode');
      expect(request.headers['user-agent'], 'codex_vscode/0.146.0');
      expect(request.headers['openai-beta'], 'responses=v1');
      expect(request.headers['accept'], 'application/json');
      return http.Response(
        jsonEncode({
          'models': [
            {
              'slug': 'gpt-visible',
              'display_name': 'GPT Visible',
              'supported_in_api': false,
              'visibility': 'list',
              'supported_reasoning_levels': [
                {'effort': 'high'},
              ],
            },
            {'slug': 'gpt-hidden', 'visibility': 'hidden'},
          ],
        }),
        200,
      );
    });

    final models = await OpenAiCodexOAuthService(client: client).fetchModels(
      const OpenAiCodexOAuthTokens(
        accessToken: 'access-token',
        accountId: 'acct-1',
      ),
    );

    expect(models.map((model) => model.slug), ['gpt-visible']);
    expect(models.single.reasoningEfforts, ['high']);
  });

  test('GPT model catalog accepts a data array and string reasoning levels',
      () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 'gpt-data',
              'supported_reasoning_levels': ['low', 'high'],
            },
          ],
        }),
        200,
      );
    });

    final models = await OpenAiCodexOAuthService(client: client).fetchModels(
      const OpenAiCodexOAuthTokens(
        accessToken: 'access-token',
        accountId: 'acct-1',
      ),
    );

    expect(models.single.slug, 'gpt-data');
    expect(models.single.reasoningEfforts, ['low', 'high']);
  });

  test('Codex OAuth config emits the required Responses headers', () {
    const config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'access-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-visible',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-1',
    );

    final headers = config.authHeaders();
    expect(headers['Authorization'], 'Bearer access-token');
    expect(headers['ChatGPT-Account-Id'], 'acct-1');
    expect(headers['originator'], 'codex_vscode');
    expect(headers['OpenAI-Beta'], 'responses=v1');
    expect(headers['Accept'], 'text/event-stream');
  });

  test('local callback server completes PKCE flow and exchanges tokens',
      () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://auth.openai.com/oauth/token');
      return http.Response(
        jsonEncode({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'id_token': _jwtPayload({
            'https://api.openai.com/auth': {
              'chatgpt_account_id': 'acct-callback',
            },
          }),
          'expires_in': 3600,
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);
    final session = await service.start();
    expect(await service.resumePending(forceRebind: true), isTrue);
    final authorization = Uri.parse(session.authorizationUrl);
    final callback = Uri.parse(session.redirectUri).replace(
      host: '127.0.0.1',
      queryParameters: {
        'code': 'authorization-code',
        'state': _oauthState(authorization.toString()),
      },
    );

    final httpClient = io.HttpClient();
    try {
      final request = await httpClient.getUrl(callback);
      final response = await request.close();
      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      expect(body, contains('授权成功'));
      expect(body, contains('您可以关闭此窗口并返回应用'));
      expect(body, contains('#6b61c7'));
      final tokens = await session.completion;
      expect(tokens.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
      expect(tokens.accountId, 'acct-callback');
    } finally {
      httpClient.close(force: true);
      await service.cancel();
    }
  });

  test('failed token exchange keeps callback for an in-app retry', () async {
    var tokenCalls = 0;
    final client = MockClient((request) async {
      tokenCalls++;
      // The authorization-code exchange is deliberately a raw OAuth request;
      // Codex runtime identity headers belong to refresh/API calls only.
      expect(request.headers['originator'], isNull);
      expect(request.headers['user-agent'], isNull);
      if (tokenCalls <= 3) {
        return http.Response('temporary gateway failure', 503);
      }
      return http.Response(
        jsonEncode({
          'access_token': 'recovered-access',
          'refresh_token': 'recovered-refresh',
          'chatgpt_account_id': 'acct-recovered',
          'expires_in': 3600,
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);
    final session = await service.start(providerId: 'provider-retry');
    final authorization = Uri.parse(session.authorizationUrl);
    final callback = Uri.parse(session.redirectUri).replace(
      queryParameters: {
        'code': 'authorization-code',
        'state': _oauthState(authorization.toString()),
      },
    );

    try {
      await expectLater(
        service.submitCallbackUrl(callback.toString()),
        throwsA(isA<OpenAiCodexOAuthException>()),
      );

      // The browser has already completed. Recovery must reuse the persisted
      // callback instead of forcing a second authorization page.
      final recovered = await service.waitForPendingCompletion();
      expect(recovered?.accessToken, 'recovered-access');
      expect(recovered?.accountId, 'acct-recovered');
      expect(tokenCalls, 4);
    } finally {
      await service.cancel();
    }
  });

  test('Token response preserves explicit account id and string expiry',
      () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'chatgpt_account_id': 'acct-explicit',
          'expires_in': '3600',
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);
    final session = await service.start();
    final authorization = Uri.parse(session.authorizationUrl);
    final callback = Uri.parse(session.redirectUri).replace(
      queryParameters: {
        'code': 'authorization-code',
        'state': _oauthState(authorization.toString()),
      },
    );
    final tokens = await service.submitCallbackUrl(callback.toString());

    expect(tokens.accountId, 'acct-explicit');
    expect(tokens.expiresAtMs, isNotNull);
    expect(tokens.refreshToken, 'refresh-token');
    await service.cancel();
  });

  test('an old token exchange cannot stop or erase a replacement flow',
      () async {
    final releaseOldExchange = Completer<void>();
    final oldExchangeStarted = Completer<void>();
    var tokenCalls = 0;
    final client = MockClient((request) async {
      tokenCalls++;
      if (tokenCalls == 1) {
        oldExchangeStarted.complete();
        await releaseOldExchange.future;
        return http.Response(
          jsonEncode({'access_token': 'old-access'}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'access_token': 'new-access',
          'chatgpt_account_id': 'acct-new',
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);

    Future<void> sendCallback(OpenAiCodexOAuthSession session) async {
      final authorization = Uri.parse(session.authorizationUrl);
      final callback = Uri.parse(session.redirectUri).replace(
        host: '127.0.0.1',
        queryParameters: {
          'code': 'authorization-code',
          'state': _oauthState(authorization.toString()),
        },
      );
      final httpClient = io.HttpClient();
      try {
        final request = await httpClient.getUrl(callback);
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        httpClient.close(force: true);
      }
    }

    final oldSession = await service.start(providerId: 'old-provider');
    final oldCompletion = oldSession.completion;
    final oldFailure = expectLater(
      oldCompletion,
      throwsA(isA<OpenAiCodexOAuthException>()),
    );
    await sendCallback(oldSession);
    await oldExchangeStarted.future;

    // Replacing the flow while A is still waiting on the token endpoint is
    // the Android failure path that used to close B's localhost listener.
    final newSession = await service.start(providerId: 'new-provider');
    expect(service.pendingProviderId, 'new-provider');
    releaseOldExchange.complete();
    await oldFailure;
    expect(service.pendingProviderId, 'new-provider');

    await sendCallback(newSession);
    final newTokens = await newSession.completion;
    expect(newTokens.accessToken, 'new-access');
    expect(newTokens.accountId, 'acct-new');
    await service.cancel();
  });

  test('Expired GPT OAuth config refreshes once and persists rotated tokens',
      () async {
    var refreshCalls = 0;
    final client = MockClient((request) async {
      refreshCalls++;
      expect(request.url.toString(), 'https://auth.openai.com/oauth/token');
      expect(request.body, contains('"grant_type":"refresh_token"'));
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['originator'],
          OpenAiCodexOAuth.authorizationOriginator);
      return http.Response(
        jsonEncode({
          'access_token': 'refreshed-access',
          'refresh_token': 'rotated-refresh',
          'chatgpt_account_id': 'acct-refresh',
          'expires_in': 3600,
        }),
        200,
      );
    });
    var savedAccount = '';
    final service = OpenAiCodexOAuthService(client: client);
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'expired-access',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-old',
      oauthRefreshToken: 'old-refresh',
      oauthExpiresAtMs: DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
      oauthTokenSaver: (access, refresh, expiresAt, accountId) async {
        expect(access, 'refreshed-access');
        expect(refresh, 'rotated-refresh');
        expect(expiresAt, isNotNull);
        savedAccount = accountId ?? '';
      },
    );

    final refreshed = await service.ensureFreshConfig(config);
    expect(refreshCalls, 1);
    expect(refreshed.apiKey, 'refreshed-access');
    expect(refreshed.oauthRefreshToken, 'rotated-refresh');
    expect(refreshed.oauthAccountId, 'acct-refresh');
    expect(savedAccount, 'acct-refresh');
  });

  test('Refresh-only GPT OAuth config exchanges before its first request',
      () async {
    var refreshCalls = 0;
    final client = MockClient((request) async {
      refreshCalls++;
      expect(request.url.toString(), 'https://auth.openai.com/oauth/token');
      return http.Response(
        jsonEncode({
          'access_token': 'first-access',
          'refresh_token': 'first-refresh',
          'chatgpt_account_id': 'acct-refresh-only',
          'expires_in': 3600,
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: '',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-refresh-only',
      oauthRefreshToken: 'refresh-only-token',
    );

    final refreshed = await service.ensureFreshConfig(config);

    expect(refreshCalls, 1);
    expect(refreshed.apiKey, 'first-access');
    expect(refreshed.oauthRefreshToken, 'first-refresh');
    expect(refreshed.oauthAccountId, 'acct-refresh-only');
  });
}
