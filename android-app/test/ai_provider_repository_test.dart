import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/ai_account_json.dart';
import 'package:qingji/core/ai/chat_session.dart';
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
      baseUrl: 'https://claude.example/v1',
      apiKey: 'key-a',
      models: const ['shared-model', 'claude-sonnet'],
      model: 'shared-model',
    );
    final second = await repo.addAiConfiguredProvider(
      displayName: 'OpenAI Gateway',
      baseUrl: 'https://openai.example/v1',
      apiKey: 'key-b',
      models: const ['shared-model', 'gpt-5'],
      model: 'shared-model',
    );

    await repo.saveChatModelSelection(
      providerId: second.id,
      model: 'shared-model',
      reasoningEffort: AiReasoningEffort.high,
    );
    await repo.setAiPrivacyAccepted(
      true,
      forConfig: repo.aiProviderConfigFor(AiTaskType.chatQuery),
    );
    expect(repo.aiPrivacyAccepted, isTrue);
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

  test('Chats tool access and web search are global, not provider settings',
      () async {
    final repo = AppRepository();
    await repo.init();
    expect(repo.chatToolAccess, AiChatToolAccess.auto);

    await repo.setChatWebSearchEnabled(true);
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).webSearchEnabled,
        isTrue);
    final session = await repo.createChatSession(title: '工具权限');
    expect(
      repo.aiProviderConfigForChatSession(session.id).webSearchEnabled,
      isTrue,
    );

    // The Chats preference remains on, but an explicitly disabled connector
    // must prevent the request layer from attaching search tools or the local
    // search adapter.
    await repo.setAiConnectorEnabled('web_search', false);
    expect(repo.chatWebSearchEnabled, isTrue);
    expect(repo.chatWebSearchAllowed, isFalse);
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).webSearchEnabled,
        isFalse);
    await repo.setAiConnectorEnabled('web_search', true);
    expect(repo.chatWebSearchAllowed, isTrue);

    await repo.setChatToolAccess(AiChatToolAccess.onDemand);
    expect(repo.chatToolAccess, AiChatToolAccess.onDemand);
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).webSearchEnabled,
        isTrue);
    expect(
      repo.aiProviderConfigForChatSession(session.id).webSearchEnabled,
      isTrue,
    );
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.chatToolAccess, AiChatToolAccess.onDemand);
    expect(
      reopened.aiProviderConfigFor(AiTaskType.chatQuery).webSearchEnabled,
      isTrue,
    );
    await reopened.closeForTest();
  });

  test('skill switches are persisted and expose only their declared tools',
      () async {
    final repo = AppRepository();
    await repo.init();
    expect(
      repo.aiSkillAllowsTool('ledger_assistant', 'create_transactions'),
      isTrue,
    );
    expect(
      repo.aiSkillAllowsTool('ledger_assistant', 'read_statistics'),
      isFalse,
    );
    await repo.setAiSkillEnabled('ledger_assistant', false);
    expect(
      repo.aiSkillAllowsTool('ledger_assistant', 'create_transactions'),
      isFalse,
    );
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.aiSkillEnabled('ledger_assistant'), isFalse);
    expect(
      reopened.aiSkillAllowsTool('ledger_assistant', 'create_transactions'),
      isFalse,
    );
    await reopened.closeForTest();
  });

  test('configured current model remains selectable when catalog is empty',
      () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Catalog Offline',
      baseUrl: 'https://catalog.example/v1',
      apiKey: 'catalog-key',
      model: 'saved-model',
    );

    expect(
      repo.aiChatModelOptions
          .where((option) => option.providerId == provider.id)
          .map((option) => option.model),
      contains('saved-model'),
    );
    await repo.saveAiProviderModels(provider.id, const []);
    expect(
      repo.aiChatModelOptions
          .where((option) => option.providerId == provider.id)
          .map((option) => option.model),
      contains('saved-model'),
    );
    await repo.closeForTest();
  });

  test('custom provider cannot promote itself to built in', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Temporary Gateway',
      baseUrl: 'https://temporary.example/v1',
      apiKey: 'temporary-key',
    );
    await repo.saveAiConfiguredProvider(provider.copyWith(builtIn: true));
    expect(repo.aiProviderById(provider.id)!.builtIn, isFalse);
    await repo.deleteAiConfiguredProvider(provider.id);
    expect(repo.aiProviderById(provider.id), isNull);
    await repo.closeForTest();
  });

  test('privacy consent is scoped to the actual provider, not the model',
      () async {
    final repo = AppRepository();
    await repo.init();
    final first = await repo.addAiConfiguredProvider(
      displayName: 'Record Gateway',
      baseUrl: 'https://record.example/v1',
      apiKey: 'record-key',
      model: 'record-model',
    );
    final second = await repo.addAiConfiguredProvider(
      displayName: 'Second Gateway',
      baseUrl: 'https://second.example/v1',
      apiKey: 'second-key',
      model: 'second-model',
    );
    await repo.saveChatModelSelection(
      providerId: first.id,
      model: 'record-model',
      reasoningEffort: AiReasoningEffort.high,
    );
    final firstConfig = repo.aiProviderConfigFor(AiTaskType.chatQuery);
    await repo.setAiPrivacyAccepted(true, forConfig: firstConfig);
    expect(repo.aiPrivacyAccepted, isTrue);

    await repo.saveChatModelSelection(
      providerId: first.id,
      model: 'record-model',
      reasoningEffort: AiReasoningEffort.low,
    );
    expect(repo.aiPrivacyAccepted, isTrue);

    await repo.saveChatModelSelection(
      providerId: second.id,
      model: 'second-model',
      reasoningEffort: AiReasoningEffort.low,
    );
    expect(repo.aiPrivacyAccepted, isFalse);
    await repo.setAiPrivacyAccepted(
      true,
      forConfig: repo.aiProviderConfigFor(AiTaskType.chatQuery),
    );
    expect(repo.aiPrivacyAccepted, isTrue);
    await repo.closeForTest();
  });

  test('metadata never exposes provider secrets in app settings', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      baseUrl: 'https://secret.example/v1',
      model: 'secret-model',
      apiKey: 'secret-value',
    );
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

  test('clearing the active provider key falls back to another usable provider',
      () async {
    final repo = AppRepository();
    await repo.init();
    final first = await repo.addAiConfiguredProvider(
      displayName: 'Primary',
      baseUrl: 'https://primary.example/v1',
      apiKey: 'primary-key',
      model: 'primary-model',
    );
    final second = await repo.addAiConfiguredProvider(
      displayName: 'Fallback',
      baseUrl: 'https://fallback.example/v1',
      apiKey: 'fallback-key',
      model: 'fallback-model',
    );
    await repo.saveChatModelSelection(
      providerId: first.id,
      model: 'primary-model',
      reasoningEffort: AiReasoningEffort.none,
    );

    await repo.saveAiConfiguredProvider(first.copyWith(apiKey: ''));

    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).providerLabel,
        second.label);
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).hasKey, isTrue);
    await repo.closeForTest();
  });

  test('clearing or deleting a provider rebinds its Chats sessions', () async {
    final repo = AppRepository();
    await repo.init();
    final first = await repo.addAiConfiguredProvider(
      displayName: 'Session Primary',
      baseUrl: 'https://session-primary.example/v1',
      apiKey: 'primary-key',
      model: 'primary-model',
    );
    final fallback = await repo.addAiConfiguredProvider(
      displayName: 'Session Fallback',
      baseUrl: 'https://session-fallback.example/v1',
      apiKey: 'fallback-key',
      model: 'fallback-model',
    );
    final session = await repo.createChatSession(title: '独立会话');
    await repo.saveChatSessionSelection(
      sessionId: session.id,
      providerId: first.id,
      model: 'primary-model',
      effort: AiReasoningEffort.high,
    );

    await repo.saveAiConfiguredProvider(first.copyWith(apiKey: ''));
    var restored = repo.chatSessionById(session.id)!;
    expect(restored.providerId, fallback.id);
    expect(restored.model, 'fallback-model');
    expect(restored.effort, AiReasoningEffort.high);

    await repo.saveChatSessionSelection(
      sessionId: session.id,
      providerId: fallback.id,
      model: 'fallback-model',
      effort: AiReasoningEffort.medium,
    );
    await repo.deleteAiConfiguredProvider(fallback.id);
    restored = repo.chatSessionById(session.id)!;
    expect(restored.providerId, isNot(fallback.id));
    expect(restored.model, isNot('fallback-model'));
    expect(restored.effort, AiReasoningEffort.medium);
    await repo.closeForTest();
  });

  test(
      'removing a provider model repairs every Chat session to the new catalog',
      () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Catalog Gateway',
      baseUrl: 'https://catalog.example/v1',
      apiKey: 'catalog-key',
      model: 'model-a',
      models: const ['model-a', 'model-b'],
    );
    final first = await repo.createChatSession(title: '会话一');
    final second = await repo.createChatSession(title: '会话二');
    await repo.saveChatSessionSelection(
      sessionId: first.id,
      providerId: provider.id,
      model: 'model-b',
      effort: AiReasoningEffort.high,
    );
    await repo.saveChatSessionSelection(
      sessionId: second.id,
      providerId: provider.id,
      model: 'model-b',
      effort: AiReasoningEffort.medium,
    );

    await repo.saveAiProviderModels(
      provider.id,
      const ['model-a'],
      selectedModel: 'model-a',
    );

    expect(repo.chatSessionById(first.id)!.model, 'model-a');
    expect(repo.chatSessionById(first.id)!.effort, AiReasoningEffort.high);
    expect(repo.chatSessionById(second.id)!.model, 'model-a');
    expect(repo.chatSessionById(second.id)!.effort, AiReasoningEffort.medium);
    expect(
      repo.aiProviderConfigForChatSession(first.id).model,
      'model-a',
    );

    await repo.closeForTest();
    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.chatSessionById(first.id)!.model, 'model-a');
    expect(reopened.chatSessionById(second.id)!.model, 'model-a');
    expect(
      reopened.aiProviderConfigForChatSession(second.id).model,
      'model-a',
    );
    await reopened.closeForTest();
  });

  test('adding the first keyed provider immediately selects its model',
      () async {
    final repo = AppRepository();
    await repo.init();
    final deepseek = repo.aiProviderById('deepseek')!;
    await repo.saveAiConfiguredProvider(deepseek.copyWith(apiKey: ''));

    final gateway = await repo.addAiConfiguredProvider(
      displayName: 'Only Gateway',
      baseUrl: 'https://only.example/v1',
      apiKey: 'gateway-key',
      model: 'gateway-chat',
      models: const ['gateway-chat', 'gateway-fast'],
    );

    expect(repo.chatCurrentProviderId, gateway.id);
    final config = repo.aiProviderConfigFor(AiTaskType.chatQuery);
    expect(config.providerLabel, gateway.label);
    expect(config.model, 'gateway-chat');
    expect(config.model, isNot('deepseek-v4-flash'));
    await repo.closeForTest();
  });

  test('editing provider metadata never resets consent implicitly', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Gateway',
      apiKey: 'gateway-key',
      baseUrl: 'https://gateway.example/v1',
      model: 'gateway-model',
      models: const ['gateway-model'],
    );
    await repo.saveChatModelSelection(
      providerId: provider.id,
      model: provider.model,
      reasoningEffort: AiReasoningEffort.low,
    );
    await repo.setAiPrivacyAccepted(true);

    await repo.saveAiConfiguredProvider(
      provider.copyWith(displayName: 'Renamed'),
    );
    expect(repo.aiPrivacyAccepted, isTrue);

    await repo.saveAiConfiguredProvider(
      provider.copyWith(baseUrl: 'https://other.example/v1'),
    );
    expect(repo.aiPrivacyAccepted, isFalse);
    await repo.setAiPrivacyAccepted(false);
    expect(repo.aiPrivacyAccepted, isFalse);
    await repo.closeForTest();
  });

  test('provider enabled switch persists and active Chats falls back',
      () async {
    final repo = AppRepository();
    await repo.init();
    final first = await repo.addAiConfiguredProvider(
      displayName: 'Primary',
      baseUrl: 'https://primary.example/v1',
      apiKey: 'primary-key',
      model: 'primary-model',
    );
    final second = await repo.addAiConfiguredProvider(
      displayName: 'Fallback',
      baseUrl: 'https://fallback.example/v1',
      apiKey: 'fallback-key',
      model: 'fallback-model',
    );
    await repo.saveChatModelSelection(
      providerId: first.id,
      model: first.model,
    );

    await repo.setAiConfiguredProviderEnabled(first.id, false);
    expect(repo.aiProviderById(first.id)!.enabled, isFalse);
    expect(repo.aiProviderById(first.id)!.hasKey, isTrue);
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).providerLabel,
        second.label);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.aiProviderById(first.id)!.enabled, isFalse);
    expect(reopened.aiProviderById(first.id)!.hasKey, isTrue);
    await reopened.setAiConfiguredProviderEnabled(first.id, true);
    expect(reopened.aiProviderById(first.id)!.enabled, isTrue);
    await reopened.closeForTest();
  });

  test('new custom provider starts with empty placeholder fields', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider();
    expect(provider.displayName, isEmpty);
    expect(provider.baseUrl, isEmpty);
    expect(provider.model, isEmpty);
    await repo.closeForTest();
  });

  test('a keyed custom provider without address or model stays incomplete',
      () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(apiKey: 'key-only');

    expect(provider.hasCredential, isTrue);
    expect(provider.isUsable, isFalse);
    expect(
      repo.aiChatModelOptions.where(
        (option) => option.providerId == provider.id,
      ),
      isEmpty,
    );
    expect(repo.aiProviderConfigFor(AiTaskType.chatQuery).providerLabel,
        'DeepSeek');
    await repo.closeForTest();
  });

  test('imports Cockpit OAuth account, updates duplicate, and exports it',
      () async {
    final repo = AppRepository();
    await repo.init();
    final entry = AiAccountJsonCodec.parse('''
      {
        "type": "codex",
        "email": "json@example.com",
        "account_id": "acct-json",
        "access_token": "access-json",
        "refresh_token": "refresh-json",
        "id_token": "id-json"
      }
    ''').accounts.single;
    final imported = await repo.importAiAccount(entry);
    expect(imported.authMethod, AiAuthMethod.oauth);
    expect(imported.oauthAccountId, 'acct-json');
    expect(imported.isUsable, isTrue);
    expect(repo.matchingAiProvider(entry)!.id, imported.id);
    expect(repo.exportAiAccountsJson(), contains('refresh-json'));

    final updatedEntry = AiAccountJsonCodec.parse('''
      {
        "type": "codex",
        "email": "json@example.com",
        "account_id": "acct-json",
        "access_token": "access-json-new",
        "refresh_token": "refresh-json-new",
        "id_token": "id-json-new"
      }
    ''').accounts.single;
    final updated = await repo.importAiAccount(
      updatedEntry,
      existingProviderId: imported.id,
    );
    expect(updated.id, imported.id);
    expect(updated.apiKey, 'access-json-new');
    expect(updated.oauthRefreshToken, 'refresh-json-new');
    expect(updated.oauthIdToken, 'id-json-new');
    await repo.closeForTest();
  });

  test('refresh-only Cockpit OAuth import remains selectable before refresh',
      () async {
    final repo = AppRepository();
    await repo.init();
    final entry = AiAccountJsonCodec.parse('''
      {
        "type": "codex",
        "email": "refresh-only@example.com",
        "account_id": "acct-refresh-only",
        "refresh_token": "refresh-only-token"
      }
    ''').accounts.single;

    final imported = await repo.importAiAccount(entry);
    expect(imported.authMethod, AiAuthMethod.oauth);
    expect(imported.apiKey, isEmpty);
    expect(imported.oauthRefreshToken, 'refresh-only-token');
    expect(imported.hasCredential, isTrue);
    expect(imported.isUsable, isTrue);
    expect(
      repo.aiProviderConfigFor(AiTaskType.chatQuery).hasCredential,
      isTrue,
    );
    await repo.closeForTest();
  });

  test('normal recording provider model and effort save and restore together',
      () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Record Models',
      baseUrl: 'https://record-models.example/v1',
      apiKey: 'record-key',
      model: 'record-fast',
      models: const ['record-fast', 'record-smart'],
    );

    await repo.saveRecordAiSelection(
      providerId: provider.id,
      model: 'record-smart',
      reasoningEffort: AiReasoningEffort.xhigh,
    );
    expect(repo.recordAiProviderId, provider.id);
    expect(repo.recordAiModel, 'record-smart');
    expect(
      repo.aiProviderConfigFor(AiTaskType.recordParse).model,
      'record-smart',
    );
    expect(
      repo.aiProviderConfigFor(AiTaskType.recordParse).reasoningEffort,
      AiReasoningEffort.xhigh,
    );

    final db = await databaseFactory.openDatabase(
      p.join(temp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final rows = await db.query(
      'app_settings',
      columns: const ['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const [
        'ai_record_provider_id',
        'ai_record_model',
        'ai_record_reasoning_effort',
      ],
    );
    final settings = {
      for (final row in rows) row['key']: row['value'],
    };
    expect(settings['ai_record_provider_id'], provider.id);
    expect(settings['ai_record_model'], 'record-smart');
    expect(settings['ai_record_reasoning_effort'], 'xhigh');
    await db.close();
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.recordAiProviderId, provider.id);
    expect(reopened.recordAiModel, 'record-smart');
    expect(
      reopened.aiProviderConfigFor(AiTaskType.recordParse).model,
      'record-smart',
    );
    expect(
      reopened.aiReasoningEffortFor(AiTaskType.recordParse),
      AiReasoningEffort.xhigh,
    );
    await reopened.closeForTest();
  });

  test('legacy normal recording selection falls back to provider primary model',
      () async {
    final repo = AppRepository();
    await repo.init();
    final provider = await repo.addAiConfiguredProvider(
      displayName: 'Legacy Record',
      baseUrl: 'https://legacy-record.example/v1',
      apiKey: 'legacy-record-key',
      model: 'legacy-primary',
      models: const ['legacy-primary', 'legacy-other'],
    );
    await repo.setRecordAiProvider(provider.id);
    await repo.closeForTest();

    final db = await databaseFactory.openDatabase(
      p.join(temp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: const ['ai_record_model'],
    );
    await db.close();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.recordAiProviderId, provider.id);
    expect(reopened.recordAiModel, 'legacy-primary');
    expect(
      reopened.aiProviderConfigFor(AiTaskType.recordParse).model,
      'legacy-primary',
    );
    await reopened.closeForTest();
  });

  test('normal recording selection validates and repairs catalogue mutations',
      () async {
    final repo = AppRepository();
    await repo.init();
    final primary = await repo.addAiConfiguredProvider(
      displayName: 'Record Primary',
      baseUrl: 'https://record-primary.example/v1',
      apiKey: 'primary-key',
      model: 'model-a',
      models: const ['model-a', 'model-b'],
    );
    final fallback = await repo.addAiConfiguredProvider(
      displayName: 'Record Fallback',
      baseUrl: 'https://record-fallback.example/v1',
      apiKey: 'fallback-key',
      model: 'fallback-model',
    );
    await repo.saveRecordAiSelection(
      providerId: primary.id,
      model: 'model-b',
      reasoningEffort: AiReasoningEffort.high,
    );

    await expectLater(
      repo.saveRecordAiSelection(
        providerId: primary.id,
        model: 'missing-model',
        reasoningEffort: AiReasoningEffort.low,
      ),
      throwsStateError,
    );
    expect(repo.recordAiProviderId, primary.id);
    expect(repo.recordAiModel, 'model-b');
    expect(
      repo.aiReasoningEffortFor(AiTaskType.recordParse),
      AiReasoningEffort.high,
    );

    await repo.saveAiProviderModels(
      primary.id,
      const ['model-a'],
      selectedModel: 'model-a',
    );
    expect(repo.recordAiProviderId, primary.id);
    expect(repo.recordAiModel, 'model-a');

    await repo.setAiConfiguredProviderEnabled(primary.id, false);
    expect(repo.recordAiProviderId, fallback.id);
    expect(repo.recordAiModel, 'fallback-model');
    expect(
      repo.aiReasoningEffortFor(AiTaskType.recordParse),
      AiReasoningEffort.high,
    );

    await repo.setAiConfiguredProviderEnabled(primary.id, true);
    await repo.saveRecordAiSelection(
      providerId: primary.id,
      model: 'model-a',
      reasoningEffort: AiReasoningEffort.medium,
    );
    await repo.deleteAiConfiguredProvider(primary.id);
    expect(repo.recordAiProviderId, fallback.id);
    expect(repo.recordAiModel, 'fallback-model');
    expect(
      repo.aiReasoningEffortFor(AiTaskType.recordParse),
      AiReasoningEffort.medium,
    );
    await repo.closeForTest();
  });

  test('stale OAuth refresh cannot overwrite a newer credential', () async {
    final repo = AppRepository();
    await repo.init();
    final provider = AiConfiguredProvider(
      id: 'oauth-cas',
      type: AiProviderType.custom,
      displayName: 'GPT OAuth',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      apiKey: 'new-access',
      model: 'gpt-5',
      models: const ['gpt-5'],
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-cas',
      oauthRefreshToken: 'new-refresh',
    );
    await repo.saveAiConfiguredProvider(provider);

    // Simulate a refresh that began before a newer OAuth authorization. The
    // compare-and-set precondition must reject the stale result.
    await repo.saveAiConfiguredProvider(
      provider.copyWith(
        apiKey: 'stale-access',
        oauthRefreshToken: 'stale-refresh',
      ),
      expectedAccessToken: 'old-access',
      expectedRefreshToken: 'old-refresh',
    );

    final current = repo.aiProviderById(provider.id)!;
    expect(current.apiKey, 'new-access');
    expect(current.oauthRefreshToken, 'new-refresh');
    await repo.closeForTest();
  });
}
