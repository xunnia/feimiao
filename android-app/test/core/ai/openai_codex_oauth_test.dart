import 'dart:convert';

import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

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
  test('global OAuth service creates its HTTP client lazily', () {
    final previous = io.HttpOverrides.current;
    final tracking = _TrackingHttpOverrides();
    io.HttpOverrides.global = tracking;
    try {
      // The first access constructs the singleton. On Android this happens
      // only after main() has installed the current system proxy override.
      expect(OpenAiCodexOAuth.service, isA<OpenAiCodexOAuthService>());
      expect(tracking.createdClients, 1);
    } finally {
      io.HttpOverrides.global = previous;
    }
  });

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

  test('legacy issuer-only OAuth URL normalizes to the authorize endpoint', () {
    expect(
      OpenAiCodexOAuth.isAuthorizationUrl('https://auth.openai.com'),
      isTrue,
    );
    final url = Uri.parse(
      OpenAiCodexOAuth.buildAuthorizationUrl(
        codeChallenge: 'challenge',
        state: 'state',
        authorizationUrl: 'https://auth.openai.com',
      ),
    );
    expect(url.host, 'auth.openai.com');
    expect(url.path, '/oauth/authorize');
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

  test('GPT model catalog keeps region errors in the diagnostic message',
      () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': 'unsupported_country_region',
            'message': 'country, region, or territory is not supported',
          }),
          403,
        ));

    await expectLater(
      OpenAiCodexOAuthService(client: client).fetchModels(
        const OpenAiCodexOAuthTokens(
          accessToken: 'access-token',
          accountId: 'acct-region',
        ),
      ),
      throwsA(
        isA<OpenAiCodexOAuthException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              allOf(
                contains('unsupported_country_region'),
                contains('country, region'),
              ),
            ),
      ),
    );
  });

  test('GPT model catalog derives account id from the JWT when omitted',
      () async {
    final client = MockClient((request) async {
      expect(request.headers['chatgpt-account-id'], 'acct-from-jwt');
      return http.Response(
        jsonEncode({
          'models': [
            {'slug': 'gpt-from-jwt'},
          ],
        }),
        200,
      );
    });
    final models = await OpenAiCodexOAuthService(client: client).fetchModels(
      OpenAiCodexOAuthTokens(
        accessToken: _jwtPayload({
          'https://api.openai.com/auth': {
            'chatgpt_account_id': 'acct-from-jwt',
          },
        }),
        idToken: _jwtPayload({}),
      ),
    );
    expect(models.single.slug, 'gpt-from-jwt');
  });

  test(
      'GPT model catalog hydrates personal access token identity before request',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        expect(
          request.url.toString(),
          OpenAiCodexOAuth.personalAccessTokenWhoAmIEndpoint,
        );
        expect(request.headers['authorization'], 'Bearer at-personal-token');
        return http.Response(
          jsonEncode({
            'email': 'pat@example.com',
            'chatgpt_user_id': 'user-pat',
            'chatgpt_account_id': 'acct-pat',
            'chatgpt_plan_type': 'pro',
            'chatgpt_account_is_fedramp': false,
          }),
          200,
        );
      }
      expect(request.url.path, '/backend-api/codex/models');
      expect(request.headers['authorization'], 'Bearer at-personal-token');
      expect(request.headers['chatgpt-account-id'], 'acct-pat');
      return http.Response(
        jsonEncode({
          'models': [
            {'slug': 'gpt-pat'},
          ],
        }),
        200,
      );
    });

    final models = await OpenAiCodexOAuthService(client: client).fetchModels(
      const OpenAiCodexOAuthTokens(accessToken: 'at-personal-token'),
    );
    expect(models.single.slug, 'gpt-pat');
    expect(calls, 2);
  });

  test('personal access token identity rejects an invalid token', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        OpenAiCodexOAuth.personalAccessTokenWhoAmIEndpoint,
      );
      return http.Response('{}', 403);
    });

    await expectLater(
      OpenAiCodexOAuthService(client: client).fetchModels(
        const OpenAiCodexOAuthTokens(accessToken: 'at-invalid'),
      ),
      throwsA(
        isA<OpenAiCodexOAuthException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
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

  test('Codex request metadata binds one Responses turn to one session', () {
    final headers = OpenAiCodexOAuth.codexRequestHeaders(
      sessionId: 'session-1',
      stream: true,
    );
    expect(headers['Version'], OpenAiCodexOAuth.defaultClientVersion);
    expect(headers['Session-Id'], 'session-1');
    expect(headers['X-Client-Request-Id'], 'session-1');
    expect(headers['Thread-Id'], 'session-1');
    expect(headers['X-Codex-Window-Id'], 'session-1:0');
    expect(headers['Accept'], 'text/event-stream');

    final body = OpenAiCodexOAuth.prepareCodexResponsesBody(
      const {'model': 'gpt-5.4', 'input': <Object>[]},
      sessionId: 'session-1',
    );
    expect(body['prompt_cache_key'], 'session-1');
    final metadata = body['client_metadata'] as Map<String, dynamic>;
    expect(metadata['x-codex-installation-id'], 'session-1');
    expect(metadata['x-codex-window-id'], 'session-1:0');
    expect(metadata['x-codex-turn-metadata'], contains('session-1'));
  });

  test('local callback server completes PKCE flow and exchanges tokens',
      () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://auth.openai.com/oauth/token');
      return http.Response(
        jsonEncode({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'email': 'callback@example.com',
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
    expect(Uri.parse(session.authorizationUrl).host, 'auth.openai.com');
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
      expect(tokens.email, 'callback@example.com');
    } finally {
      httpClient.close(force: true);
      await service.cancel();
    }
  });

  test('official device authorization avoids localhost and exchanges tokens',
      () async {
    final verifier = OpenAiCodexOAuth.generateVerifier(Random(7));
    final challenge = OpenAiCodexOAuth.codeChallenge(verifier);
    var devicePolls = 0;
    final client = MockClient((request) async {
      if (request.url.toString() == OpenAiCodexOAuth.deviceUserCodeEndpoint) {
        expect(request.method, 'POST');
        expect(request.body, contains(OpenAiCodexOAuth.clientId));
        return http.Response(
          jsonEncode({
            'device_auth_id': 'device-auth-id',
            'user_code': 'ABCD-EFGH',
            'interval': 1,
          }),
          200,
        );
      }
      if (request.url.toString() == OpenAiCodexOAuth.deviceTokenEndpoint) {
        devicePolls++;
        if (devicePolls == 1) return http.Response('{}', 403);
        return http.Response(
          jsonEncode({
            'authorization_code': 'device-authorization-code',
            'code_verifier': verifier,
            'code_challenge': challenge,
          }),
          200,
        );
      }
      expect(request.url.toString(), OpenAiCodexOAuth.tokenEndpoint);
      expect(request.body, contains('device-authorization-code'));
      expect(
        request.body,
        contains(Uri.encodeQueryComponent(
          OpenAiCodexOAuth.deviceExchangeRedirectUri,
        )),
      );
      return http.Response(
        jsonEncode({
          'access_token': 'device-access-token',
          'refresh_token': 'device-refresh-token',
          'chatgpt_account_id': 'device-account-id',
          'expires_in': 3600,
        }),
        200,
      );
    });
    final service = OpenAiCodexOAuthService(client: client);
    final session = await service.startDeviceAuth(providerId: 'provider-1');

    expect(session.userCode, 'ABCD-EFGH');
    expect(session.verificationUrl, OpenAiCodexOAuth.deviceVerificationUrl);
    expect(session.verificationUrl, isNot(contains('localhost')));
    expect(service.pendingProviderId, 'provider-1');
    expect(service.pendingUsesDeviceCode, isTrue);

    final tokens = await session.completion;
    expect(tokens.accessToken, 'device-access-token');
    expect(tokens.refreshToken, 'device-refresh-token');
    expect(tokens.accountId, 'device-account-id');
    expect(devicePolls, 2);
    expect(service.pendingProviderId, isNull);
  });

  test('failed token exchange keeps callback for an in-app retry', () async {
    var tokenCalls = 0;
    final client = MockClient((request) async {
      tokenCalls++;
      // The authorization-code exchange is deliberately a raw OAuth request;
      // Codex runtime identity headers belong to refresh/API calls only.
      expect(request.headers['originator'], isNull);
      expect(request.headers['user-agent'], isNull);
      expect(
        request.headers['content-type'],
        'application/x-www-form-urlencoded',
      );
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

class _TrackingHttpOverrides extends io.HttpOverrides {
  int createdClients = 0;

  @override
  io.HttpClient createHttpClient(io.SecurityContext? context) {
    createdClients++;
    return super.createHttpClient(context);
  }
}
