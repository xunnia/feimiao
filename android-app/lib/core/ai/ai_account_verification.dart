import 'dart:async';

import 'package:http/http.dart' as http;

import 'ai_provider_config.dart';
import 'ai_logger.dart';
import 'llm_query.dart';
import 'openai_codex_oauth.dart';

/// Result of the post-import account health check.
enum AiAccountVerificationStatus {
  available,
  needsProxy,
  invalidCredential,
  modelUnavailable,
  networkError,
  configurationError,
}

extension AiAccountVerificationStatusX on AiAccountVerificationStatus {
  String get label => switch (this) {
        AiAccountVerificationStatus.available => '可用',
        AiAccountVerificationStatus.needsProxy => '需要代理/VPN',
        AiAccountVerificationStatus.invalidCredential => '凭据失效',
        AiAccountVerificationStatus.modelUnavailable => '模型不可用',
        AiAccountVerificationStatus.networkError => '网络失败',
        AiAccountVerificationStatus.configurationError => '配置不完整',
      };
}

class AiAccountVerificationResult {
  final AiAccountVerificationStatus status;
  final List<String> models;
  final String message;
  final int latencyMs;

  const AiAccountVerificationResult({
    required this.status,
    this.models = const [],
    this.message = '',
    this.latencyMs = 0,
  });

  bool get isAvailable => status == AiAccountVerificationStatus.available;

  String get summary =>
      '${status.label}${message.trim().isEmpty ? '' : '：${message.trim()}'}';
}

/// Verifies an imported provider without sending any ledger or user message.
///
/// The check deliberately uses the same model-catalog and connection paths as
/// normal Chats. This catches the common false-positive where an account can
/// be parsed and displayed but cannot actually reach its upstream endpoint.
class AiAccountVerificationService {
  final http.Client? client;

  const AiAccountVerificationService({this.client});

  Future<AiAccountVerificationResult> verify(
    AiProviderConfig config, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final started = DateTime.now();
    // A missing model is not a configuration failure by itself: the purpose
    // of this check is to discover the upstream catalogue and choose its first
    // usable model. Credentials and base URL are the only prerequisites for
    // the catalogue request.
    if (!config.hasCredential || !config.hasBaseUrl) {
      return const AiAccountVerificationResult(
        status: AiAccountVerificationStatus.configurationError,
        message: '缺少凭据、基础地址或模型',
      );
    }

    var discoveredModels = const <String>[];
    try {
      // Refresh-only Cockpit exports need an access-token exchange before both
      // catalogue discovery and the probe.  Use the same injected client for
      // both calls so tests and production cannot silently take different
      // network routes.
      final oauthService = client == null
          ? OpenAiCodexOAuth.service
          : OpenAiCodexOAuthService(client: client);
      final prepared = await oauthService.ensureFreshConfig(config);
      discoveredModels = await LlmQuery.fetchModels(
        prepared,
        client: client,
        timeout: timeout,
      );
      final selectedModel = discoveredModels
              .where((model) => model.trim().isNotEmpty)
              .firstOrNull ??
          prepared.model;
      if (selectedModel.trim().isEmpty) {
        return AiAccountVerificationResult(
          status: AiAccountVerificationStatus.modelUnavailable,
          message: '模型目录为空',
          latencyMs: DateTime.now().difference(started).inMilliseconds,
        );
      }
      final probeConfig = prepared.copyWith(model: selectedModel);
      // `testConnection` sends only the fixed system/user probe ("ping"); no
      // account transactions, conversation history, or attachments are used.
      await LlmQuery.testConnection(
        probeConfig,
        client: client,
      ).timeout(timeout);
      return AiAccountVerificationResult(
        status: AiAccountVerificationStatus.available,
        models: discoveredModels,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } on OpenAiCodexOAuthException catch (error) {
      return AiAccountVerificationResult(
        status: _statusFor(error.statusCode, error.message),
        models: discoveredModels,
        message: _safeMessage(error.message),
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } on LlmQueryException catch (error) {
      return AiAccountVerificationResult(
        status: _statusFor(error.statusCode, error.message),
        models: discoveredModels,
        message: _safeMessage(error.message),
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } on TimeoutException {
      return AiAccountVerificationResult(
        status: AiAccountVerificationStatus.networkError,
        models: discoveredModels,
        message: '请求超时',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (error) {
      return AiAccountVerificationResult(
        status: _statusFor(null, error.toString()),
        models: discoveredModels,
        message: _safeMessage(error.toString()),
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    }
  }

  static AiAccountVerificationStatus _statusFor(int? code, String message) {
    final lower = message.toLowerCase();
    if (lower.contains('unsupported_country') ||
        lower.contains('unsupported country') ||
        lower.contains('country, region') ||
        lower.contains('proxy') ||
        lower.contains('socket') ||
        lower.contains('超时') ||
        lower.contains('网络')) {
      return AiAccountVerificationStatus.needsProxy;
    }
    if (code == 401 || code == 403) {
      return AiAccountVerificationStatus.invalidCredential;
    }
    if (code == 400 || code == 404 || lower.contains('model')) {
      return AiAccountVerificationStatus.modelUnavailable;
    }
    if (errorLooksLikeConfig(lower)) {
      return AiAccountVerificationStatus.configurationError;
    }
    return AiAccountVerificationStatus.networkError;
  }

  static bool errorLooksLikeConfig(String lower) =>
      lower.contains('未配置') ||
      lower.contains('配置不完整') ||
      lower.contains('api key') && lower.contains('未');

  static String _safeMessage(String raw) {
    final compact = AiLogger.sanitizeErrorForDisplay(raw)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) return '';
    return compact.length <= 180 ? compact : '${compact.substring(0, 177)}...';
  }
}
