import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_url_policy.dart';

void main() {
  test('accepts HTTPS provider addresses, including private hosts', () {
    expect(
      AiProviderUrlPolicy.validateBaseUrl('https://api.example.com/v1'),
      isNull,
    );
    expect(
      AiProviderUrlPolicy.validateBaseUrl('https://192.168.31.254/v1'),
      isNull,
    );
  });

  test('allows local and private HTTP relays', () {
    const allowed = <String>[
      'http://localhost:18080/v1',
      'http://127.0.0.1:18080/v1',
      'http://[::1]:18080/v1',
      'http://10.0.0.12/v1',
      'http://172.16.4.8/v1',
      'http://172.31.4.8/v1',
      'http://192.168.31.254:18080/v1',
      'http://169.254.20.3/v1',
      'http://[fd12:3456::20]/v1',
      'http://[fe80::20]/v1',
    ];
    for (final value in allowed) {
      expect(
        AiProviderUrlPolicy.validateBaseUrl(value),
        isNull,
        reason: value,
      );
      expect(
        AiProviderUrlPolicy.isAllowedRequestUri(Uri.parse(value)),
        isTrue,
        reason: value,
      );
    }
  });

  test('rejects public cleartext and unsupported provider addresses', () {
    expect(
      AiProviderUrlPolicy.validateBaseUrl('http://api.example.com/v1'),
      AiProviderUrlError.insecureRemote,
    );
    expect(
      AiProviderUrlPolicy.validateBaseUrl('http://192.0.2.1/v1'),
      AiProviderUrlError.insecureRemote,
    );
    expect(
      AiProviderUrlPolicy.validateBaseUrl('ftp://api.example.com/v1'),
      AiProviderUrlError.unsupportedScheme,
    );
    expect(
      AiProviderUrlPolicy.validateBaseUrl('https://user:secret@api.example.com'),
      AiProviderUrlError.invalid,
    );
    expect(
      AiProviderUrlPolicy.isAllowedRequestUri(Uri.parse('http://api.example.com')),
      isFalse,
    );
  });

  test('empty address remains valid while an address is being configured', () {
    expect(AiProviderUrlPolicy.validateBaseUrl('  '), isNull);
  });
}
