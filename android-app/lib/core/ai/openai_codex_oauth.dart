import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../security/secure_key_store.dart';
import 'ai_provider_config.dart';

/// OpenAI's ChatGPT/Codex OAuth is separate from an OpenAI Platform API key.
/// Keep the protocol details in one place so API-key providers remain generic.
class OpenAiCodexOAuth {
  OpenAiCodexOAuth._();

  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const authorizationEndpoint =
      'https://auth.openai.com/oauth/authorize';
  static const tokenEndpoint = 'https://auth.openai.com/oauth/token';
  static const codexBaseUrl = 'https://chatgpt.com/backend-api';
  static const codexModelsPath = '/codex/models';
  static const codexResponsesPath = '/codex/responses';
  static const redirectUri = 'http://localhost:1455/auth/callback';
  static const fallbackRedirectUri = 'http://localhost:1457/auth/callback';
  // Keep this in sync with the scope set used by the official Codex login
  // helper. The connector scopes are part of the current ChatGPT consent
  // contract even when this app does not expose connectors yet.
  static const scopes =
      'openid profile email offline_access api.connectors.read api.connectors.invoke';
  static const originator = 'codex_vscode';
  static const userAgent = 'codex_vscode/0.146.0';
  static const defaultClientVersion = '0.146.0';

  static final OpenAiCodexOAuthService service = OpenAiCodexOAuthService();

  static Future<AiProviderConfig> ensureFreshConfig(
    AiProviderConfig config,
  ) =>
      service.ensureFreshConfig(config);

