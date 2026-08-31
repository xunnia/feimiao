import '../core/ai/ai_account_json.dart';
import '../core/ai/ai_account_verification.dart';
import '../core/ai/ai_logger.dart';
import '../core/ai/ai_provider_config.dart';
import '../data/app_repository.dart';

enum AiAccountImportAction { create, update, skip }

class AiAccountImportRequest {
  final AiAccountImportEntry account;
  final AiAccountImportAction action;
  final String? existingProviderId;
  final bool enabled;

  const AiAccountImportRequest({
    required this.account,
    required this.action,
    required this.enabled,
    this.existingProviderId,
  });
}

class AiAccountImportIssue {
  final String identity;
  final String message;

  const AiAccountImportIssue({
    required this.identity,
    required this.message,
  });

  String get summary => identity.trim().isEmpty ? message : '$identity：$message';
}

class AiAccountImportBatchResult {
  final int imported;
  final int skipped;
  final int verificationSkipped;
  final Map<AiAccountVerificationStatus, int> verificationCounts;
  final List<AiAccountImportIssue> issues;

  const AiAccountImportBatchResult({
    required this.imported,
    required this.skipped,
    required this.verificationSkipped,
    required this.verificationCounts,
    required this.issues,
  });

  int get failed => issues.length;
}

typedef AiAccountVerifier = Future<AiAccountVerificationResult> Function(
  AiProviderConfig config,
);

/// Narrow account-import boundary used by the application use case.
///
/// Keeping this port smaller than [AppRepository] prevents the settings page
/// and tests from depending on the ledger/database surface.
abstract class AiAccountImportRepository {
  void beginBatch();

  Future<AiConfiguredProvider> importAccount(
    AiAccountImportEntry entry, {
    String? existingProviderId,
    required bool enabled,
    required bool deferMetadata,
  });

  AiProviderConfig? providerConfigFor(String providerId);

  AiConfiguredProvider? providerById(String providerId);

  Future<void> recordVerification(
    String providerId,
    AiAccountVerificationResult result,
  );

  Future<void> saveDiscoveredModels(
    AiConfiguredProvider provider,
    List<String> models, {
    required bool deferMetadata,
  });

  Future<void> commitBatch();

  Future<void> rollbackBatch();
}

/// Compatibility adapter while AI account persistence is progressively moved
/// out of the monolithic repository.
class AppRepositoryAiAccountImportAdapter
    implements AiAccountImportRepository {
  final AppRepository repository;

  const AppRepositoryAiAccountImportAdapter(this.repository);

  @override
  void beginBatch() => repository.beginAiAccountImportBatch();

  @override
  Future<AiConfiguredProvider> importAccount(
    AiAccountImportEntry entry, {
    String? existingProviderId,
    required bool enabled,
    required bool deferMetadata,
  }) async =>
      repository.importAiAccount(
        entry,
        existingProviderId: existingProviderId,
        enabledOverride: enabled,
        persistMetadata: !deferMetadata,
        notify: !deferMetadata,
      );

  @override
  AiProviderConfig? providerConfigFor(String providerId) =>
      repository.aiProviderConfigForProvider(providerId);

  @override
  AiConfiguredProvider? providerById(String providerId) =>
      repository.aiProviderById(providerId);

  @override
  Future<void> recordVerification(
    String providerId,
    AiAccountVerificationResult result,
  ) =>
      repository.recordAiProviderVerification(
        providerId,
        status: result.status.name,
        message: result.message,
        latencyMs: result.latencyMs,
      );

  @override
  Future<void> saveDiscoveredModels(
    AiConfiguredProvider provider,
    List<String> models, {
    required bool deferMetadata,
  }) =>
      repository.saveAiConfiguredProvider(
        provider.copyWith(model: models.first, models: models),
        persistMetadata: !deferMetadata,
        notify: !deferMetadata,
      );

  @override
  Future<void> commitBatch() => repository.commitAiAccountImportBatch();

  @override
  Future<void> rollbackBatch() => repository.rollbackAiAccountImportBatch();
}

