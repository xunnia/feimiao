import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'system_network_proxy.dart';

/// Shared HTTP boundary for every AI provider request.
///
/// Keeping route selection and timeout handling here prevents OAuth, model
/// discovery, streaming chat, and web search from silently using different
/// network paths. A caller may inject a [http.Client] in tests; production
/// clients are created once, after the Android proxy override has been
/// installed by `main()`.
class AiHttpTransport {
  final http.Client _client;
  final bool _ownsClient;

  AiHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  http.Client get client => _client;

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
    bool forceRouteRefresh = false,
  }) =>
      _run(
        uri,
        () => _client.get(uri, headers: headers),
        timeout: timeout,
        forceRouteRefresh: forceRouteRefresh,
      );

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 30),
    bool forceRouteRefresh = false,
  }) =>
      _run(
        uri,
        () => _client.post(
          uri,
          headers: headers,
          body: body,
          encoding: encoding,
        ),
        timeout: timeout,
        forceRouteRefresh: forceRouteRefresh,
      );

  Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 30),
    bool forceRouteRefresh = false,
  }) =>
      _run(
        uri,
        () => _client.put(
          uri,
          headers: headers,
          body: body,
          encoding: encoding,
        ),
        timeout: timeout,
        forceRouteRefresh: forceRouteRefresh,
      );

  /// Sends a request whose response body is consumed as a stream.
  ///
  /// [timeout] covers connection/headers. Stream idle timeouts remain the
  /// responsibility of the streaming parser because only that layer knows
  /// the acceptable inter-event gap.
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    Duration timeout = const Duration(seconds: 30),
    bool forceRouteRefresh = false,
  }) async {
    await _prepare(request.url, forceRouteRefresh: forceRouteRefresh);
    return _client.send(request).timeout(timeout);
  }

  Future<http.Response> _run(
    Uri uri,
    Future<http.Response> Function() action, {
    required Duration timeout,
    required bool forceRouteRefresh,
  }) async {
    await _prepare(uri, forceRouteRefresh: forceRouteRefresh);
    return action().timeout(timeout);
  }

  Future<void> _prepare(
    Uri uri, {
    required bool forceRouteRefresh,
  }) async {
    // `refresh()` updates the process-wide fallback while `refreshFor()`
    // evaluates Android PAC rules for this concrete host. Both are no-ops on
    // desktop and in unit tests.
    await SystemNetworkProxy.refresh(force: forceRouteRefresh);
    await SystemNetworkProxy.refreshFor(uri, force: forceRouteRefresh);
  }

  /// Statuses for which replaying an idempotent request is safe. Authorization
  /// code and refresh-token requests intentionally use their own policy and
  /// never blindly retry non-transient 4xx responses.
  static bool isRetryableStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Future<http.Response> postWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 30),
    int attempts = 2,
    bool forceRouteRefresh = false,
    bool Function(int statusCode)? shouldRetryStatus,
  }) async {
    final maxAttempts = attempts < 1 ? 1 : attempts;
    final retryStatus = shouldRetryStatus ?? isRetryableStatus;
    Object? lastError;
    http.Response? lastResponse;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await post(
          uri,
          headers: headers,
          body: body,
          encoding: encoding,
          timeout: timeout,
          forceRouteRefresh: forceRouteRefresh || attempt > 0,
        );
        if (!retryStatus(response.statusCode) || attempt == maxAttempts - 1) {
          return response;
        }
        lastResponse = response;
      } on Object catch (error) {
        lastError = error;
        if (attempt == maxAttempts - 1) rethrow;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 250 * (1 << attempt.clamp(0, 4))),
      );
    }
    if (lastResponse != null) return lastResponse;
    throw lastError ?? StateError('AI transport request failed');
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
