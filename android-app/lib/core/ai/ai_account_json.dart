import 'dart:convert';

import 'ai_provider_config.dart';

/// The external account-file dialect from which an account was read.
enum AiAccountJsonSource {
  cockpit,
  openAiAuth,
  sub2Api,
  generic,
}

extension AiAccountJsonSourceX on AiAccountJsonSource {
  String get label => switch (this) {
        AiAccountJsonSource.cockpit => 'Cockpit',
        AiAccountJsonSource.openAiAuth => 'OpenAI auth.json',
        AiAccountJsonSource.sub2Api => 'Sub2API',
        AiAccountJsonSource.generic => '通用 JSON',
      };
}

/// One account extracted from a portable account file.
///
/// Token fields intentionally live only in this short-lived import object and
/// are never included in its [toString]. The repository writes them to the
/// platform secure store as soon as the user confirms the import.
class AiAccountImportEntry {
  final AiAccountJsonSource source;
  final String sourceId;
  final String displayName;
  final String accountEmail;
  final String accountId;
  final String accessToken;
  final String refreshToken;
  final String idToken;
  final String apiKey;
  final String baseUrl;
  final String model;
  final List<String> models;
  final AiEndpointType endpointType;
  final AiAuthMethod authMethod;
  final int? expiresAtMs;
  final bool enabled;

  const AiAccountImportEntry({
    required this.source,
    this.sourceId = '',
    this.displayName = '',
    this.accountEmail = '',
    this.accountId = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.idToken = '',
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.models = const [],
    this.endpointType = AiEndpointType.auto,
    this.authMethod = AiAuthMethod.apiKey,
    this.expiresAtMs,
    this.enabled = true,
  });

  bool get isOAuth => authMethod == AiAuthMethod.oauth;

  /// The credential that will be persisted in the provider's API-key slot.
  /// OAuth access tokens use that slot because the existing request layer
  /// already refreshes them through [oauthRefreshToken].
  String get credential => isOAuth ? accessToken : apiKey;

  bool get hasCredential =>
      credential.trim().isNotEmpty ||
      (isOAuth && refreshToken.trim().isNotEmpty);

  String get identityKey {
    final account = accountId.trim().toLowerCase();
    final email = accountEmail.trim().toLowerCase();
    // Cockpit and Sub2API exports can contain several independent tokens in
    // the same ChatGPT workspace. `account_id` is not unique by itself;
    // pairing it with the email keeps each exported identity available.
    if (account.isNotEmpty && email.isNotEmpty) {
      return 'account-email:$account|$email';
    }
    if (email.isNotEmpty) return 'email:$email';
    final id = sourceId.trim().toLowerCase();
    if (account.isNotEmpty && id.isNotEmpty) {
      return 'account-id:$account|$id';
    }
    if (account.isNotEmpty) return 'account:$account';
    if (id.isNotEmpty) return 'id:$id';
    final name = displayName.trim().toLowerCase();
    if (name.isNotEmpty) return 'name:$name';
    return '';
  }

  String get maskedIdentity {
    final email = accountEmail.trim();
    if (email.contains('@')) {
      final parts = email.split('@');
      final local = parts.first;
      final shown = local.length <= 2
          ? '${local.substring(0, 1)}*'
          : '${local.substring(0, 2)}***';
      return '$shown@${parts.skip(1).join('@')}';
    }
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final id = accountId.trim();
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  @override
  String toString() =>
      'AiAccountImportEntry(source: ${source.label}, identity: $maskedIdentity)';
}

class AiAccountJsonParseResult {
  final List<AiAccountImportEntry> accounts;
  final List<String> warnings;

  const AiAccountJsonParseResult({
    required this.accounts,
    this.warnings = const [],
  });

  bool get isEmpty => accounts.isEmpty;
}

/// Portable account JSON support.
///
/// The parser is deliberately permissive on field spelling because Cockpit,
/// OpenAI's auth.json, and Sub2API have used both snake_case and camelCase
/// names over time. It remains conservative about credentials: an object is
/// accepted only when it contains an API key or at least one OAuth token.
class AiAccountJsonCodec {
  const AiAccountJsonCodec._();

