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
    if (account.isNotEmpty) return 'account:$account';
    final email = accountEmail.trim().toLowerCase();
    if (email.isNotEmpty) return 'email:$email';
    final id = sourceId.trim().toLowerCase();
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

  static AiAccountJsonParseResult parse(String text) {
    final warnings = <String>[];
    final raw = text.trim();
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
      return const AiAccountJsonParseResult(
        accounts: [],
        warnings: ['不是有效的 JSON 文件'],
      );
    }

    final accounts = <AiAccountImportEntry>[];
    if (decoded is List) {
      for (var index = 0; index < decoded.length; index++) {
        final item = decoded[index];
        if (item is Map) {
          final parsed = _parseAccount(
            Map<String, dynamic>.from(item),
            source: _sourceForMap(Map<String, dynamic>.from(item)),
          );
          if (parsed != null) {
            accounts.add(parsed);
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
    final rawAccounts = root['accounts'] ?? root['providers'] ?? root['items'];
    if (rawAccounts is List) {
      final source = root['accounts'] == rawAccounts
          ? AiAccountJsonSource.sub2Api
          : AiAccountJsonSource.generic;
      for (var index = 0; index < rawAccounts.length; index++) {
        final item = rawAccounts[index];
        if (item is! Map) {
          warnings.add('第 ${index + 1} 个账号不是对象，已跳过');
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final parsed = _parseAccount(map, source: source);
        if (parsed != null) {
          accounts.add(parsed);
        } else {
          warnings.add('第 ${index + 1} 个账号缺少可用密钥或 Token，已跳过');
        }
      }
      return;
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
    } else {
      warnings.add('没有找到可用的 API Key、access_token 或 refresh_token');
    }
  }

  static AiAccountImportEntry? _parseAccount(
    Map<String, dynamic> input, {
    required AiAccountJsonSource source,
  }) {
    final credentials = _map(input['credentials']) ??
        _map(input['credential']) ??
        _map(input['auth']) ??
        const <String, dynamic>{};
    final merged = <String, dynamic>{...input, ...credentials};
    final nestedUser = _map(input['user']);

    final accessToken = _string(merged, const [
          'access_token',
          'accessToken',
          'access-token',
          'token',
        ]) ??
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
          'OPENAI_API_KEY',
          'key',
        ]) ??
        '';
    final accountId = _string(merged, const [
          'account_id',
          'accountId',
          'chatgpt_account_id',
          'chatGPTAccountId',
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
        _emailFromJwt(idToken) ??
        _emailFromJwt(accessToken) ??
        '';

    final rawType = _string(merged, const ['type', 'auth_type', 'authType'])
            ?.toLowerCase() ??
        '';
    final oauth = accessToken.isNotEmpty ||
        refreshToken.isNotEmpty ||
        idToken.isNotEmpty ||
        rawType.contains('oauth') ||
        rawType.contains('codex') ||
        rawType.contains('chatgpt');
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
          'endpoint',
          'url',
        ]) ??
        '';
    final rawModels =
        merged['models'] ?? merged['model_list'] ?? merged['modelList'];
    final models = _models(rawModels);
    final model = _string(merged, const [
          'model',
          'model_name',
          'modelName',
          'default_model',
          'defaultModel',
        ]) ??
        models.firstOrNull ??
        (oauth ? AiProviderConfig.customDefaultModel : '');
    final endpointRaw = _string(merged, const [
      'endpoint_type',
      'endpointType',
      'protocol',
      'upstream_format',
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
        ]) ??
        (oauth ? (email.isNotEmpty ? 'GPT · $email' : 'GPT') : '自定义服务');
    final effectiveBaseUrl =
        oauth ? AiProviderConfig.openAiCodexBaseUrl : baseUrl.trim();
    final expiresAtMs = _expiresAtMs(merged);
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
    final type =
        _string(map, const ['type', 'auth_type', 'authType'])?.toLowerCase() ??
            '';
    if (type.contains('codex') || type.contains('cockpit')) {
      return AiAccountJsonSource.cockpit;
    }
    if (map.containsKey('credentials') || map.containsKey('credential')) {
      return AiAccountJsonSource.sub2Api;
    }
    return AiAccountJsonSource.generic;
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
      'expiry',
      'expiration',
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
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static String? _value(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
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
