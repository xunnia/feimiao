class AiProviderHealth {
  final String providerId;
  final int successCount;
  final int failureCount;
  final int consecutiveFailures;
  final int? lastSuccessMs;
  final int? lastFailureMs;
  final int? cooldownUntilMs;
  final int averageLatencyMs;
  final String lastError;
  final int updatedMs;

  const AiProviderHealth({
    required this.providerId,
    this.successCount = 0,
    this.failureCount = 0,
    this.consecutiveFailures = 0,
    this.lastSuccessMs,
    this.lastFailureMs,
    this.cooldownUntilMs,
    this.averageLatencyMs = 0,
    this.lastError = '',
    this.updatedMs = 0,
  });

  bool get isCoolingDown =>
      cooldownUntilMs != null &&
      cooldownUntilMs! > DateTime.now().millisecondsSinceEpoch;

  bool get hasRecentFailure =>
      lastFailureMs != null &&
      DateTime.now().millisecondsSinceEpoch - lastFailureMs! <
          const Duration(minutes: 10).inMilliseconds;

  double get successRate {
    final total = successCount + failureCount;
    return total == 0 ? 0 : successCount / total;
  }

  String get statusLabel {
    if (isCoolingDown) return '暂时冷却';
    if (hasRecentFailure) return '最近失败';
    if (successCount == 0 && failureCount == 0) return '尚未测试';
    return '可用';
  }

  Map<String, Object?> toMap() => {
        'provider_id': providerId,
        'success_count': successCount,
        'failure_count': failureCount,
        'consecutive_failures': consecutiveFailures,
        'last_success_ms': lastSuccessMs,
        'last_failure_ms': lastFailureMs,
        'cooldown_until_ms': cooldownUntilMs,
        'average_latency_ms': averageLatencyMs,
        'last_error': lastError,
        'updated_ms': updatedMs,
      };

  factory AiProviderHealth.fromMap(Map<String, Object?> map) =>
      AiProviderHealth(
        providerId: map['provider_id']?.toString() ?? '',
        successCount: (map['success_count'] as num?)?.toInt() ?? 0,
        failureCount: (map['failure_count'] as num?)?.toInt() ?? 0,
        consecutiveFailures:
            (map['consecutive_failures'] as num?)?.toInt() ?? 0,
        lastSuccessMs: (map['last_success_ms'] as num?)?.toInt(),
        lastFailureMs: (map['last_failure_ms'] as num?)?.toInt(),
        cooldownUntilMs: (map['cooldown_until_ms'] as num?)?.toInt(),
        averageLatencyMs: (map['average_latency_ms'] as num?)?.toInt() ?? 0,
        lastError: map['last_error']?.toString() ?? '',
        updatedMs: (map['updated_ms'] as num?)?.toInt() ?? 0,
      );

  AiProviderHealth recordSuccess(int latencyMs, int now) {
    final nextCount = successCount + 1;
    final nextAverage = averageLatencyMs == 0
        ? latencyMs
        : ((averageLatencyMs * successCount) + latencyMs) ~/ nextCount;
    return AiProviderHealth(
      providerId: providerId,
      successCount: nextCount,
      failureCount: failureCount,
      consecutiveFailures: 0,
      lastSuccessMs: now,
      lastFailureMs: lastFailureMs,
      cooldownUntilMs: null,
      averageLatencyMs: nextAverage,
      lastError: '',
      updatedMs: now,
    );
  }

  AiProviderHealth recordFailure(String error, int now) {
    final failures = consecutiveFailures + 1;
    final cooldown =
        failures >= 3 ? now + const Duration(minutes: 2).inMilliseconds : null;
    return AiProviderHealth(
      providerId: providerId,
      successCount: successCount,
      failureCount: failureCount + 1,
      consecutiveFailures: failures,
      lastSuccessMs: lastSuccessMs,
      lastFailureMs: now,
      cooldownUntilMs: cooldown,
      averageLatencyMs: averageLatencyMs,
      lastError: error.length > 240 ? error.substring(0, 240) : error,
      updatedMs: now,
    );
  }
}
