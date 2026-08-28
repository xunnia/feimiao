import 'dart:convert';
import 'dart:io';

class LocalModelCompanionConfig {
  final Uri endpoint;
  final String model;
  final bool enabled;

  const LocalModelCompanionConfig({
    required this.endpoint,
    this.model = '',
    this.enabled = false,
  });

  bool get isLocalhost =>
      endpoint.scheme == 'http' &&
      const {'127.0.0.1', 'localhost', '::1'}.contains(endpoint.host);
}

/// Optional bridge for a desktop/local companion service. The APK never
/// launches arbitrary processes; it can only call an explicitly configured
/// loopback endpoint and fails closed for remote cleartext URLs.
class LocalModelCompanionClient {
  final LocalModelCompanionConfig config;

  const LocalModelCompanionClient(this.config);

  Future<bool> checkHealth(
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (!config.enabled || !config.isLocalhost) return false;
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(config.endpoint.resolve('/health'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> complete(
    String prompt, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (!config.enabled || !config.isLocalhost) {
      throw StateError('本地模型伴侣未启用或地址不安全');
    }
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(config.endpoint.resolve('/v1/chat/completions'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }));
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('本地伴侣请求失败（${response.statusCode}）');
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['choices'] is List) {
        final choices = decoded['choices'] as List;
        if (choices.isNotEmpty && choices.first is Map) {
          final message = (choices.first as Map)['message'];
          if (message is Map) return message['content']?.toString() ?? '';
        }
      }
      return decoded is Map ? decoded['output']?.toString() ?? body : body;
    } finally {
      client.close(force: true);
    }
  }
}
