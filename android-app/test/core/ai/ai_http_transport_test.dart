import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/ai/ai_http_transport.dart';

void main() {
  test('retries transient responses once and returns the recovered response',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.headers['content-type'], 'application/json');
      if (calls == 1) return http.Response('busy', 503);
      return http.Response('{"ok":true}', 200);
    });
    final transport = AiHttpTransport(client: client);

    final response = await transport.postWithRetry(
      Uri.parse('https://relay.example/v1/responses'),
      headers: const {'Content-Type': 'application/json'},
      body: '{"ping":true}',
      timeout: const Duration(seconds: 1),
    );

    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('does not retry permanent authorization responses', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{"error":"forbidden"}', 403);
    });
    final transport = AiHttpTransport(client: client);

    final response = await transport.postWithRetry(
      Uri.parse('https://relay.example/v1/responses'),
      body: '{}',
      timeout: const Duration(seconds: 1),
    );

    expect(response.statusCode, 403);
    expect(calls, 1);
  });

  test('retryable status helper keeps auth errors out of replay policy', () {
    expect(AiHttpTransport.isRetryableStatus(503), isTrue);
    expect(AiHttpTransport.isRetryableStatus(429), isTrue);
    expect(AiHttpTransport.isRetryableStatus(401), isFalse);
    expect(AiHttpTransport.isRetryableStatus(403), isFalse);
  });
}