/// Application-level use case for importing portable AI accounts.
///
/// The settings page owns only preview/user choices. This controller owns the
/// batch lifecycle, per-account isolation, model discovery, minimal probe and
/// final metadata commit. Credentials remain in the repository's secure-store
/// boundary; network details remain in [AiAccountVerificationService].
class AiAccountImportController {
  final AiAccountVerifier _verify;

  AiAccountImportController({AiAccountVerifier? verifier})
      : _verify = verifier ?? const AiAccountVerificationService().verify;

  Future<AiAccountImportBatchResult> import(
    AiAccountImportRepository repository,
    List<AiAccountImportRequest> requests,
  ) async {
    final active = requests
        .where((request) => request.action != AiAccountImportAction.skip)
        .toList(growable: false);
    final batched = active.length > 1;
    if (batched) repository.beginBatch();

    var imported = 0;
    var skipped = 0;
    var verificationSkipped = 0;
    final counts = <AiAccountVerificationStatus, int>{};
    final issues = <AiAccountImportIssue>[];

    try {
      for (final request in requests) {
        if (request.action == AiAccountImportAction.skip) {
          skipped++;
          continue;
        }

        late final AiConfiguredProvider saved;
        try {
          saved = await repository.importAccount(
            request.account,
            existingProviderId:
                request.action == AiAccountImportAction.update
                    ? request.existingProviderId
                    : null,
            enabled: request.enabled,
            deferMetadata: batched,
          );
          imported++;
        } catch (error) {
          issues.add(_issue(request.account, error));
          continue;
        }

        if (!request.enabled) {
          verificationSkipped++;
          continue;
        }
        final config = repository.providerConfigFor(saved.id);
        if (config == null) {
          const result = AiAccountVerificationResult(
            status: AiAccountVerificationStatus.configurationError,
            message: '账号已保存，但无法建立验证配置',
          );
          counts.update(
            result.status,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          issues.add(
            AiAccountImportIssue(
              identity: request.account.maskedIdentity,
              message: result.message,
            ),
          );
          await _recordVerificationBestEffort(repository, saved.id, result);
          continue;
        }

        late final AiAccountVerificationResult verification;
        try {
          verification = await _verify(config);
        } catch (error) {
          final message = _safeError(error);
          verification = AiAccountVerificationResult(
            status: AiAccountVerificationStatus.networkError,
            message: message,
          );
          issues.add(
            AiAccountImportIssue(
              identity: request.account.maskedIdentity,
              message: '验证失败：$message',
            ),
          );
        }
        counts.update(
          verification.status,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        await _recordVerificationBestEffort(
          repository,
          saved.id,
          verification,
        );

        if (verification.models.isNotEmpty) {
          try {
            final latest = repository.providerById(saved.id) ?? saved;
            await repository.saveDiscoveredModels(
              latest,
              verification.models,
              deferMetadata: batched,
            );
          } catch (error) {
            issues.add(_issue(request.account, error));
          }
        }
      }

      if (batched) await repository.commitBatch();
      return AiAccountImportBatchResult(
        imported: imported,
        skipped: skipped,
        verificationSkipped: verificationSkipped,
        verificationCounts: Map.unmodifiable(counts),
        issues: List.unmodifiable(issues),
      );
    } catch (_) {
      if (batched) {
        try {
          await repository.rollbackBatch();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> _recordVerificationBestEffort(
    AiAccountImportRepository repository,
    String providerId,
    AiAccountVerificationResult result,
  ) async {
    try {
      await repository.recordVerification(providerId, result);
    } catch (_) {
      // Diagnostic persistence must not invalidate a securely saved account.
      // The user can rerun verification for this account from settings.
    }
  }

  static AiAccountImportIssue _issue(
    AiAccountImportEntry account,
    Object error,
  ) {
    return AiAccountImportIssue(
      identity: account.maskedIdentity,
      message: _safeError(error),
    );
  }

  static String _safeError(Object error) {
    final raw = AiLogger.sanitizeErrorForDisplay(error.toString())
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (raw.isEmpty) return '未知错误';
    return raw.length <= 120 ? raw : '${raw.substring(0, 117)}…';
  }
}