  static bool isAuthorizationUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri?.scheme == 'https' && uri?.host == 'auth.openai.com';
  }

  static Uri modelsUri({String clientVersion = defaultClientVersion}) {
    return Uri.parse('$codexBaseUrl$codexModelsPath').replace(
      queryParameters: {'client_version': clientVersion},
    );
  }

  static Uri responsesUri() => Uri.parse('$codexBaseUrl$codexResponsesPath');

  static String redirectUriForPort(int port) =>
      'http://localhost:$port/auth/callback';

  static String buildAuthorizationUrl({
    required String codeChallenge,
    required String state,
    String redirect = redirectUri,
    String authorizationUrl = authorizationEndpoint,
  }) {
    final base =
        Uri.tryParse(authorizationUrl) ?? Uri.parse(authorizationEndpoint);
    final query = <String, String>{
      ...base.queryParameters,
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirect,
      'scope': scopes,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'id_token_add_organizations': 'true',
      'codex_cli_simplified_flow': 'true',
      'state': state,
      'originator': originator,
    };
    return base.replace(queryParameters: query).toString();
  }

  static String generateVerifier([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => source.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String? accountIdFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map) return null;
      final auth = decoded['https://api.openai.com/auth'];
      if (auth is Map) {
        final id = auth['chatgpt_account_id'] ?? auth['account_id'];
        if (id is String && id.trim().isNotEmpty) return id.trim();
      }
      final direct = decoded['chatgpt_account_id'] ?? decoded['account_id'];
      if (direct is String && direct.trim().isNotEmpty) return direct.trim();

      // A few token issuers only expose the workspace through the first
      // organization claim. This mirrors the fallback used by Codex clients.
      final organizations = decoded['organizations'];
      if (organizations is List) {
        for (final organization in organizations) {
          if (organization is Map) {
            final id = organization['id'] ?? organization['organization_id'];
            if (id is String && id.trim().isNotEmpty) return id.trim();
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads a JWT `exp` claim without validating the signature. Signature
  /// validation remains the server's responsibility; this value is only used
  /// to decide when a stored refresh token should be used.
  static int? expiresAtFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final exp = payload['exp'];
      if (exp is num && exp > 0) return exp.toInt() * 1000;
      final seconds = int.tryParse(exp?.toString() ?? '');
      return seconds == null || seconds <= 0 ? null : seconds * 1000;
    } catch (_) {
      return null;
    }
  }
}

class OpenAiCodexOAuthException implements Exception {
  final String message;
  final int? statusCode;

  const OpenAiCodexOAuthException(this.message, {this.statusCode});

  @override
  String toString() => 'OpenAiCodexOAuthException: $message';
}

/// Android-only process keep-alive used while the external browser follows
/// the localhost OAuth redirect.  MissingPluginException is expected on
/// desktop/test runners, where the Dart HttpServer itself is sufficient.
class OpenAiCodexOAuthKeepAlive {
  OpenAiCodexOAuthKeepAlive._();

  static const MethodChannel _channel = MethodChannel('feimiao/oauth');

  static Future<int?> start({
    List<int> ports = const [1455, 1457],
    String? flowId,
  }) async {
    try {
      return await _channel.invokeMethod<int>(
        'startKeepAlive',
        <String, dynamic>{
          'ports': ports,
          if (flowId != null && flowId.trim().isNotEmpty) 'flowId': flowId,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    }
  }

  static Future<bool> stop({String? flowId}) async {
    try {
      return await _channel.invokeMethod<bool>(
            'stopKeepAlive',
            <String, dynamic>{
              if (flowId != null && flowId.trim().isNotEmpty) 'flowId': flowId,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on FlutterError {
      return false;
    }
  }

  static Future<String?> takeCallback({String? flowId}) async {
    try {
      return await _channel.invokeMethod<String>(
        'takeCallback',
        <String, dynamic>{
          if (flowId != null && flowId.trim().isNotEmpty) 'flowId': flowId,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    }
  }

  static Future<bool> clearCallback() async {
    try {
      return await _channel.invokeMethod<bool>('clearCallback') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on FlutterError {
      return false;
    }
  }
}

class OpenAiCodexOAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final String idToken;
  final String? accountId;
  final int? expiresAtMs;

  const OpenAiCodexOAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken = '',
    this.accountId,
    this.expiresAtMs,
  });

  bool get hasRefreshToken => refreshToken?.trim().isNotEmpty ?? false;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'accountId': accountId,
        'expiresAtMs': expiresAtMs,
      };
}

class OpenAiCodexModel {
  final String slug;
  final String displayName;
  final bool supportedInApi;
  final String visibility;
  final List<String> reasoningEfforts;

  const OpenAiCodexModel({
    required this.slug,
    this.displayName = '',
    this.supportedInApi = true,
    this.visibility = 'list',
    this.reasoningEfforts = const [],
  });

  factory OpenAiCodexModel.fromJson(Map<String, dynamic> json) {
    final levels = json['supported_reasoning_levels'];
    final efforts = levels is List
        ? levels
            .map((item) => item is Map
                ? item['effort']?.toString().trim() ?? ''
                : item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return OpenAiCodexModel(
      slug: (json['slug'] ?? json['id'] ?? '').toString().trim(),
      displayName:
          (json['display_name'] ?? json['name'] ?? '').toString().trim(),
      supportedInApi: json['supported_in_api'] != false,
      visibility:
          (json['visibility'] ?? 'list').toString().trim().toLowerCase(),
      reasoningEfforts: efforts,
    );
  }
}

class OpenAiCodexOAuthSession {
  final String authorizationUrl;
  final String redirectUri;
  final Future<OpenAiCodexOAuthTokens> completion;

  const OpenAiCodexOAuthSession({
    required this.authorizationUrl,
    required this.redirectUri,
    required this.completion,
  });
}

class OpenAiCodexOAuthService {
  static const _pendingKey = 'ai_codex_oauth_pending_v1';
  static const _callbackPort = 1455;
  static const _fallbackCallbackPort = 1457;

  final http.Client _client;
  // Keep one listener per loopback family. Browsers are free to resolve
  // `localhost` to either 127.0.0.1 or ::1, while Android devices differ in
  // whether an IPv6 socket accepts IPv4-mapped connections.
  final List<HttpServer> _servers = [];
  _PendingOAuthState? _pending;
  Completer<Uri>? _callback;
  Future<OpenAiCodexOAuthTokens>? _completion;
  int? _nativeCallbackPort;
  final Map<String, Future<AiProviderConfig>> _refreshInFlight = {};

  // OAuth has two independent asynchronous owners: the settings page and
  // the app-level lifecycle watcher. An older flow must never stop the
  // listener that belongs to a newer flow. Generations identify ownership;
  // the operation tails serialize Dart cleanup and native start/stop calls.
  int _flowGeneration = 0;
  Future<void> _flowOperationTail = Future<void>.value();
  Future<void> _nativeOperationTail = Future<void>.value();

  Future<T> _exclusiveFlow<T>(Future<T> Function() action) {
    final previous = _flowOperationTail;
    final gate = Completer<void>();
    _flowOperationTail = gate.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    }();
  }

  Future<T> _exclusiveNative<T>(Future<T> Function() action) {
    final previous = _nativeOperationTail;
    final gate = Completer<void>();
    _nativeOperationTail = gate.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    }();
  }

  /// The provider id is persisted together with the PKCE state so an Android
  /// activity recreation can finish the same account login without relying on
  /// the settings page state that launched the browser.
  String? get pendingProviderId => _pending?.providerId;

  OpenAiCodexOAuthService({http.Client? client})
      : _client = client ?? http.Client();

  Future<OpenAiCodexOAuthSession> start({
    String? authorizationUrl,
    String? providerId,
  }) =>
      _exclusiveFlow(
        () => _start(
          authorizationUrl: authorizationUrl,
          providerId: providerId,
        ),
      );

  Future<OpenAiCodexOAuthSession> _start({
    String? authorizationUrl,
    String? providerId,
  }) async {
    await _cancelInternal();
    final generation = _flowGeneration;
    final verifier = OpenAiCodexOAuth.generateVerifier();
    final state = OpenAiCodexOAuth.generateVerifier();
    final challenge = OpenAiCodexOAuth.codeChallenge(verifier);
    _nativeCallbackPort = null;
    late final List<HttpServer> servers;
    // On Android the callback is owned by the isolated native foreground
    // service. This keeps localhost:1455 alive even if FlutterActivity and
    // the Dart isolate are reclaimed while Chrome is authorizing. Desktop and
    // test runners retain the original Dart listener.
    final nativePort = Platform.isAndroid
        ? await _startNative(
            generation: generation,
            flowId: state,
            ports: const [_callbackPort, _fallbackCallbackPort],
          )
        : null;
    if (generation != _flowGeneration) {
      throw const OpenAiCodexOAuthException('OAuth 授权已被新的授权流程替换');
    }
    if (nativePort != null) {
      _nativeCallbackPort = nativePort;
      servers = const <HttpServer>[];
    } else {
      try {
        servers = await _bindCallbackServers();
      } on SocketException catch (error) {
        throw OpenAiCodexOAuthException(
          '无法监听 OAuth 回调端口 $_callbackPort/$_fallbackCallbackPort，请关闭旧授权页面后重试：${error.message}',
        );
      }
      _servers.addAll(servers);
    }
    final redirectPort = nativePort ?? servers.first.port;
    final redirectUri = OpenAiCodexOAuth.redirectUriForPort(redirectPort);
    final authUrl = OpenAiCodexOAuth.buildAuthorizationUrl(
      codeChallenge: challenge,
      state: state,
      redirect: redirectUri,
      authorizationUrl:
          authorizationUrl ?? OpenAiCodexOAuth.authorizationEndpoint,
    );
    final pending = _PendingOAuthState(
      providerId: providerId ?? '',
      codeVerifier: verifier,
      state: state,
      authorizationUrl: authUrl,
      redirectUri: redirectUri,
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );
    _pending = pending;
    try {
      await _persistPending(pending);
    } catch (error) {
      await _stopServer();
      await _stopNativeIfCurrent(generation, flowId: state);
      _pending = null;
      throw OpenAiCodexOAuthException('无法保存 OAuth 授权状态：$error');
    }
    _callback = Completer<Uri>();
    _completion = _completePending(pending, generation);
    for (final server in servers) {
      unawaited(_serveCallbacks(server));
    }
    return OpenAiCodexOAuthSession(
      authorizationUrl: authUrl,
      redirectUri: pending.redirectUri,
      completion: _completion!,
    );
  }

  /// Recreate the callback listener after Android recreates or suspends the
  /// activity while the external browser is handling authorization. The
  /// persisted redirect URI is authoritative: a resumed flow must listen on
  /// the same registered port so the already-issued callback remains valid.
  ///
  /// [forceRebind] is retained for callers compiled against the earlier API.
  /// It no longer tears down a healthy listener; every resume is health
  /// checked first so Chrome never sees an avoidable refusal window.
  Future<bool> resumePending({bool forceRebind = false}) =>
      _exclusiveFlow(() => _resumePending(forceRebind: forceRebind));

  Future<bool> _resumePending({bool forceRebind = false}) async {
    await _loadPendingIfNeeded();
    final generation = _flowGeneration;
    final pending = _pending;
    if (pending == null) {
      await _stopNativeIfCurrent(generation);
      return false;
    }
    if (pending.expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
      await _cancelInternal();
      return false;
    }
    final pendingPort = Uri.tryParse(pending.redirectUri)?.port;
    if (Platform.isAndroid && pendingPort != null && pendingPort > 0) {
      final nativePort = await _startNative(
        generation: generation,
        ports: <int>[pendingPort, _fallbackCallbackPort],
        flowId: pending.state,
      );
      if (generation != _flowGeneration) return false;
      if (nativePort == pendingPort) {
        _nativeCallbackPort = nativePort;
        _ensurePendingCompletion(pending, generation);
        return true;
      }
      if (nativePort != null) {
        await _stopNativeIfCurrent(generation, flowId: pending.state);
      }
    }
    if (_servers.isNotEmpty) {
      // Do not tear down a healthy listener merely because the Activity was
      // resumed.  That creates a real refusal window exactly when Chrome may
      // deliver the callback.  A process can still retain a stale HttpServer
      // object after Android reclaimed its socket, so verify the loopback
      // endpoint and only rebind when the health probe fails.
      if (await _isCallbackReachable(pending.redirectUri)) {
        _ensurePendingCompletion(pending, generation);
        return true;
      }
      await _stopServer();
    }
    if (_servers.isNotEmpty) {
      _ensurePendingCompletion(pending, generation);
      return true;
    }

    final port = pendingPort;
    if (port == null || port <= 0) return false;
    List<HttpServer>? servers;
    for (var attempt = 0; attempt < 3 && servers == null; attempt++) {
      try {
        servers = await _bindCallbackServers(
          preferredPort: port,
          allowFallback: false,
        );
      } on SocketException {
        if (attempt < 2) {
          // Android may release a backgrounded socket a few milliseconds
          // after close(). Retry the same registered port before falling back
          // to the manual paste path.
          await Future<void>.delayed(
            Duration(milliseconds: 80 * (attempt + 1)),
          );
        }
      }
    }
    if (servers == null) {
      // The manual callback paste path remains available when another
      // process owns the port or the OS has not released it yet.
      return false;
    }
    if (generation != _flowGeneration) return false;
    _servers.addAll(servers);
    _callback ??= Completer<Uri>();
    _ensurePendingCompletion(pending, generation);
    for (final server in servers) {
      unawaited(_serveCallbacks(server));
    }
    return true;
  }

  /// Returns the pending completion future after making sure the callback
  /// listener exists.  This is used by the app-level lifecycle watcher when
  /// Android recreates the settings route while the browser is open.
  Future<OpenAiCodexOAuthTokens?> waitForPendingCompletion() async {
    await _loadPendingIfNeeded();
    final pending = _pending;
    if (pending == null) return null;
    if (!await resumePending()) return null;
    final completion = _completion;
    if (completion == null) return null;
    return completion;
  }

  Future<OpenAiCodexOAuthTokens> submitCallbackUrl(String rawUrl) async {
    await _loadPendingIfNeeded();
    final pending = _pending;
    if (pending == null) {
      throw const OpenAiCodexOAuthException('没有正在进行的 OAuth 授权，请重新开始');
    }
    final uri = _parseCallbackUrl(rawUrl, pending.redirectUri);
    _validateCallback(uri, pending);
    final callback = _callback;
    if (callback != null && !callback.isCompleted) {
      callback.complete(uri);
      return _completion!;
    }
    return _exchangeCallback(
      uri,
      pending,
      generation: _flowGeneration,
    );
  }

  Future<void> cancel() => _exclusiveFlow(_cancelInternal);

  Future<void> _cancelInternal() async {
    // Invalidate every continuation from the old flow before touching any
    // shared field or native resource. start() calls this method while it
    // owns the flow mutex, so a replacement cannot begin until cleanup ends.
    final generation = ++_flowGeneration;
    final canceledFlowId = _pending?.state;
    final callback = _callback;
    if (callback != null && !callback.isCompleted) {
      callback.completeError(
        const OpenAiCodexOAuthException('OAuth 授权已取消'),
      );
    }
    _callback = null;
    _completion = null;
    _pending = null;
    _nativeCallbackPort = null;
    await _stopServer();
    await SecureKeyStore.delete(_pendingKey);
    await _stopNativeIfCurrent(generation, flowId: canceledFlowId);
    // A callback captured by an abandoned flow must never be consumed by the
    // next authorization attempt. Pending-flow recovery does not call cancel,
    // so a still-valid callback remains available across Activity recreation.
    await _clearNativeCallback();
  }

  Future<List<OpenAiCodexModel>> fetchModels(
    OpenAiCodexOAuthTokens tokens, {
    String clientVersion = OpenAiCodexOAuth.defaultClientVersion,
  }) async {
    if (tokens.accessToken.trim().isEmpty) {
      throw const OpenAiCodexOAuthException('GPT OAuth access token 为空');
    }
    if (tokens.accountId?.trim().isEmpty ?? true) {
      throw const OpenAiCodexOAuthException(
        'GPT OAuth Token 未包含 ChatGPT 账号 ID，请重新授权',
      );
    }
    final headers = _codexHeaders(
      accessToken: tokens.accessToken,
      accountId: tokens.accountId,
    )..addAll({'Accept': 'application/json'});
    final uri = OpenAiCodexOAuth.modelsUri(clientVersion: clientVersion);
    late http.Response response;
    Object? lastNetworkError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 45));
        lastNetworkError = null;
        break;
      } on TimeoutException catch (error) {
        lastNetworkError = error;
      } on SocketException catch (error) {
        lastNetworkError = error;
      } on http.ClientException catch (error) {
        lastNetworkError = error;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    if (lastNetworkError != null) {
      throw OpenAiCodexOAuthException(
        '获取 GPT 模型失败：$lastNetworkError',
      );
    }
    if (response.statusCode != 200) {
      throw OpenAiCodexOAuthException(
        '获取 GPT 模型失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Object?;
    final raw =
        decoded is Map ? (decoded['models'] ?? decoded['data']) : decoded;
    if (raw is! List) {
      throw const OpenAiCodexOAuthException('GPT 模型响应格式错误');
    }
    final models = raw
        .map((item) => item is Map
            ? OpenAiCodexModel.fromJson(Map<String, dynamic>.from(item))
            : OpenAiCodexModel(slug: item?.toString().trim() ?? ''))
        // `supported_in_api` describes the public api.openai.com catalog. The
        // authenticated Codex catalog is intentionally broader for ChatGPT
        // subscription accounts, so only hide entries the backend marks as
        // hidden/none.
        .where((model) =>
            model.slug.isNotEmpty &&
            model.visibility != 'hide' &&
            model.visibility != 'hidden' &&
            model.visibility != 'none')
        .toList(growable: false);
    if (models.isEmpty) {
      throw const OpenAiCodexOAuthException('当前 GPT 账号没有可用模型');
    }
    return models;
  }

  Future<AiProviderConfig> ensureFreshConfig(AiProviderConfig config) async {
    if (!config.isOpenAiCodexOAuth || config.oauthRefreshToken.trim().isEmpty) {
      return config;
    }
    final hasAccessToken = config.apiKey.trim().isNotEmpty;
    final expiresAtMs = config.oauthExpiresAtMs ??
        OpenAiCodexOAuth.expiresAtFromJwt(config.apiKey);
    // Cockpit exports may contain only a refresh token.  An absent access
    // token is not an "unknown expiry" case: it must be exchanged before the
    // first request, otherwise callers proceed with an empty Bearer token.
    // When an access token exists but has no decodable expiry, retain the
    // historical behaviour and let the upstream validate it on request.
    if (hasAccessToken &&
        (expiresAtMs == null ||
            expiresAtMs >
                DateTime.now()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch)) {
      return config;
    }
    // Several app surfaces can begin a request at the same time (for example
    // Chats and a report refresh). Share one refresh call per account so a
    // rotating refresh token is never redeemed twice concurrently.
    final key = (config.providerId?.trim().isNotEmpty ?? false)
        ? config.providerId!.trim()
        : config.oauthAccountId.trim().isNotEmpty
            ? config.oauthAccountId.trim()
            : config.oauthRefreshToken.trim();
    return _refreshConfigShared(
      config,
      key: key,
      fallbackExpiresAtMs: expiresAtMs ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  }

  /// Force one refresh after the upstream rejects an otherwise apparently
  /// valid access token. ChatGPT rotates access tokens independently of the
  /// expiry metadata, so a 401 must be recoverable without making the user
  /// authorize again. Concurrent callers share the same refresh request.
  Future<AiProviderConfig> refreshAfterUnauthorized(
    AiProviderConfig config,
  ) async {
    if (!config.isOpenAiCodexOAuth || config.oauthRefreshToken.trim().isEmpty) {
      return config;
    }
    final key = (config.providerId?.trim().isNotEmpty ?? false)
        ? config.providerId!.trim()
        : config.oauthAccountId.trim().isNotEmpty
            ? config.oauthAccountId.trim()
            : config.oauthRefreshToken.trim();
    return _refreshConfigShared(
      config,
      key: key,
      fallbackExpiresAtMs:
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  }

  Future<AiProviderConfig> _refreshConfigShared(
    AiProviderConfig config, {
    required String key,
    required int fallbackExpiresAtMs,
  }) async {
    final existing = _refreshInFlight[key];
    if (existing != null) return existing;
    final future = _refreshConfig(
      config,
      refreshExpiresAtMs: fallbackExpiresAtMs,
    );
    _refreshInFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight[key], future)) {
        _refreshInFlight.remove(key);
      }
    }
  }

  Future<AiProviderConfig> _refreshConfig(
    AiProviderConfig config, {
    required int refreshExpiresAtMs,
  }) async {
    final tokens = await _refreshToken(
      refreshToken: config.oauthRefreshToken,
      previousAccountId: config.oauthAccountId,
    );
    final refreshed = config.copyWith(
      apiKey: tokens.accessToken,
      oauthRefreshToken: tokens.refreshToken ?? config.oauthRefreshToken,
      oauthAccountId: tokens.accountId ?? config.oauthAccountId,
      oauthExpiresAtMs: tokens.expiresAtMs ?? refreshExpiresAtMs,
    );
    await config.oauthTokenSaver?.call(
      refreshed.apiKey,
      refreshed.oauthRefreshToken,
      refreshed.oauthExpiresAtMs,
      refreshed.oauthAccountId,
    );
    return refreshed;
  }

  Future<OpenAiCodexOAuthTokens> _completePending(
    _PendingOAuthState pending,
    int generation,
  ) async {
    try {
      if (!_ownsFlow(pending, generation)) {
        throw const OpenAiCodexOAuthException('OAuth 授权已被新的授权流程替换');
      }
      final uri = await _waitForCallback(pending);
      if (!_ownsFlow(pending, generation)) {
        throw const OpenAiCodexOAuthException('OAuth 授权已被新的授权流程替换');
      }
      _validateCallback(uri, pending);
      return await _exchangeCallback(
        uri,
        pending,
        generation: generation,
      );
    } finally {
      // A stale completion is deliberately not allowed to clean up shared
      // listeners. The replacement flow owns those resources now.
      await _cleanupPendingIfCurrent(pending, generation);
    }
  }

  void _ensurePendingCompletion(
    _PendingOAuthState pending,
    int generation,
  ) {
    _callback ??= Completer<Uri>();
    _completion ??= _completePending(pending, generation);
  }

  Future<Uri> _waitForCallback(_PendingOAuthState pending) {
    final callback = _callback!.future;
    if (_nativeCallbackPort == null) return callback;
    // The native service is in a separate process, so it cannot invoke the
    // Flutter MethodChannel directly. Poll its atomic callback hand-off while
    // also keeping the manual paste completer as an immediate fallback.
    return Future.any<Uri>([
      callback,
      _pollNativeCallback(pending),
    ]);
  }

  Future<Uri> _pollNativeCallback(_PendingOAuthState pending) async {
    while (DateTime.now().millisecondsSinceEpoch < pending.expiresAtMs) {
      final raw = await OpenAiCodexOAuthKeepAlive.takeCallback(
        flowId: pending.state,
      );
      if (raw != null && raw.trim().isNotEmpty) {
        final uri = Uri.tryParse(raw.trim());
        if (uri != null) return uri;
        throw const OpenAiCodexOAuthException('OAuth 原生回调地址格式错误');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const OpenAiCodexOAuthException('OAuth 授权已超时，请重新开始');
  }

  Future<OpenAiCodexOAuthTokens> _exchangeCallback(
      Uri uri, _PendingOAuthState pending,
      {required int generation}) async {
    final code = uri.queryParameters['code']?.trim() ?? '';
    final tokens = await _exchangeCode(
      code: code,
      verifier: pending.codeVerifier,
      redirectUri: pending.redirectUri,
    );
    if (!_ownsFlow(pending, generation)) {
      throw const OpenAiCodexOAuthException('OAuth 授权已被新的授权流程替换');
    }
    // Stop only after the token exchange belongs to the current flow. A
    // previous exchange may finish after the user has already started a new
    // login; stopping in that stale continuation used to kill the new 1455
    // listener and produce ERR_CONNECTION_REFUSED in Chrome.
    // Chrome may issue a follow-up request (for example favicon or a retry of
    // the redirect) immediately after the callback response. Keep the native
    // listener alive briefly so the success page never turns into
    // `localhost:1455 ERR_CONNECTION_REFUSED` while the token exchange is
    // finishing.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _stopNativeIfCurrent(generation, flowId: pending.state);
    if (!_ownsFlow(pending, generation)) {
      throw const OpenAiCodexOAuthException('OAuth 授权已被新的授权流程替换');
    }
    _pending = null;
    _callback = null;
    _completion = null;
    _nativeCallbackPort = null;
    await SecureKeyStore.delete(_pendingKey);
    return tokens;
  }

  Future<OpenAiCodexOAuthTokens> _exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await _client.post(
      Uri.parse(OpenAiCodexOAuth.tokenEndpoint),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': OpenAiCodexOAuth.userAgent,
        'originator': OpenAiCodexOAuth.originator,
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': OpenAiCodexOAuth.clientId,
        'code_verifier': verifier,
      },
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiCodexOAuthException(
        'GPT 授权换取 Token 失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    return _decodeTokens(response.body);
  }

  Future<OpenAiCodexOAuthTokens> _refreshToken({
    required String refreshToken,
    String? previousAccountId,
  }) async {
    final response = await _client.post(
      Uri.parse(OpenAiCodexOAuth.tokenEndpoint),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': OpenAiCodexOAuth.userAgent,
        'originator': OpenAiCodexOAuth.originator,
      },
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': OpenAiCodexOAuth.clientId,
      },
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiCodexOAuthException(
        'GPT Token 刷新失败（${response.statusCode}），请重新授权',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeTokens(response.body);
    return OpenAiCodexOAuthTokens(
      accessToken: decoded.accessToken,
      refreshToken: decoded.refreshToken ?? refreshToken,
      idToken: decoded.idToken,
      accountId: decoded.accountId ?? previousAccountId,
      expiresAtMs: decoded.expiresAtMs,
    );
  }

  OpenAiCodexOAuthTokens _decodeTokens(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const OpenAiCodexOAuthException('GPT Token 响应格式错误');
    }
    final accessToken = decoded['access_token']?.toString().trim() ?? '';
    if (accessToken.isEmpty) {
      throw const OpenAiCodexOAuthException('GPT Token 响应缺少 access_token');
    }
    final idToken = decoded['id_token']?.toString().trim() ?? '';
    final expiresIn = decoded['expires_in'];
    final seconds = expiresIn is num
        ? expiresIn.toInt()
        : int.tryParse(expiresIn?.toString() ?? '');
    final explicitAccountId =
        (decoded['chatgpt_account_id'] ?? decoded['account_id'])
            ?.toString()
            .trim();
    final accountId = explicitAccountId != null && explicitAccountId.isNotEmpty
        ? explicitAccountId
        : idToken.isEmpty
            ? OpenAiCodexOAuth.accountIdFromIdToken(accessToken)
            : OpenAiCodexOAuth.accountIdFromIdToken(idToken) ??
                OpenAiCodexOAuth.accountIdFromIdToken(accessToken);
    final expiresAtMs = seconds == null
        ? OpenAiCodexOAuth.expiresAtFromJwt(accessToken) ??
            OpenAiCodexOAuth.expiresAtFromJwt(idToken)
        : DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
    return OpenAiCodexOAuthTokens(
      accessToken: accessToken,
      refreshToken: decoded['refresh_token']?.toString().trim(),
      idToken: idToken,
      accountId: accountId,
      expiresAtMs: expiresAtMs,
    );
  }

  Future<void> _serveCallbacks(HttpServer server) async {
    try {
      await for (final request in server) {
        if (request.uri.path != '/auth/callback') {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found');
          await request.response.close();
          continue;
        }
        try {
          final pending = _pending;
          if (pending == null) throw const OpenAiCodexOAuthException('授权状态已失效');
          _validateCallback(request.uri, pending);
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType =
                ContentType('text', 'html', charset: 'utf-8')
            ..write(_successHtml());
          await request.response.close();
          if (_callback != null && !_callback!.isCompleted) {
            _callback!.complete(request.uri);
          }
        } catch (error) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType =
                ContentType('text', 'html', charset: 'utf-8')
            ..write(_errorHtml(error.toString()));
          await request.response.close();
          // A user cancellation or malformed callback with the correct state
          // must wake the waiting UI. Do not fail the pending flow for an
          // unrelated request carrying a forged state value.
          final pending = _pending;
          final callbackState = request.uri.queryParameters['state']?.trim();
          if (pending != null && callbackState == pending.state) {
            final callback = _callback;
            if (callback != null && !callback.isCompleted) {
              callback.completeError(error);
            }
          }
        }
      }
    } on SocketException {
      // The listener is deliberately short-lived and may be closed by cancel.
    } finally {
      _servers.remove(server);
    }
  }

  void _validateCallback(Uri uri, _PendingOAuthState pending) {
    final expected = Uri.tryParse(pending.redirectUri);
    if (expected == null) {
      throw const OpenAiCodexOAuthException('OAuth 回调地址配置错误');
    }
    _validateCallbackHostAndPort(uri, expected);
    final callbackState = uri.queryParameters['state']?.trim() ?? '';
    if (callbackState != pending.state) {
      throw const OpenAiCodexOAuthException('OAuth state 校验失败，请重新授权');
    }
    final error = uri.queryParameters['error']?.trim();
    if (error != null && error.isNotEmpty) {
      throw OpenAiCodexOAuthException(
        'GPT 授权失败：${uri.queryParameters['error_description'] ?? error}',
      );
    }
    if ((uri.queryParameters['code']?.trim() ?? '').isEmpty) {
      throw const OpenAiCodexOAuthException('OAuth 回调缺少授权码');
    }
  }

  Uri _parseCallbackUrl(String raw, String redirect) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const OpenAiCodexOAuthException('回调地址不能为空');
    }
    final base = Uri.tryParse(redirect);
    if (base == null) {
      throw const OpenAiCodexOAuthException('OAuth 回调地址配置错误');
    }
    Uri? uri = Uri.tryParse(value);
    if (value.startsWith('localhost:') || value.startsWith('127.0.0.1:')) {
      uri = Uri.tryParse('http://$value');
    }
    if (value.startsWith('/')) {
      // Browser address bars sometimes omit the scheme and host when users
      // copy only `/auth/callback?...`.
      uri = base.replace(
        path: uri?.path.isNotEmpty == true ? uri!.path : '/auth/callback',
        query: uri?.query ?? '',
        fragment: '',
      );
    } else if (uri == null || !uri.hasScheme) {
      // Also accept a raw `code=...&state=...` query string.
      uri = base.replace(
        query: value.replaceFirst(RegExp(r'^\?'), ''),
        fragment: '',
      );
    }
    return uri;
  }

  Map<String, String> _codexHeaders({
    required String accessToken,
    String? accountId,
  }) =>
      {
        'Authorization': 'Bearer $accessToken',
        if (accountId != null && accountId.trim().isNotEmpty)
          'ChatGPT-Account-Id': accountId.trim(),
        'originator': OpenAiCodexOAuth.originator,
        'User-Agent': OpenAiCodexOAuth.userAgent,
        'OpenAI-Beta': 'responses=v1',
      };

  Future<void> _loadPendingIfNeeded() async {
    if (_pending != null) return;
    final raw = await SecureKeyStore.read(_pendingKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final pending = _PendingOAuthState.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (pending.expiresAtMs > DateTime.now().millisecondsSinceEpoch) {
          _pending = pending;
        } else {
          await SecureKeyStore.delete(_pendingKey);
        }
      }
    } catch (_) {
      await SecureKeyStore.delete(_pendingKey);
    }
  }

  Future<void> _persistPending(_PendingOAuthState pending) async {
    await SecureKeyStore.write(_pendingKey, jsonEncode(pending.toJson()));
  }

  bool _ownsFlow(_PendingOAuthState pending, int generation) =>
      generation == _flowGeneration && _pending?.state == pending.state;

  Future<int?> _startNative({
    required int generation,
    required String flowId,
    required List<int> ports,
  }) async {
    return _exclusiveNative(() async {
      if (generation != _flowGeneration) return null;
      final port = await OpenAiCodexOAuthKeepAlive.start(
        ports: ports,
        flowId: flowId,
      );
      // A flow replacement cannot normally happen while the flow mutex is
      // held, but keep this check after the platform await as a second guard
      // for activity recreation and test doubles.
      if (generation != _flowGeneration) return null;
      return port;
    });
  }

  Future<void> _stopNativeIfCurrent(
    int generation, {
    String? flowId,
  }) async {
    await _exclusiveNative(() async {
      if (generation != _flowGeneration) return;
      await OpenAiCodexOAuthKeepAlive.stop(flowId: flowId);
    });
  }

  Future<void> _clearNativeCallback() async {
    await _exclusiveNative(OpenAiCodexOAuthKeepAlive.clearCallback);
  }

  Future<void> _cleanupPendingIfCurrent(
    _PendingOAuthState pending,
    int generation,
  ) async {
    await _exclusiveFlow(() async {
      if (!_ownsFlow(pending, generation)) return;
      await _stopServer();
      if (!_ownsFlow(pending, generation)) return;
      await _stopNativeIfCurrent(generation, flowId: pending.state);
    });
  }

  Future<void> _stopServer() async {
    final servers = List<HttpServer>.from(_servers);
    _servers.clear();
    for (final server in servers) {
      await server.close(force: true);
    }
  }

  Future<List<HttpServer>> _bindCallbackServers({
    int? preferredPort,
    bool allowFallback = true,
  }) async {
    Object? lastError;
    final ports = preferredPort == null
        ? const [_callbackPort, _fallbackCallbackPort]
        : <int>[preferredPort];
    for (final port in ports) {
      // The registered Codex redirect is `http://localhost:1455/...`, but
      // Android Chrome resolves it to IPv4 on affected devices.  Require an
      // IPv4 listener before declaring a port usable; an IPv6-only listener
      // would make the browser show ERR_CONNECTION_REFUSED even though bind()
      // itself succeeded. This mirrors the official Codex client. Retry a
      // recently released socket before moving to the registered fallback.
      for (var attempt = 0; attempt < 3; attempt++) {
        final servers = <HttpServer>[];
        try {
          servers.add(await HttpServer.bind(
            // The callback is strictly local to the device. The Android
            // native listener uses the same loopback-only policy; keep the
            // desktop/test fallback from exposing an OAuth endpoint on the
            // LAN as well.
            InternetAddress.loopbackIPv4,
            port,
            shared: false,
          ));
        } catch (error) {
          lastError = error;
        }

        if (servers.isNotEmpty) {
          // IPv6 is optional. Add it only after IPv4 owns the port and keep
          // the IPv4 listener if the platform does not allow a second socket.
          try {
            servers.add(await HttpServer.bind(
              InternetAddress.loopbackIPv6,
              port,
              v6Only: true,
              shared: false,
            ));
          } catch (error) {
            lastError = error;
          }
          return servers;
        }
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 80 * (attempt + 1)),
          );
        }
      }
      if (!allowFallback) break;
    }
    if (lastError is SocketException) {
      throw lastError;
    }
    throw SocketException(lastError?.toString() ?? 'unknown socket error');
  }

  Future<bool> _isCallbackReachable(String redirectUri) async {
    final uri = Uri.tryParse(redirectUri);
    final port = uri?.port;
    if (port == null || port <= 0) return false;
    Socket? socket;
    try {
      for (final address in <InternetAddress>[
        InternetAddress.loopbackIPv4,
        InternetAddress.loopbackIPv6,
      ]) {
        try {
          socket = await Socket.connect(
            address,
            port,
            timeout: const Duration(milliseconds: 350),
          );
          return true;
        } catch (_) {
          socket?.destroy();
          socket = null;
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  void _validateCallbackHostAndPort(Uri uri, Uri expected) {
    if (uri.path != expected.path) {
      throw const OpenAiCodexOAuthException(
        'OAuth 回调路径不正确，请使用 /auth/callback',
      );
    }
    if (!uri.hasScheme) return;
    final host = uri.host.toLowerCase();
    final expectedHost = expected.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (!isLoopback ||
        (expectedHost != 'localhost' && host != expectedHost) ||
        uri.port != expected.port ||
        uri.scheme != expected.scheme) {
      throw const OpenAiCodexOAuthException(
        'OAuth 回调地址不是当前设备的授权回调地址',
      );
    }
  }

  static String _safeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _successHtml() => '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>授权成功</title>
  <style>
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    html, body { width: 100%; height: 100%; margin: 0; }
    body {
      display: grid;
      place-items: center;
      padding: 24px;
      color: #fff;
      background: #6b61c7;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      text-align: center;
    }
    main { transform: translateY(-2vh); }
    .title {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 12px;
      font-size: clamp(28px, 8vw, 42px);
      font-weight: 700;
      letter-spacing: .02em;
    }
    .check { font-size: 1em; line-height: 1; }
    h1 { margin: 0; font-size: 1em; }
    p {
      margin: 20px 0 0;
      font-size: clamp(16px, 4.5vw, 22px);
      font-weight: 600;
      opacity: .9;
    }
  </style>
</head>
<body>
  <main>
    <div class="title"><span class="check">✅</span><h1>授权成功</h1></div>
    <p>您可以关闭此窗口并返回应用</p>
  </main>
</body>
</html>''';

  static String _errorHtml(String value) {
    final message = _safeHtml(value);
    return '''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>授权失败</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#fff;
background:#6b61c7;text-align:center}main{max-width:720px}h1{font-size:30px}
p{font-size:16px;line-height:1.6;opacity:.9;word-break:break-word}</style>
<main><h1>授权未完成</h1><p>$message</p><p>请关闭此窗口，返回应用后重试。</p></main>''';
  }
}

class _PendingOAuthState {
  final String providerId;
  final String codeVerifier;
  final String state;
  final String authorizationUrl;
  final String redirectUri;
  final int expiresAtMs;

  const _PendingOAuthState({
    required this.providerId,
    required this.codeVerifier,
    required this.state,
    required this.authorizationUrl,
    required this.redirectUri,
    required this.expiresAtMs,
  });

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'codeVerifier': codeVerifier,
        'state': state,
        'authorizationUrl': authorizationUrl,
        'redirectUri': redirectUri,
        'expiresAtMs': expiresAtMs,
      };

  factory _PendingOAuthState.fromJson(Map<String, dynamic> json) =>
      _PendingOAuthState(
        providerId: json['providerId']?.toString() ?? '',
        codeVerifier: json['codeVerifier']?.toString() ?? '',
        state: json['state']?.toString() ?? '',
        authorizationUrl: json['authorizationUrl']?.toString() ?? '',
        redirectUri:
            json['redirectUri']?.toString() ?? OpenAiCodexOAuth.redirectUri,
        expiresAtMs: int.tryParse(json['expiresAtMs']?.toString() ?? '') ?? 0,
      );
}
