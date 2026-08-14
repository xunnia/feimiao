import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qingji_ai_provider_');
    await databaseFactory.setDatabasesPath(temp.path);
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  test('provider model selection survives restart and deletion falls back',
      () async {
    final repo = AppRepository();
    await repo.init();
    final first = await repo.addAiConfiguredProvider(
      displayName: 'Claude Gateway',
      apiKey: 'key-a',
      models: const ['shared-model', 'claude-sonnet'],
      model: 'shared-model',
    );
    final second = await repo.addAiConfiguredProvider(
      displayName: 'OpenAI Gateway',
      apiKey: 'key-b',
      models: const ['shared-model', 'gpt-5'],
      model: 'shared-model',
    );

    await repo.setAiPrivacyAccepted(true);
    await repo.saveChatModelSelection(
      providerId: second.id,
      model: 'shared-model',
      reasoningEffort: AiReasoningEffort.high,
    );
    expect(repo.aiPrivacyAccepted, isFalse);
    await repo.setAiPrivacyAccepted(true);
    await repo.saveChatModelSelection(
      providerId: second.id,
      model: 'gpt-5',
      reasoningEffort: AiReasoningEffort.high,
    );
    expect(repo.aiPrivacyAccepted, isTrue);
    await repo.saveChatModelSelection(
      providerId: second.id,
      model: 'shared-model',
      reasoningEffort: AiReasoningEffort.high,
    );
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).providerLabel,
        second.label);
    expect(
        repo.aiProviderConfigFor(AiTaskType.chatQuery).model, 'shared-model');
    expect(
        repo.aiChatModelOptions.where((item) => item.model == 'shared-model'),
        hasLength(2));
    expect(
      repo.aiChatModelOptions.any((item) => item.providerId == 'deepseek'),
      isFalse,
    );
    expect(
      repo.aiProviderConfigFor(AiTaskType.report).reasoningEffort,
      AiReasoningEffort.high,
    );
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.chatCurrentProviderId, second.id);
    expect(reopened.chatCurrentModel, 'shared-model');
    expect(reopened.aiProviderConfigFor(AiTaskType.report).providerLabel,
        second.label);

    await reopened.deleteAiConfiguredProvider(second.id);
    expect(reopened.chatCurrentProviderId, isNot(second.id));
    expect(reopened.aiProviderConfigFor(AiTaskType.chatQuery).providerLabel,
        isNot(second.label));
    expect(reopened.aiProviderById(first.id), isNotNull);
    expect(reopened.aiProviderById('deepseek'), isNotNull);
    await reopened.closeForTest();
  });

  test('deepseek remains built in and cannot be deleted', () async {
    final repo = AppRepository();
    await repo.init();
    final deepseek = repo.aiProviderById('deepseek');
    expect(deepseek, isNotNull);
    expect(deepseek!.builtIn, isTrue);
    await expectLater(
      repo.deleteAiConfiguredProvider('deepseek'),
      throwsStateError,
    );
    await repo.closeForTest();
  });

  test('custom provider cannot promote itself to built in', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Temporary Gateway',
      apiKey: 'temporary-key',
    );
    await repo.saveAiConfiguredProvider(provider.copyWith(builtIn: true));
    expect(repo.aiProviderById(provider.id)!.builtIn, isFalse);
    await repo.deleteAiConfiguredProvider(provider.id);
    expect(repo.aiProviderById(provider.id), isNull);
    await repo.closeForTest();
  });

  test('changing the record provider resets privacy consent', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Record Gateway',
      apiKey: 'record-key',
    );
    await repo.setAiPrivacyAccepted(true);
    await repo.setRecordAiProvider(provider.id);
    expect(repo.aiPrivacyAccepted, isFalse);
    await repo.setAiPrivacyAccepted(true);
    await repo.setRecordAiProvider(provider.id);
    expect(repo.aiPrivacyAccepted, isTrue);
    await repo.closeForTest();
  });

  test('metadata never exposes provider secrets in app settings', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(apiKey: 'secret-value');
    final db = await databaseFactory.openDatabase(
      p.join(temp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: const ['ai_providers_json'],
    );
    expect(rows.single['value'], isNot(contains('secret-value')));
    expect(repo.aiProviderById(provider.id)!.hasKey, isTrue);
    await db.close();
    await repo.closeForTest();
  });
}
