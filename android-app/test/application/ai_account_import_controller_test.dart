import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/application/ai_account_import_controller.dart';
import 'package:qingji/core/ai/ai_account_json.dart';
import 'package:qingji/core/ai/ai_account_verification.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';

void main() {
  AiAccountImportEntry account(
    String email, {
    String apiKey = 'key',
    bool enabled = true,
  }) =>
      AiAccountImportEntry(
        source: AiAccountJsonSource.cockpit,
        displayName: email.split('@').first,
        accountEmail: email,
        apiKey: apiKey,
        baseUrl: 'https://gateway.example/v1',
        model: 'seed-model',
        enabled: enabled,
      );

  AiAccountImportRequest request(
    AiAccountImportEntry entry, {
    AiAccountImportAction action = AiAccountImportAction.create,
  }) =>
      AiAccountImportRequest(
        account: entry,
        action: action,
        enabled: entry.enabled,
      );

  test('one account import failure does not stop other accounts', () async {
    final repository = _FakeImportRepository(
      throwOnEmails: {'bad@example.com'},
    );
    final controller = AiAccountImportController(
      verifier: (config) async {
        expect(config.hasCredential, isTrue);
        return const AiAccountVerificationResult(
          status: AiAccountVerificationStatus.available,
          models: ['discovered-model', 'backup-model'],
          latencyMs: 12,
        );
      },
    );

    final result = await controller.import(repository, [
      request(account('bad@example.com')),
      request(account('good@example.com')),
    ]);

    expect(result.imported, 1);
    expect(result.failed, 1);
    expect(result.verificationCounts[
        AiAccountVerificationStatus.available], 1);
    expect(repository.beginCalls, 1);
    expect(repository.commitCalls, 1);
    expect(repository.rollbackCalls, 0);
    expect(repository.providers, hasLength(1));
    expect(repository.providers.values.single.accountEmail, 'good@example.com');
    expect(repository.providers.values.single.model, 'discovered-model');
    expect(repository.verifications, contains('provider-0'));
  });

  test('verifier exception is recorded for one account and later account runs',
      () async {
    final repository = _FakeImportRepository();
    final controller = AiAccountImportController(
      verifier: (config) async {
        if (config.providerId == 'provider-0') {
          throw StateError('temporary verifier failure');
        }
        return const AiAccountVerificationResult(
          status: AiAccountVerificationStatus.available,
          models: ['second-model'],
        );
      },
    );

    final result = await controller.import(repository, [
      request(account('first@example.com')),
      request(account('second@example.com')),
    ]);

    expect(result.imported, 2);
    expect(result.failed, 1);
    expect(result.issues.single.message, contains('验证失败'));
    expect(result.verificationCounts[
        AiAccountVerificationStatus.networkError], 1);
    expect(result.verificationCounts[
        AiAccountVerificationStatus.available], 1);
    expect(repository.verifications, contains('provider-0'));
    expect(repository.verifications, contains('provider-1'));
    expect(repository.providers['provider-1']!.model, 'second-model');
  });

  test('final batch commit failure rolls back all imported accounts', () async {
    final repository = _FakeImportRepository(failCommit: true);
    final controller = AiAccountImportController(
      verifier: (_) async => const AiAccountVerificationResult(
        status: AiAccountVerificationStatus.available,
        models: ['available-model'],
      ),
    );

    await expectLater(
      controller.import(repository, [
        request(account('first@example.com')),
        request(account('second@example.com')),
      ]),
      throwsA(isA<StateError>()),
    );

    expect(repository.beginCalls, 1);
    expect(repository.commitCalls, 1);
    expect(repository.rollbackCalls, 1);
    expect(repository.providers, isEmpty);
  });
}

class _FakeImportRepository implements AiAccountImportRepository {
  final Set<String> throwOnEmails;
  final bool failCommit;
  final Map<String, AiConfiguredProvider> providers = {};
  final Map<String, AiAccountVerificationResult> verifications = {};
  Map<String, AiConfiguredProvider> _snapshot = {};
  int beginCalls = 0;
  int commitCalls = 0;
  int rollbackCalls = 0;

  _FakeImportRepository({this.throwOnEmails = const {}, this.failCommit = false});

  @override
  void beginBatch() {
    beginCalls++;
    _snapshot = Map<String, AiConfiguredProvider>.from(providers);
  }

  @override
  Future<AiConfiguredProvider> importAccount(
    AiAccountImportEntry entry, {
    String? existingProviderId,
    required bool enabled,
    required bool deferMetadata,
  }) async {
    if (throwOnEmails.contains(entry.accountEmail)) {
      throw StateError('malformed account');
    }
    final id = existingProviderId ?? 'provider-${providers.length}';
    final provider = AiConfiguredProvider(
      id: id,
      type: AiProviderType.custom,
      displayName: entry.displayName,
      baseUrl: entry.baseUrl,
      apiKey: entry.credential,
      model: entry.model,
      models: entry.models,
      enabled: enabled,
      accountEmail: entry.accountEmail,
    );
    providers[id] = provider;
    return provider;
  }

  @override
  AiProviderConfig? providerConfigFor(String providerId) {
    final provider = providers[providerId];
    return provider?.toConfig();
  }

  @override
  AiConfiguredProvider? providerById(String providerId) => providers[providerId];

  @override
  Future<void> recordVerification(
    String providerId,
    AiAccountVerificationResult result,
  ) async {
    verifications[providerId] = result;
  }

  @override
  Future<void> saveDiscoveredModels(
    AiConfiguredProvider provider,
    List<String> models, {
    required bool deferMetadata,
  }) async {
    providers[provider.id] = provider.copyWith(
      model: models.first,
      models: models,
    );
  }

  @override
  Future<void> commitBatch() async {
    commitCalls++;
    if (failCommit) throw StateError('metadata commit failed');
  }

  @override
  Future<void> rollbackBatch() async {
    rollbackCalls++;
    providers
      ..clear()
      ..addAll(_snapshot);
    verifications.clear();
  }
}
