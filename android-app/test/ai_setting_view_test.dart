import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/settings/ai_setting_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screenshot_font_support.dart';

class _SettingsRepository extends AppRepository {
  _SettingsRepository(Iterable<AiConfiguredProvider> providers)
      : _providers = List<AiConfiguredProvider>.from(providers) {
    final selected =
        _providers.where((provider) => provider.isUsable).firstOrNull;
    selectedRecordProviderId = selected?.id;
    selectedRecordModel = selected?.model;
  }

  final List<AiConfiguredProvider> _providers;
  String? selectedRecordProviderId;
  String? selectedRecordModel;
  AiReasoningEffort selectedRecordEffort = AiReasoningEffort.none;

  @override
  List<AiConfiguredProvider> get aiProviders => List.unmodifiable(_providers);

  @override
  AiConfiguredProvider? aiProviderById(String? id) {
    final value = id?.trim();
    if (value == null || value.isEmpty) return null;
    return _providers.where((provider) => provider.id == value).firstOrNull;
  }

  @override
  String? get recordAiProviderId => selectedRecordProviderId;

  @override
  String? get recordAiModel => selectedRecordModel;

  @override
  AiReasoningEffort aiReasoningEffortFor(AiTaskType task) =>
      task == AiTaskType.recordParse
          ? selectedRecordEffort
          : super.aiReasoningEffortFor(task);

  @override
  Future<void> saveRecordAiSelection({
    required String providerId,
    required String model,
    required AiReasoningEffort reasoningEffort,
  }) async {
    selectedRecordProviderId = providerId;
    selectedRecordModel = model;
    selectedRecordEffort = reasoningEffort;
    notifyListeners();
  }

  @override
  Future<void> setAiConfiguredProviderEnabled(
    String providerId,
    bool enabled,
  ) async {
    final index =
        _providers.indexWhere((provider) => provider.id == providerId);
    if (index < 0) throw StateError('服务商不存在');
    _providers[index] = _providers[index].copyWith(enabled: enabled);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadScreenshotFonts);

  test(
      'Android GPT OAuth falls back to an external browser when isolation is unavailable',
      () {
    expect(
      openAiOAuthLaunchMode(isAndroid: true),
      LaunchMode.externalApplication,
    );
    expect(
      openAiOAuthLaunchMode(isAndroid: false),
      LaunchMode.inAppBrowserView,
    );
  });

  final oauthProvider = AiConfiguredProvider(
    id: 'claude-gateway',
    type: AiProviderType.custom,
    displayName: 'Claude Gateway',
    baseUrl: 'https://api.anthropic.com/v1',
    apiKey: 'oauth-token',
    model: 'claude-sonnet-5',
    models: const ['claude-sonnet-5'],
    endpointType: AiEndpointType.anthropicMessages,
    authMethod: AiAuthMethod.oauth,
    oauthAuthorizationUrl: 'https://auth.example.com/authorize',
  );
  final emptyProvider = AiConfiguredProvider(
    id: 'new-gateway',
    type: AiProviderType.custom,
    displayName: '',
    baseUrl: '',
    apiKey: '',
    model: '',
  );

