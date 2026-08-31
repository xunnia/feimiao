import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_health.dart';

void main() {
  test('explicit verification status survives normal request failures', () {
    const now = 1735689600000;
    var health = const AiProviderHealth(providerId: 'account-1');

    health = health.recordVerification(
      status: 'invalid_credential',
      message: '凭据失效',
      latencyMs: 120,
      now: now,
    );
    expect(health.verificationStatus, 'invalid_credential');
    expect(health.statusLabel, '凭据失效');

    health = health.recordFailure('temporary network error', now + 1);
    expect(health.verificationStatus, 'invalid_credential');
    expect(health.statusLabel, '凭据失效');
  });

  test('successful verification records availability and latency', () {
    final health =
        const AiProviderHealth(providerId: 'account-2').recordVerification(
      status: 'available',
      message: '',
      latencyMs: 240,
      now: 1735689600000,
    );

    expect(health.verificationStatus, 'available');
    expect(health.statusLabel, '可用');
    expect(health.successCount, 1);
    expect(health.averageLatencyMs, 240);
    expect(health.lastError, isEmpty);
  });
}