  /// Decode account files exported by Windows tools as well as normal UTF-8
  /// JSON. Cockpit writes UTF-8, but users sometimes re-save the file from
  /// Notepad as UTF-8-with-BOM or UTF-16; silently decoding those bytes as
  /// malformed UTF-8 makes an otherwise valid account look empty.
  static String decodeBytes(Iterable<int> bytes) {
    final data = List<int>.from(bytes);
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      return utf8.decode(data.sublist(3), allowMalformed: true);
    }
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      return String.fromCharCodes([
        for (var index = 2; index + 1 < data.length; index += 2)
          data[index] | (data[index + 1] << 8),
      ]);
    }
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      return String.fromCharCodes([
        for (var index = 2; index + 1 < data.length; index += 2)
          (data[index] << 8) | data[index + 1],
      ]);
    }
    return utf8.decode(data, allowMalformed: true);
  }

  static AiAccountJsonParseResult parse(String text) {
    final warnings = <String>[];
    final raw = text.replaceFirst('\uFEFF', '').trim();
    if (raw.isEmpty) {
      return const AiAccountJsonParseResult(
        accounts: [],
        warnings: ['文件为空'],
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // Cockpit's batch/import tooling may emit JSON Lines when several
      // portable account documents are concatenated. Accept that shape only
      // when every non-empty line is an independently valid JSON object; a
      // malformed pretty-printed JSON document must still fail closed.
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (lines.isEmpty) {
        return const AiAccountJsonParseResult(
          accounts: [],
          warnings: ['不是有效的 JSON 文件'],
        );
      }
      final jsonLines = <Map<String, dynamic>>[];
      for (final line in lines) {
        try {
          final value = jsonDecode(line);
          if (value is! Map) {
            return const AiAccountJsonParseResult(
              accounts: [],
              warnings: ['不是有效的 JSON 文件'],
            );
          }
          jsonLines.add(Map<String, dynamic>.from(value));
        } catch (_) {
          return const AiAccountJsonParseResult(
            accounts: [],
            warnings: ['不是有效的 JSON 文件'],
          );
        }
      }
      decoded = jsonLines;
    }

    // Some export/share flows wrap the actual document as a JSON string in a
    // `data`, `payload`, `json`, or `content` field. Unwrap at most twice so a
    // nested document is accepted without treating arbitrary text as an
    // account file.
    for (var depth = 0; depth < 2; depth++) {
      final unwrapped = _embeddedDocument(decoded);
      if (identical(unwrapped, decoded)) break;
      decoded = unwrapped;
    }

    final accounts = <AiAccountImportEntry>[];
    if (decoded is List) {
      for (var index = 0; index < decoded.length; index++) {
        final item = decoded[index];
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final parsed = _parseAccount(map, source: _sourceForMap(map));
          if (parsed != null) {
            accounts.add(parsed);
          } else if (_looksLikeAgentIdentity(map)) {
            warnings.add(
              '第 ${index + 1} 个账号是 Agent Identity；Android 当前只支持 OAuth Token/API Key，'
              '请从 Cockpit 导出包含 access_token/refresh_token 的 OAuth 账号',
            );
          } else {
            warnings.add('第 ${index + 1} 个账号缺少可用密钥或 Token，已跳过');
          }
        }
      }
    } else if (decoded is Map) {
      _parseRoot(Map<String, dynamic>.from(decoded), accounts, warnings);
    } else {
      warnings.add('JSON 顶层必须是对象或数组');
    }

    // A multi-account export can contain the same account twice. Keep the
    // first copy to make the preview and conflict decision deterministic.
    final seen = <String>{};
    final unique = <AiAccountImportEntry>[];
    for (final account in accounts) {
      final key = account.identityKey;
      if (key.isNotEmpty && !seen.add(key)) {
        warnings.add('检测到重复账号 ${account.maskedIdentity}，已合并为一条');
        continue;
      }
      unique.add(account);
    }
    if (unique.isEmpty && warnings.isEmpty) {
      warnings.add('没有找到可导入的账号');
    }
    return AiAccountJsonParseResult(
      accounts: List.unmodifiable(unique),
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Encode a list in the flat multi-account shape accepted by Cockpit.
  ///
  /// This is an intentional secret export. Callers must present a warning
  /// before sharing the resulting file because it contains active credentials.
  static String encodeCockpit(
    Iterable<AiConfiguredProvider> providers, {
    bool includeDisabled = true,
  }) {
    final records = <Map<String, dynamic>>[];
    for (final provider in providers) {
      if (!includeDisabled && !provider.enabled) continue;
      final oauth = provider.authMethod == AiAuthMethod.oauth;
      final record = <String, dynamic>{
        'id': provider.id,
        'type': oauth ? 'codex' : 'api_key',
        'enabled': provider.enabled,
        'name': provider.displayName,
        'base_url': provider.baseUrl,
        'model': provider.selectedModel,
        'models': provider.models,
        'endpoint_type': provider.endpointType.storageKey,
      };
      if (provider.accountEmail.trim().isNotEmpty) {
        record['email'] = provider.accountEmail.trim();
      }
      if (oauth) {
        _putIfNotEmpty(record, 'id_token', provider.oauthIdToken);
        _putIfNotEmpty(record, 'access_token', provider.apiKey);
        _putIfNotEmpty(record, 'refresh_token', provider.oauthRefreshToken);
        _putIfNotEmpty(record, 'account_id', provider.oauthAccountId);
        if (provider.oauthExpiresAtMs != null) {
          record['expired'] = provider.oauthExpiresAtMs;
        }
      } else {
        _putIfNotEmpty(record, 'api_key', provider.apiKey);
      }
      records.add(record);
    }
    return const JsonEncoder.withIndent('  ').convert(records);
  }

  static void _parseRoot(
    Map<String, dynamic> root,
    List<AiAccountImportEntry> accounts,
    List<String> warnings,
  ) {
    // Cockpit's full backup wraps each platform export below
    // `accounts.platforms.<platform>.exported_data`.  This is a valid
    // credential-bearing export, but it is not the same as the lightweight
    // `codex_accounts.json` index (which intentionally contains metadata
    // only).  Pull only Codex platform sections here so unrelated platform
    // accounts are never imported into the GPT provider list.
    final cockpitData = _cockpitCodexExportedData(root);
    if (cockpitData != null) {
      _parseAccountList(
        cockpitData,
        source: AiAccountJsonSource.cockpit,
        accounts: accounts,
        warnings: warnings,
      );
      if (cockpitData.isNotEmpty) return;
      warnings.add('Cockpit 备份中没有可用的 Codex 账号凭据');
      return;
    }

    final rawAccounts = root['accounts'] ??
        root['providers'] ??
        root['items'] ??
        // A single Cockpit platform transfer section can be shared without
        // the outer `platforms` map.
        root['exported_data'] ??
        // Some account managers wrap a portable export in a generic `data`
        // array. Only entries with credentials are accepted below, so a model
        // catalogue accidentally pasted here still fails closed.
        root['data'];
    if (rawAccounts is List) {
      final rootType = root['type']?.toString().toLowerCase() ?? '';
      final rootSource = rootType.contains('sub2api') ||
              root.containsKey('proxies') ||
              root.containsKey('exported_at')
          ? AiAccountJsonSource.sub2Api
          : AiAccountJsonSource.generic;
      _parseAccountList(
        rawAccounts,
        source: rootSource,
        accounts: accounts,
        warnings: warnings,
      );
      return;
    }

    // A few tools serialize accounts as an object keyed by account id rather
    // than an array. Treat each map value as a candidate while preserving the
    // normal single-account/auth.json path when the values are not objects.
    if (rawAccounts is Map) {
      final values = rawAccounts.values.whereType<Map>();
      if (values.isNotEmpty) {
        for (final value in values) {
          final map = Map<String, dynamic>.from(value);
          final parsed = _parseAccount(
            map,
            source: _sourceForMap(map),
          );
          if (parsed != null) {
            accounts.add(parsed);
          } else if (_looksLikeAgentIdentity(map)) {
            warnings.add(
              '发现 Agent Identity 账号；Android 当前只支持 OAuth Token/API Key，已跳过',
            );
          } else {
            warnings.add('发现一个账号对象，但其中没有可用密钥或 Token，已跳过');
          }
        }
        return;
      }
    }

    final tokens = _map(root['tokens']) ?? _map(root['token']);
    if (tokens != null || _value(root, const ['OPENAI_API_KEY']) != null) {
      final merged = <String, dynamic>{...root, ...?tokens};
      final parsed =
          _parseAccount(merged, source: AiAccountJsonSource.openAiAuth);
      if (parsed != null) {
        accounts.add(parsed);
      } else {
        warnings.add('auth.json 中没有可用的 Token 或 API Key');
      }
      return;
    }

    final parsed = _parseAccount(
      root,
      source: _sourceForMap(root),
    );
    if (parsed != null) {
      accounts.add(parsed);
    } else if (_looksLikeAgentIdentity(root)) {
      warnings.add(
        '该文件是 Agent Identity 凭据；Android 当前只支持 OAuth Token/API Key，'
        '请导出包含 access_token/refresh_token 的 OAuth JSON',
      );
    } else {
      warnings.add('没有找到可用的 API Key、access_token 或 refresh_token');
    }
  }

  /// Returns credential-bearing Codex records from Cockpit's full backup
  /// envelope, or `null` when the input is not that envelope. An empty list is
  /// meaningful: it means the backup is recognized but contains no Codex
  /// accounts, and should produce a precise warning instead of falling through
  /// to the metadata-only index parser.
  static List<Map<String, dynamic>>? _cockpitCodexExportedData(
    Map<String, dynamic> root,
  ) {
    final accounts = _map(root['accounts']);
    final platforms = _map(accounts?['platforms']) ?? _map(root['platforms']);
    final hasCockpitMarker = root.containsKey('schema') ||
        root.containsKey('exported_at') ||
        accounts?.containsKey('summary') == true;
    if (!hasCockpitMarker) return null;

    // Also accept an individual transfer section such as
    // `{account_count, exported_data}`.
    if (platforms == null) {
      final raw = root['exported_data'] ?? root['data'];
      final list = _list(raw);
      if (list != null) {
        return [
          for (final item in list)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      }
      final single = _map(raw);
      if (single != null) return [single];

      // A few backup writers keep the credential-bearing account array at the
      // root while still adding the Cockpit schema marker. Do not discard it
      // merely because `accounts` is an array rather than the usual summary
      // object.
      final rootAccounts = _list(root['accounts']);
      if (rootAccounts != null) {
        return [
          for (final item in rootAccounts)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      }
      return null;
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in platforms.entries) {
      final platform = entry.key.toLowerCase().replaceAll('-', '_');
      if (platform != 'codex' && platform != 'codex_api_service') continue;
      final section = _map(entry.value);
      if (section == null) continue;
      final raw = section['exported_data'] ??
          section['data'] ??
          section['accounts'] ??
          section['items'];
      final list = _list(raw);
      if (list != null) {
        for (final item in list) {
          if (item is Map) result.add(Map<String, dynamic>.from(item));
        }
      } else {
        final single = _map(raw);
        if (single != null) result.add(single);
      }
    }
    return result;
  }

  static void _parseAccountList(
    List<dynamic> rawAccounts, {
    required AiAccountJsonSource source,
    required List<AiAccountImportEntry> accounts,
    required List<String> warnings,
  }) {
    for (var index = 0; index < rawAccounts.length; index++) {
      final item = rawAccounts[index];
      if (item is! Map) {
        warnings.add('第 ${index + 1} 个账号不是对象，已跳过');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final detectedSource = _sourceForMap(map);
      final parsed = _parseAccount(
        map,
        // The surrounding Cockpit full-backup envelope is authoritative even
        // when its records use the same nested `tokens` shape as auth.json.
        source: source == AiAccountJsonSource.cockpit ||
                detectedSource == AiAccountJsonSource.generic
            ? source
            : detectedSource,
      );
      if (parsed != null) {
        accounts.add(parsed);
      } else if (_looksLikeAgentIdentity(map)) {
        warnings.add(
          '第 ${index + 1} 个账号是 Agent Identity；Android 当前只支持 OAuth Token/API Key，'
          '请从 Cockpit 导出包含 access_token/refresh_token 的 OAuth 账号',
        );
      } else {
        warnings.add('第 ${index + 1} 个账号缺少可用密钥或 Token，已跳过');
      }
    }
  }

  static AiAccountImportEntry? _parseAccount(
    Map<String, dynamic> input, {
    required AiAccountJsonSource source,
  }) {
    // Web-session exports from Cockpit may wrap the actual session as an
    // object or as a JSON string under session/session_json. Normalize that
    // envelope before reading the same token fields as auth.json.
    final embeddedSession = _embeddedMap(
          input['session_json'] ?? input['sessionJson'],
        ) ??
        _embeddedMap(input['session']);
    // Cockpit exports its full CodexAccount objects with OAuth credentials in
    // a nested `tokens` object. Keep the top-level account metadata while
    // flattening the credential envelope for the common field readers below.
    // `token` is also accepted when a tool wraps the same object under that
    // singular key; non-map token values remain available to the scalar
    // `token` reader through the original input map.
    final tokens = _map(input['tokens']) ??
        _map(input['token']) ??
        _map(input['token_data']) ??
        _map(input['tokenData']) ??
        _map(embeddedSession?['tokens']) ??
        _map(embeddedSession?['token']) ??
        _map(embeddedSession?['token_data']) ??
        _map(embeddedSession?['tokenData']);
    final credentials = _map(input['credentials']) ??
        _map(input['credential']) ??
        _map(input['auth']) ??
        _map(embeddedSession?['credentials']) ??
        const <String, dynamic>{};
    final merged = <String, dynamic>{
      ...input,
      ...?embeddedSession,
      ...?tokens,
      ...credentials,
    };
    final nestedUser = _map(input['user']) ?? _map(embeddedSession?['user']);
    final nestedProfile =
        _map(input['profile']) ?? _map(embeddedSession?['profile']);
    final nestedAccount =
        _map(input['account']) ?? _map(embeddedSession?['account']);
    final headers = _map(input['headers']) ??
        _map(credentials['headers']) ??
        _map(embeddedSession?['headers']);
    final customHeaders = _map(input['custom_headers']) ??
        _map(input['customHeaders']) ??
        _map(credentials['custom_headers']) ??
        _map(credentials['customHeaders']);

    final accessToken = _string(merged, const [
          'access_token',
          'accessToken',
          'access-token',
          'personal_access_token',
          'personalAccessToken',
          'at_token',
          'atToken',
          'session_token',
          'sessionToken',
          'token',
        ]) ??
        _bearerToken(headers) ??
        _bearerToken(customHeaders) ??
        '';
    final refreshToken = _string(merged, const [
          'refresh_token',
          'refreshToken',
          'refresh-token',
        ]) ??
        '';
    final idToken = _string(merged, const ['id_token', 'idToken']) ?? '';
    final apiKey = _string(merged, const [
          'api_key',
          'apiKey',
          'openai_api_key',
          'OPENAI_API_KEY',
          'key',
        ]) ??
        '';
    final accountId = _string(merged, const [
          'account_id',
          'accountId',
          'chatgpt_account_id',
          'chatGPTAccountId',
          'workspace_id',
          'workspaceId',
        ]) ??
        _string(nestedAccount, const [
          'id',
          'account_id',
          'accountId',
          'chatgpt_account_id',
          'chatgptAccountId',
        ]) ??
        _string(headers, const [
          'ChatGPT-Account-Id',
          'Chatgpt-Account-Id',
          'chatgpt-account-id',
          'x-chatgpt-account-id',
        ]) ??
        _string(customHeaders, const [
          'ChatGPT-Account-Id',
          'Chatgpt-Account-Id',
          'chatgpt-account-id',
          'x-chatgpt-account-id',
        ]) ??
        _accountIdFromJwt(idToken) ??
        _accountIdFromJwt(accessToken) ??
        '';
    final email = _string(merged, const [
          'email',
          'account_email',
          'accountEmail',
        ]) ??
        _string(nestedUser, const ['email']) ??
        _string(
            nestedAccount, const ['email', 'account_email', 'accountEmail']) ??
        _string(nestedProfile, const ['email']) ??
        _emailFromJwt(idToken) ??
        _emailFromJwt(accessToken) ??
        '';

    // Prefer an explicit auth mode over the broad `type: codex` marker. Some
    // official auth.json/API-service exports use `type: codex` for both API
    // Key and OAuth accounts; treating that marker as OAuth when only
    // OPENAI_API_KEY is present creates an unusable provider with no access
    // token. A real token always wins, while a marker alone is only accepted
    // when no API key is present.
    final explicitAuthMode = _string(
          merged,
          const [
            'auth_mode',
            'authMode',
            'openai_auth_mode',
            'auth_type',
            'authType',
            'authProvider',
          ],
        )?.toLowerCase() ??
        '';
    final rawType = _string(merged, const ['type'])?.toLowerCase() ?? '';
    final explicitApiKey = explicitAuthMode.contains('api') ||
        explicitAuthMode.contains('key') ||
        explicitAuthMode == 'apikey';
    final tokenOAuth =
        accessToken.isNotEmpty || refreshToken.isNotEmpty || idToken.isNotEmpty;
    final markerOAuth = !explicitApiKey &&
        (explicitAuthMode.contains('oauth') ||
            explicitAuthMode.contains('codex') ||
            explicitAuthMode.contains('chatgpt') ||
            rawType.contains('oauth') ||
            rawType.contains('codex') ||
            rawType.contains('chatgpt'));
    final oauth = tokenOAuth || (markerOAuth && apiKey.isEmpty);
    if (!oauth && apiKey.isEmpty) return null;
    if (oauth &&
        accessToken.isEmpty &&
        refreshToken.isEmpty &&
        idToken.isEmpty) {
      return null;
    }

    final baseUrl = _string(merged, const [
          'base_url',
          'baseUrl',
          'api_base',
          'apiBase',
          'api_base_url',
          'apiBaseUrl',
          'endpoint',
          'url',
        ]) ??
        '';
    final hasApiModelCatalog = merged.containsKey('api_model_catalog') ||
        merged.containsKey('apiModelCatalog');
    final rawModels = merged['models'] ??
        merged['model_list'] ??
        merged['modelList'] ??
        // Cockpit's Codex API-key export names this field explicitly. Keep
        // the catalog so an imported relay account does not silently fall
        // back to a model that the relay never exposed.
        merged['api_model_catalog'] ??
        merged['apiModelCatalog'];
    final models = _models(rawModels)
        .where((model) => !hasApiModelCatalog || !_isInternalModel(model))
        .toList(growable: false);
    final explicitModel = _string(merged, const [
          'model',
          'model_name',
          'modelName',
          'default_model',
          'defaultModel',
        ]) ??
        '';
    final parsedModel = explicitModel.isNotEmpty
        ? explicitModel
        : _preferredImportedModel(models);
    // An imported standard OpenAI/Codex credential must be usable immediately
    // even when the source export omits its model catalogue. The user can
    // still replace this fallback in the provider card or refresh the list.
    final model = parsedModel.isEmpty && (oauth || apiKey.trim().isNotEmpty)
        ? (oauth
            ? AiProviderConfig.openAiCodexDefaultModel
            : AiProviderConfig.customDefaultModel)
        : parsedModel;
    final endpointRaw = _string(merged, const [
      'endpoint_type',
      'endpointType',
      'protocol',
      'upstream_format',
      'api_wire_api',
      'apiWireApi',
    ]);
    final endpoint = oauth
        ? AiEndpointType.responses
        : _endpointFromAny(endpointRaw, baseUrl: baseUrl);
    final displayName = _string(merged, const [
          'display_name',
          'displayName',
          'name',
          'label',
          'provider_name',
          'providerName',
          'account_name',
          'accountName',
        ]) ??
        _string(nestedAccount, const [
          'name',
          'display_name',
          'displayName',
          'account_name',
          'accountName',
        ]) ??
        _string(nestedProfile, const ['name', 'display_name', 'displayName']) ??
        (oauth ? (email.isNotEmpty ? 'GPT · $email' : 'GPT') : '自定义服务');
    final effectiveBaseUrl =
        oauth ? AiProviderConfig.openAiCodexBaseUrl : baseUrl.trim();
    final expiresAtMs = _expiresAtMs(merged) ?? _expiresAtFromJwt(accessToken);
    final enabled =
        merged['enabled'] == false || merged['disabled'] == true ? false : true;
    return AiAccountImportEntry(
      source: source,
      sourceId: _string(merged, const ['id', 'uuid', 'uid', 'account']) ?? '',
      displayName: displayName.trim(),
      accountEmail: email.trim(),
      accountId: accountId.trim(),
      accessToken: accessToken.trim(),
      refreshToken: refreshToken.trim(),
      idToken: idToken.trim(),
      apiKey: apiKey.trim(),
      baseUrl: effectiveBaseUrl,
      model: model.trim(),
      models: _dedupe([model, ...models]),
      endpointType: endpoint,
      authMethod: oauth ? AiAuthMethod.oauth : AiAuthMethod.apiKey,
      expiresAtMs: expiresAtMs,
      enabled: enabled,
    );
  }

  static AiAccountJsonSource _sourceForMap(Map<String, dynamic> map) {
    final type = _string(
          map,
          const ['type', 'auth_type', 'authType', 'auth_mode', 'authMode'],
        )?.toLowerCase() ??
        '';
    if (type.contains('codex') || type.contains('cockpit')) {
      return AiAccountJsonSource.cockpit;
    }
    if (map.containsKey('credentials') || map.containsKey('credential')) {
      return AiAccountJsonSource.sub2Api;
    }
    if (map.containsKey('tokens') || map.containsKey('token')) {
      return AiAccountJsonSource.openAiAuth;
    }
    return AiAccountJsonSource.generic;
  }

  static bool _looksLikeAgentIdentity(Map<String, dynamic> map) {
    final mode = _string(
      map,
      const ['auth_mode', 'authMode', 'openai_auth_mode'],
    )?.toLowerCase();
    if (mode?.replaceAll('_', '').contains('agentidentity') == true) {
      return true;
    }
    final identity = _map(map['agent_identity']) ?? _map(map['agentIdentity']);
    if (identity != null) return true;
    final credentials = _map(map['credentials']);
    return (credentials?['agent_runtime_id'] != null ||
            credentials?['agentRuntimeId'] != null) &&
        (credentials?['agent_private_key'] != null ||
            credentials?['agentPrivateKey'] != null);
  }

  static AiEndpointType _endpointFromAny(String? value, {String baseUrl = ''}) {
    final raw = value?.trim().toLowerCase() ?? '';
    if (raw.contains('anthropic') ||
        raw.contains('claude') ||
        raw == 'messages') {
      return AiEndpointType.anthropicMessages;
    }
    if (raw.contains('response')) return AiEndpointType.responses;
    if (raw.contains('chat')) return AiEndpointType.chatCompletions;
    final lowerBase = baseUrl.toLowerCase();
    if (lowerBase.contains('anthropic.com')) {
      return AiEndpointType.anthropicMessages;
    }
    return AiEndpointType.auto;
  }

  static List<String> _models(Object? raw) {
    if (raw is! List) return const [];
    return _dedupe(raw.map((item) {
      if (item is Map) {
        return (item['slug'] ?? item['id'] ?? item['name'] ?? '').toString();
      }
      return item?.toString() ?? '';
    }));
  }

  static String _preferredImportedModel(List<String> models) {
    // Cockpit includes its internal review model at the front of some API
    // service catalogs. It is not a safe default for a user's normal request;
    // retain it in the list but select the first ordinary model instead.
    return models.firstOrNull ?? '';
  }

  static bool _isInternalModel(String model) =>
      model.trim().toLowerCase() == 'codex-auto-review';

  static List<String> _dedupe(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) result.add(trimmed);
    }
    return List.unmodifiable(result);
  }

  static int? _expiresAtMs(Map<String, dynamic> map) {
    Object? raw;
    for (final key in const [
      'expires_at_ms',
      'expiresAtMs',
      'expired_at_ms',
      'expiredAtMs',
      'expired',
      'expires_at',
      'expiresAt',
      'expires',
      'expiry',
      'expiration',
      'token_expires_at',
      'tokenExpiresAt',
    ]) {
      if (map.containsKey(key)) {
        raw = map[key];
        break;
      }
    }
    final number = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString().trim() ?? '');
    if (number != null && number > 0) {
      return (number < 100000000000 ? number * 1000 : number).round();
    }
    final date = DateTime.tryParse(raw?.toString().trim() ?? '');
    if (date != null) return date.millisecondsSinceEpoch;
    final expiresIn = map['expires_in'] ?? map['expiresIn'];
    final seconds = expiresIn is num
        ? expiresIn.toInt()
        : int.tryParse(expiresIn?.toString() ?? '');
    if (seconds != null && seconds > 0) {
      return DateTime.now()
          .add(Duration(seconds: seconds))
          .millisecondsSinceEpoch;
    }
    return null;
  }

  static String? _emailFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      for (final key in const ['email', 'preferred_username', 'upn']) {
        final value = payload[key]?.toString().trim();
        if (value != null && value.contains('@')) return value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static int? _expiresAtFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final exp = payload['exp'];
      final seconds =
          exp is num ? exp.toInt() : int.tryParse(exp?.toString() ?? '');
      return seconds == null || seconds <= 0 ? null : seconds * 1000;
    } catch (_) {
      return null;
    }
  }

  static String? _accountIdFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final auth = payload['https://api.openai.com/auth'];
      if (auth is Map) {
        final value = (auth['chatgpt_account_id'] ?? auth['account_id'])
            ?.toString()
            .trim();
        if (value != null && value.isNotEmpty) return value;
      }
      for (final key in const ['chatgpt_account_id', 'account_id']) {
        final value = payload[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static List<dynamic>? _list(Object? value) {
    if (value is List) return value;
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _embeddedMap(Object? value) {
    final map = _map(value);
    if (map != null) return map;
    if (value is! String || value.trim().isEmpty) return null;
    try {
      return _map(jsonDecode(value));
    } catch (_) {
      return null;
    }
  }

  static Object? _embeddedDocument(Object? value) {
    if (value is! Map) return value;
    for (final key in const ['data', 'payload', 'json', 'content']) {
      final candidate = value[key];
      if (candidate is! String || candidate.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map || decoded is List) return decoded;
      } catch (_) {
        // Continue looking for another recognized wrapper key.
      }
    }
    return value;
  }

  static String? _bearerToken(Map<String, dynamic>? headers) {
    final raw = _string(headers, const ['authorization', 'Authorization']);
    if (raw == null) return null;
    final value = raw.trim();
    final prefix = RegExp(r'^Bearer\s+', caseSensitive: false);
    return prefix.hasMatch(value)
        ? value.replaceFirst(prefix, '').trim()
        : null;
  }

  static String? _value(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      // Never stringify nested maps/lists. In particular, a Cockpit
      // `{token: {access_token: ...}}` wrapper must not become a literal
      // `"{access_token: ...}"` credential when the flattened key is absent.
      if (value is Map || value is Iterable) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String? _string(Map<String, dynamic>? map, List<String> keys) =>
      _value(map, keys);

  static void _putIfNotEmpty(
    Map<String, dynamic> map,
    String key,
    String value,
  ) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) map[key] = trimmed;
  }
}