  Future<void> pumpSettings(
    WidgetTester tester,
    _SettingsRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AiSettingView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('AI 账号设置'));
    await tester.pumpAndSettle();
  }

  testWidgets('账号页展示开关、OAuth 字段和 Anthropic 上游格式', (tester) async {
    final repository = _SettingsRepository([oauthProvider, emptyProvider]);
    await pumpSettings(tester, repository);

    expect(find.text('AI 账号设置'), findsOneWidget);
    expect(find.byType(AppSwitch), findsNWidgets(2));
    expect(find.text('Claude Gateway'), findsOneWidget);
    expect(find.text('未配置凭据'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsNothing);
    expect(find.byType(AppPlainIconButton), findsNWidgets(2));

    final card = tester.getRect(find.byKey(const ValueKey('claude-gateway')));
    final accountSwitch = tester.getRect(
      find.bySemanticsLabel('Claude Gateway启用状态'),
    );
    final deleteIcon = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('claude-gateway')),
        matching: find.byIcon(CupertinoIcons.trash),
      ),
    );
    expect(deleteIcon.right, lessThan(accountSwitch.left));
    // The card render box includes its 16dp outer margin; the visible card
    // edge is therefore 16dp inside this rect, followed by the row's 12dp
    // inset.
    expect(accountSwitch.right, closeTo(card.right - 28, 1));
    final deleteWidget = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('claude-gateway')),
        matching: find.byIcon(CupertinoIcons.trash),
      ),
    );
    expect(deleteWidget.color?.a ?? 1, lessThan(0.6));
    expect(
      tester.widget<Text>(find.text('Claude Gateway')).style?.fontWeight,
      FontWeight.w300,
    );
    expect(
      tester.widget<Text>(find.text('claude-sonnet-5')).style?.fontWeight,
      FontWeight.w300,
    );

    await tester.tap(find.byKey(const ValueKey('claude-gateway')));
    await tester.pump();
    final providerModelText = find.descendant(
      of: find.byKey(const ValueKey('ai-provider-model-list')),
      matching: find.text('claude-sonnet-5'),
    );
    expect(providerModelText, findsOneWidget);
    expect(tester.widget<Text>(providerModelText).style?.fontSize, 15);
    expect(find.text('OAuth Token'), findsOneWidget);
    expect(find.text('OAuth 授权地址'), findsOneWidget);
    expect(find.text('打开 OAuth 授权页'), findsOneWidget);
    expect(find.text('上游格式'), findsOneWidget);
    expect(find.text('Anthropic Messages (Claude)'), findsOneWidget);
    expect(find.text('https://auth.example.com/authorize'), findsOneWidget);

    final switchFinder = find.bySemanticsLabel('Claude Gateway启用状态');
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(repository.aiProviderById('claude-gateway')!.enabled, isFalse);
    expect(find.text('已停用'), findsOneWidget);

    if (Platform.environment['UPDATE_AI_ACCOUNT_SCREENSHOTS'] == '1') {
      final output = Directory(
        r'C:\src\xunni-codex\android-app\outputs\ai_account',
      )..createSync(recursive: true);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('../outputs/ai_account/ai_account_current.png'),
      );
      expect(output.existsSync(), isTrue);
    }
  });

  testWidgets('新账号字段保持为空，只显示 placeholder', (tester) async {
    final repository = _SettingsRepository([emptyProvider]);
    await pumpSettings(tester, repository);
    await tester.tap(find.byKey(const ValueKey('new-gateway')));
    await tester.pump();

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(4));
    expect(fields.every((field) => field.controller?.text.isEmpty ?? true),
        isTrue);
    final hints = fields
        .map((field) => field.decoration?.hintText ?? '')
        .toList(growable: false);
    expect(hints, contains('https://api.example.com'));
    expect(hints, contains('自定义'));
    expect(hints.any((hint) => hint.contains('输入模型名称')), isTrue);
    expect(hints.any((hint) => hint.contains('API Key')), isTrue);
    expect(find.text('未配置凭据'), findsOneWidget);
  });

  testWidgets('用途分配分别选择服务商、模型和思考强度', (tester) async {
    final repository = _SettingsRepository([oauthProvider, emptyProvider]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AiSettingView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('用途分配'));
    await tester.pumpAndSettle();

    expect(find.text('服务商'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text('Claude Gateway'), findsOneWidget);
    expect(find.text('claude-sonnet-5'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);

    await tester.tap(find.text('思考强度'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-chat-effort-popup')), findsOneWidget);
    expect(find.text('Faster'), findsOneWidget);
    expect(find.text('Smarter'), findsOneWidget);
    // The shared Claude slider has six stops; High is the third stop.
    // The slider has six stops; map the tap to the third stop (High) while
    // deriving the absolute position from the rendered widget so this remains
    // stable across font metrics and route placement.
    final effortSlider = tester.getRect(
      find.byKey(const ValueKey('ai-chat-effort-slider')),
    );
    await tester.tapAt(
      Offset(
        effortSlider.left + 9 + (effortSlider.width - 18) * 2 / 5,
        effortSlider.center.dy,
      ),
    );
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.selectedRecordProviderId, oauthProvider.id);
    expect(repository.selectedRecordModel, oauthProvider.model);
    expect(repository.selectedRecordEffort, AiReasoningEffort.high);
  });
}
