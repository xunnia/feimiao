import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/ai_account_json.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_provider_health.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/openai_codex_oauth.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import '../home/ai_chat_panel.dart';
import 'ai_companion_views.dart';

/// Use Android Custom Tabs so GPT authorization follows the user's normal
/// Chrome/VPN/proxy network path. The localhost listener is IPv4/IPv6 aware
/// and is rebound by the lifecycle watcher when Android resumes the app.
LaunchMode openAiOAuthLaunchMode({bool? isAndroid}) =>
    (isAndroid ?? Platform.isAndroid)
        ? LaunchMode.inAppBrowserView
        : LaunchMode.inAppBrowserView;

/// AI 设置：入口页负责分组，具体配置拆到子页面。
class AiSettingView extends StatelessWidget {
  const AiSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('AI 设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            SettingsGroup(
              children: [
                SettingsRow(
                  title: 'AI 账号设置',
                  trailing: _ValueChevron(
                    value: _accountSummary(repo),
                  ),
                  onTap: () => _push(
                    context,
                    const _AiAccountSettingsPage(),
                  ),
                ),
                SettingsRow(
                  title: '用途分配',
                  trailing: _ValueChevron(
                    value: repo.aiResolvedProviderLabelFor(
                      AiTaskType.recordParse,
                    ),
                  ),
                  onTap: () => _push(
                    context,
                    const _AiUsageRoutingPage(),
                  ),
                ),
                SettingsRow(
                  title: '隐私与数据',
                  trailing: const _ValueChevron(value: '本机安全存储'),
                  onTap: () => _push(
                    context,
                    const _AiPrivacyDataPage(),
                  ),
                ),
                SettingsRow(
                  title: 'AI 任务中心',
                  subtitle: '查看进行中、失败和已完成的 AI 运行',
                  onTap: () => _push(context, const AiTaskCenterView()),
                ),
                SettingsRow(
                  title: 'AI 诊断',
                  subtitle: '服务商健康、耗时和脱敏错误摘要',
                  onTap: () => _push(context, const AiDiagnosticsView()),
                ),
                SettingsRow(
                  title: '统一搜索',
                  subtitle: '搜索账单、对话和 AI 任务',
                  onTap: () => _push(context, const AiUnifiedSearchView()),
                ),
                SettingsRow(
                  title: '可控记忆',
                  subtitle: '只保留你明确授权的偏好',
                  onTap: () => _push(context, const AiMemoryControlView()),
                ),
                SettingsRow(
                  title: '技能与连接',
                  subtitle: '管理内置技能和受控连接器',
                  onTap: () =>
                      _push(context, const AiSkillsAndConnectorsView()),
                ),
                SettingsRow(
                  title: '定时报表',
                  subtitle: '按周或按月生成账本报告',
                  onTap: () => _push(context, const AiReportScheduleView()),
                ),
                SettingsRow(
                  title: '本地模型伴侣',
                  subtitle: '连接电脑上的本地模型服务',
                  onTap: () => _push(context, const LocalModelCompanionView()),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _CaptionText(
                '普通记账可单独选择服务商；喵助手和报告跟随当前对话模型。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _accountSummary(AppRepository repo) {
    final providers = repo.aiProviders;
    final configured = providers.where((provider) => provider.isUsable).length;
    return '$configured/${providers.length} 个服务商';
  }
}

class _AiAccountSettingsPage extends StatefulWidget {
  const _AiAccountSettingsPage();

  @override
  State<_AiAccountSettingsPage> createState() => _AiAccountSettingsPageState();
}

class _AiAccountSettingsPageState extends State<_AiAccountSettingsPage> {
  final Map<String, _ProviderDraft> _drafts = {};
  final Set<String> _expanded = {};
  final Set<String> _busy = {};

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  _ProviderDraft _draftFor(AiConfiguredProvider provider) {
    return _drafts.putIfAbsent(
      provider.id,
      () => _ProviderDraft(provider),
    );
  }

  Future<void> _addProvider() async {
    try {
      final provider =
          await context.read<AppRepository>().addAiConfiguredProvider();
      if (!mounted) return;
      setState(() => _expanded.add(provider.id));
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '添加失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _deleteProvider(AiConfiguredProvider provider) async {
    if (provider.builtIn || _busy.contains(provider.id)) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除${provider.label}？',
      message: '该服务商的地址、密钥和已保留模型会一并移除。',
      confirmText: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(provider.id));
    try {
      await context
          .read<AppRepository>()
          .deleteAiConfiguredProvider(provider.id);
      if (!mounted) return;
      setState(() {
        final draft = _drafts.remove(provider.id);
        draft?.dispose();
        _expanded.remove(provider.id);
      });
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '删除失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  Future<void> _saveProvider(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    if (_busy.contains(provider.id) || !_ensureSecureBaseUrl(provider, draft)) {
      return;
    }
    setState(() => _busy.add(provider.id));
    try {
      final models = draft.models;
      final model = _selectedModel(draft);
      final updated = provider.copyWith(
        displayName: draft.displayName.text.trim(),
        baseUrl: draft.baseUrl.text.trim(),
        apiKey: draft.apiKey.text.trim(),
        model: model,
        models: models,
        endpointType: draft.endpointType,
        authMethod: draft.authMethod,
        oauthAuthorizationUrl: draft.oauthAuthorizationUrl.text.trim(),
      );
      try {
        await context.read<AppRepository>().saveAiConfiguredProvider(updated);
        if (mounted) showAppToast(context, '${draft.label}已保存');
      } catch (error) {
        if (mounted) {
          showAppToast(
            context,
            '保存失败：${_shortError(error)}',
            icon: Icons.error_outline,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  Future<void> _testProvider(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    if (_busy.contains(provider.id)) return;
    final config = _formConfig(provider, draft);
    if (!config.hasCredential) {
      showAppToast(context, '先填写 API Key 或完成 OAuth 授权',
          icon: Icons.info_outline);
      return;
    }
    if (!config.hasBaseUrl) {
      showAppToast(context, '先填写基础地址', icon: Icons.info_outline);
      return;
    }
    if (!_ensureSecureBaseUrl(provider, draft)) return;
    setState(() => _busy.add(provider.id));
    try {
      final testConfig = config.copyWith(model: _selectedModel(draft));
      await LlmQuery.testConnection(testConfig);
      if (mounted) showAppToast(context, '${draft.label}连接成功');
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          '连接失败：${_shortError(e)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  Future<void> _manageModels(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    if (_busy.contains(provider.id)) return;
    final config = _formConfig(provider, draft);
    if (!config.hasCredential) {
      showAppToast(context, '先填写 API Key 或完成 OAuth 授权',
          icon: Icons.info_outline);
      return;
    }
    if (!config.hasBaseUrl) {
      showAppToast(context, '先填写基础地址', icon: Icons.info_outline);
      return;
    }
    if (!config.hasModel) {
      showAppToast(context, '先填写模型名称', icon: Icons.info_outline);
      return;
    }
    if (!_ensureSecureBaseUrl(provider, draft)) return;
    final result = await showBlurSheet<_ModelManagerResult>(
      context,
      child: _ProviderModelManagerSheet(
        providerLabel: draft.label,
        config: config,
        savedModels: draft.models,
        excludedModels: provider.excludedModels,
      ),
    );
    if (result == null || !mounted) return;
    final refreshedProvider =
        context.read<AppRepository>().aiProviderById(provider.id);
    if (refreshedProvider != null &&
        refreshedProvider.apiKey.trim().isNotEmpty &&
        refreshedProvider.apiKey != draft.apiKey.text) {
      draft.apiKey.text = refreshedProvider.apiKey;
    }
    final selectedModel = result.models.contains(draft.selectedModel)
        ? draft.selectedModel
        : result.models.firstOrNull;
    try {
      final updated = provider.copyWith(
        displayName: draft.displayName.text.trim(),
        baseUrl: draft.baseUrl.text.trim(),
        apiKey: draft.apiKey.text.trim(),
        model: selectedModel,
        models: result.models,
        excludedModels: result.excludedModels,
      );
      await context.read<AppRepository>().saveAiConfiguredProvider(updated);
      if (!mounted) return;
      setState(() {
        draft.models
          ..clear()
          ..addAll(result.models);
        draft.selectedModel = selectedModel ?? '';
      });
      showAppToast(context, '已保留 ${result.models.length} 个模型');
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '保存模型失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    }
  }

  bool _ensureSecureBaseUrl(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) {
    if (provider.type != AiProviderType.custom ||
        draft.apiKey.text.trim().isEmpty ||
        !_isInsecureBaseUrl(draft.baseUrl.text)) {
      return true;
    }
    showAppToast(
      context,
      '为保护数据安全，自定义服务地址必须是 https',
      icon: Icons.error_outline,
    );
    return false;
  }

  AiProviderConfig _formConfig(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) {
    final config = provider.toConfig().copyWith(
          apiKey: draft.apiKey.text,
          baseUrl: draft.baseUrl.text,
          model: _selectedModel(draft),
          endpointType: draft.endpointType,
          authMethod: draft.authMethod,
          displayName: draft.displayName.text,
        );
    if (draft.authMethod != AiAuthMethod.oauth) return config;
    return config.copyWith(
      oauthTokenSaver: (
        accessToken,
        refreshToken,
        expiresAtMs,
        accountId,
      ) async {
        final current =
            context.read<AppRepository>().aiProviderById(provider.id) ??
                provider;
        await context.read<AppRepository>().saveAiConfiguredProvider(
              current.copyWith(
                apiKey: accessToken,
                oauthRefreshToken: refreshToken ?? current.oauthRefreshToken,
                oauthExpiresAtMs: expiresAtMs ?? current.oauthExpiresAtMs,
                oauthAccountId: accountId ?? current.oauthAccountId,
              ),
            );
      },
    );
  }

  String _selectedModel(_ProviderDraft draft) {
    final selected = draft.selectedModel.trim();
    if (selected.isNotEmpty) return selected;
    return draft.models.firstOrNull ?? '';
  }

  Future<void> _openOAuthAuthorization(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    final raw = draft.oauthAuthorizationUrl.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      showAppToast(context, '先填写有效的 OAuth 授权地址', icon: Icons.info_outline);
      return;
    }
    if (!OpenAiCodexOAuth.isAuthorizationUrl(raw)) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showAppToast(context, '无法打开授权页', icon: Icons.error_outline);
      }
      return;
    }

    if (_busy.contains(provider.id)) return;
    setState(() => _busy.add(provider.id));
    try {
      final session = await OpenAiCodexOAuth.service.start(
        providerId: provider.id,
        authorizationUrl: raw,
      );
      // Keep GPT login in Chrome Custom Tabs on Android so the authorization
      // request uses the same network/proxy route as the user's browser. The
      // localhost listener is rebound on resume; manual callback paste stays
      // available if the OS still reclaims the Dart process.
      final authorizationUri = Uri.parse(session.authorizationUrl);
      final opened = await launchUrl(
            authorizationUri,
            mode: openAiOAuthLaunchMode(),
          ) ||
          await launchUrl(
            authorizationUri,
            mode: LaunchMode.externalApplication,
          );
      if (!opened) {
        await OpenAiCodexOAuth.service.cancel();
        if (mounted)
          showAppToast(context, '无法打开 GPT 授权页', icon: Icons.error_outline);
        return;
      }
      if (mounted) {
        showAppToast(context, '已打开 GPT 授权页，完成后返回肥喵记账',
            icon: Icons.info_outline);
      }
      final tokens = await session.completion;
      await _finishOpenAiOAuth(provider, draft, tokens);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          'GPT 授权失败：${_shortError(error)}。也可以粘贴回调地址重试。',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  Future<void> _pasteOAuthCallback(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    final controller = TextEditingController();
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = clipboard?.text?.trim() ?? '';
      if (clipboardText.contains('/auth/callback') &&
          clipboardText.contains('localhost:')) {
        controller.text = clipboardText;
      }
      if (!mounted) return;
      final confirmed = await showIosFormDialog(
        context,
        title: '粘贴 OAuth 回调地址',
        subtitle: '浏览器显示连接失败时，复制地址栏中 localhost:1455 或 1457 的完整地址。',
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          decoration: iosInputDecoration(
            context,
            hint: 'http://localhost:1455/auth/callback?code=…&state=…',
          ),
        ),
        confirmText: '完成授权',
        cancelText: '取消',
      );
      if (!confirmed || !mounted) return;
      setState(() => _busy.add(provider.id));
      final tokens = await OpenAiCodexOAuth.service.submitCallbackUrl(
        controller.text,
      );
      await _finishOpenAiOAuth(provider, draft, tokens);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '回调地址处理失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      controller.dispose();
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  Future<void> _finishOpenAiOAuth(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
    OpenAiCodexOAuthTokens tokens,
  ) async {
    List<OpenAiCodexModel> models = const [];
    Object? modelFetchError;
    try {
      models = await OpenAiCodexOAuth.service.fetchModels(tokens);
    } catch (error) {
      // Token exchange is the login result.  A transient /codex/models
      // failure must not discard a valid OAuth account; save a known official
      // model and let the user refresh the catalogue later.
      modelFetchError = error;
    }
    final modelNames = <String>[];
    final seen = <String>{};
    for (final candidate in [
      ...models.map((model) => model.slug),
      draft.selectedModel,
      provider.selectedModel,
      provider.model,
      AiProviderConfig.customDefaultModel,
    ]) {
      final value = candidate.trim();
      if (value.isNotEmpty && seen.add(value)) modelNames.add(value);
    }
    final saved = await context.read<AppRepository>().saveAiOAuthTokens(
          providerId: provider.id,
          tokens: tokens,
          models: modelNames,
        );
    draft.apiKey.text = saved.apiKey;
    draft.baseUrl.text = saved.baseUrl;
    draft.model.text = saved.model;
    draft.models
      ..clear()
      ..addAll(saved.models);
    draft.endpointType = saved.endpointType;
    draft.authMethod = saved.authMethod;
    if (mounted) {
      setState(() {});
      showAppToast(
        context,
        modelFetchError == null
            ? 'GPT 已授权，获取到 ${saved.models.length} 个模型'
            : 'GPT 已授权，模型目录暂时获取失败，可稍后点“获取模型”',
        icon: modelFetchError == null
            ? Icons.check_circle_outline
            : Icons.info_outline,
      );
    }
  }

  static bool _isInsecureBaseUrl(String raw) {
    final url = raw.trim().toLowerCase();
    if (!url.startsWith('http://')) return false;
    final host = Uri.tryParse(url)?.host ?? '';
    return !(host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  Future<void> _importAccountsFromFile() async {
    if (_busy.isNotEmpty) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final text = file.bytes != null
          ? utf8.decode(file.bytes!, allowMalformed: true)
          : file.path == null
              ? ''
              : await File(file.path!).readAsString();
      await _reviewAndImportAccounts(text);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '读取账号 JSON 失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _importAccountsFromClipboard() async {
    if (_busy.isNotEmpty) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        if (mounted) showAppToast(context, '剪贴板里没有 JSON 文本');
        return;
      }
      await _reviewAndImportAccounts(text);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '读取剪贴板失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _reviewAndImportAccounts(String text) async {
    final parsed = AiAccountJsonCodec.parse(text);
    if (parsed.accounts.isEmpty) {
      if (!mounted) return;
      final detail =
          parsed.warnings.isEmpty ? '没有找到可导入账号' : parsed.warnings.join('；');
      showAppToast(context, detail, icon: Icons.error_outline);
      return;
    }
    final repo = context.read<AppRepository>();
    final selections = await showBlurSheet<List<_AiAccountImportChoice>>(
      context,
      child: _AiAccountImportSheet(
        accounts: parsed.accounts,
        duplicateFor: repo.matchingAiProvider,
      ),
    );
    if (!mounted || selections == null || selections.isEmpty) return;
    setState(() => _busy.add('__json_import__'));
    var imported = 0;
    var skipped = 0;
    var modelFetchFailed = 0;
    try {
      for (final choice in selections) {
        if (choice.action == _AiAccountImportAction.skip) {
          skipped++;
          continue;
        }
        final duplicate = repo.matchingAiProvider(choice.account);
        final saved = await repo.importAiAccount(
          choice.account,
          existingProviderId: choice.action == _AiAccountImportAction.update
              ? duplicate?.id
              : null,
          enabledOverride: choice.enabled,
        );
        imported++;
        // Cockpit exports normally omit the model catalogue. Fetch it once so
        // a successful OAuth import is immediately usable with official GPT
        // models; an offline device can still use the saved fallback model.
        if (choice.account.isOAuth &&
            saved.models.length <= 1 &&
            choice.account.accessToken.trim().isNotEmpty &&
            saved.oauthAccountId.trim().isNotEmpty) {
          try {
            final tokens = OpenAiCodexOAuthTokens(
              accessToken: choice.account.accessToken,
              refreshToken: choice.account.refreshToken,
              idToken: choice.account.idToken,
              accountId: saved.oauthAccountId,
              expiresAtMs: choice.account.expiresAtMs,
            );
            final models = await OpenAiCodexOAuth.service.fetchModels(tokens);
            await repo.saveAiOAuthTokens(
              providerId: saved.id,
              tokens: tokens,
              models: models.map((model) => model.slug).toList(),
            );
          } catch (_) {
            modelFetchFailed++;
          }
        }
      }
      if (mounted) {
        final suffix = [
          if (skipped > 0) '跳过 $skipped',
          if (modelFetchFailed > 0) '模型目录待联网获取 $modelFetchFailed',
          if (parsed.warnings.isNotEmpty) parsed.warnings.join('；'),
        ].join('；');
        showAppToast(
          context,
          '已导入 $imported 个 AI 账号${suffix.isEmpty ? '' : '（$suffix）'}',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '导入失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove('__json_import__'));
    }
  }

  Future<void> _exportAccounts() async {
    final repo = context.read<AppRepository>();
    final providers = repo.aiProviders;
    if (providers.isEmpty) {
      showAppToast(context, '暂时没有可导出的 AI 账号');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '导出 AI 账号 JSON？',
      message:
          '导出的 Cockpit 兼容文件包含 API Key、OAuth access token 和 refresh token。\n'
          '请只保存到你信任的位置，不要发送给他人。',
      confirmText: '继续导出',
    );
    if (!confirmed || !mounted) return;
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/feimiao_ai_accounts_$stamp.json');
      await file.writeAsString(repo.exportAiAccountsJson(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '肥喵 AI 账号 JSON',
        text: '肥喵 AI 账号导出（包含敏感凭据，请妥善保管）',
      );
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '导出失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final providers = repo.aiProviders;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('AI 账号设置'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppCircleButton(
              icon: CupertinoIcons.add,
              onPressed: _addProvider,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            const SettingsSectionLabel('账号文件'),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: '导入账号 JSON',
                  subtitle: '支持 Cockpit、OpenAI auth.json、Sub2API',
                  leading: const Icon(CupertinoIcons.arrow_down_doc),
                  onTap: _importAccountsFromFile,
                ),
                SettingsRow(
                  title: '从剪贴板粘贴 JSON',
                  subtitle: '适合直接粘贴 Cockpit 导出的文本',
                  leading: const Icon(CupertinoIcons.doc_on_clipboard),
                  onTap: _importAccountsFromClipboard,
                ),
                SettingsRow(
                  title: '导出账号 JSON',
                  subtitle: 'Cockpit 兼容格式，包含敏感凭据',
                  leading: const Icon(CupertinoIcons.share),
                  onTap: _exportAccounts,
                ),
              ],
            ),
            const SettingsSectionLabel('服务商'),
            for (final provider in providers)
              _ProviderCard(
                key: ValueKey(provider.id),
                provider: provider,
                health: repo.aiProviderHealthFor(provider.id),
                draft: _draftFor(provider),
                expanded: _expanded.contains(provider.id),
                busy: _busy.contains(provider.id),
                onToggle: () => setState(() {
                  if (!_expanded.add(provider.id)) {
                    _expanded.remove(provider.id);
                  }
                }),
                onSave: () => _saveProvider(provider, _draftFor(provider)),
                onTest: () => _testProvider(provider, _draftFor(provider)),
                onManageModels: () =>
                    _manageModels(provider, _draftFor(provider)),
                onEnabledChanged: (value) async {
                  try {
                    await context
                        .read<AppRepository>()
                        .setAiConfiguredProviderEnabled(provider.id, value);
                  } catch (error) {
                    if (mounted) {
                      showAppToast(
                        context,
                        '切换失败：${_shortError(error)}',
                        icon: Icons.error_outline,
                      );
                    }
                  }
                },
                onOAuthAuthorize: () =>
                    _openOAuthAuthorization(provider, _draftFor(provider)),
                onOAuthCallbackPaste: () =>
                    _pasteOAuthCallback(provider, _draftFor(provider)),
                onDelete:
                    provider.builtIn ? null : () => _deleteProvider(provider),
                onChanged: () => setState(() {}),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderDraft {
  final TextEditingController displayName;
  final TextEditingController apiKey;
  final TextEditingController baseUrl;
  final TextEditingController model;
  final TextEditingController oauthAuthorizationUrl;
  final List<String> models;
  AiEndpointType endpointType;
  AiAuthMethod authMethod;
  bool obscureKey = true;

  _ProviderDraft(AiConfiguredProvider provider)
      : displayName = TextEditingController(text: provider.displayName),
        apiKey = TextEditingController(text: provider.apiKey),
        baseUrl = TextEditingController(text: provider.baseUrl),
        model = TextEditingController(text: provider.model),
        oauthAuthorizationUrl = TextEditingController(
          text: provider.oauthAuthorizationUrl.trim().isNotEmpty
              ? provider.oauthAuthorizationUrl
              : provider.authMethod == AiAuthMethod.oauth
                  ? AiProviderConfig.openAiOAuthAuthorizationUrl
                  : '',
        ),
        models = List<String>.from(provider.models),
        endpointType = provider.endpointType,
        authMethod = provider.authMethod;

  String get selectedModel => model.text;

  set selectedModel(String value) => model.text = value;

  String get label {
    final value = displayName.text.trim();
    return value.isEmpty ? '自定义服务' : value;
  }

  void dispose() {
    displayName.dispose();
    apiKey.dispose();
    baseUrl.dispose();
    model.dispose();
    oauthAuthorizationUrl.dispose();
  }
}

enum _AiAccountImportAction { create, update, skip }

class _AiAccountImportChoice {
  final AiAccountImportEntry account;
  final AiConfiguredProvider? duplicate;
  _AiAccountImportAction action;
  bool enabled;

  _AiAccountImportChoice({
    required this.account,
    required this.duplicate,
  })  : action = duplicate == null
            ? _AiAccountImportAction.create
            : _AiAccountImportAction.update,
        enabled = account.enabled;
}

class _AiAccountImportSheet extends StatefulWidget {
  final List<AiAccountImportEntry> accounts;
  final AiConfiguredProvider? Function(AiAccountImportEntry) duplicateFor;

  const _AiAccountImportSheet({
    required this.accounts,
    required this.duplicateFor,
  });

  @override
  State<_AiAccountImportSheet> createState() => _AiAccountImportSheetState();
}

class _AiAccountImportSheetState extends State<_AiAccountImportSheet> {
  late final List<_AiAccountImportChoice> _choices;

  @override
  void initState() {
    super.initState();
    _choices = [
      for (final account in widget.accounts)
        _AiAccountImportChoice(
          account: account,
          duplicate: widget.duplicateFor(account),
        ),
    ];
  }

  void _cycleAction(_AiAccountImportChoice choice) {
    if (choice.duplicate == null) return;
    setState(() {
      choice.action = switch (choice.action) {
        _AiAccountImportAction.update => _AiAccountImportAction.create,
        _AiAccountImportAction.create => _AiAccountImportAction.skip,
        _AiAccountImportAction.skip => _AiAccountImportAction.update,
      };
    });
  }

  String _actionLabel(_AiAccountImportChoice choice) => switch (choice.action) {
        _AiAccountImportAction.create =>
          choice.duplicate == null ? '新建账号' : '新建副本',
        _AiAccountImportAction.update => '更新已有',
        _AiAccountImportAction.skip => '跳过',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedCount = _choices
        .where((choice) => choice.action != _AiAccountImportAction.skip)
        .length;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: '导入 AI 账号',
                subtitle: '账号凭据会写入本机安全存储；点击重复账号可切换处理方式',
                onClose: () => Navigator.of(context).pop(),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  itemCount: _choices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final choice = _choices[index];
                    final account = choice.account;
                    final duplicate = choice.duplicate;
                    final skipped =
                        choice.action == _AiAccountImportAction.skip;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: skipped ? 0.22 : 0.52),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: duplicate == null
                              ? AppColors.hairline(scheme)
                              : scheme.primary.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                account.isOAuth
                                    ? CupertinoIcons.person_crop_circle
                                    : CupertinoIcons.lock,
                                size: 21,
                                color: skipped
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.maskedIdentity.isEmpty
                                          ? account.displayName
                                          : account.maskedIdentity,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w500,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${account.source.label} · ${account.isOAuth ? 'OAuth' : 'API Key'}'
                                      '${duplicate == null ? '' : ' · 已存在「${duplicate.label}」'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (duplicate != null)
                                AppPillButton(
                                  label: _actionLabel(choice),
                                  onPressed: () => _cycleAction(choice),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '同步加入 API 服务',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              AppSwitch(
                                value: choice.enabled,
                                onChanged: skipped
                                    ? null
                                    : (value) => setState(
                                          () => choice.enabled = value,
                                        ),
                                semanticLabel: '同步加入 API 服务',
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: AppPillButton(
                        label: '取消',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppPillButton(
                        label: '导入 $selectedCount 个',
                        onPressed: selectedCount == 0
                            ? null
                            : () => Navigator.of(context).pop(_choices),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AiConfiguredProvider provider;
  final AiProviderHealth health;
  final _ProviderDraft draft;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onManageModels;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onOAuthAuthorize;
  final VoidCallback onOAuthCallbackPaste;
  final VoidCallback? onDelete;
  final VoidCallback onChanged;

  const _ProviderCard({
    super.key,
    required this.provider,
    required this.health,
    required this.draft,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onSave,
    required this.onTest,
    required this.onManageModels,
    required this.onEnabledChanged,
    required this.onOAuthAuthorize,
    required this.onOAuthCallbackPaste,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = draft.selectedModel.trim().isEmpty
        ? (draft.models.firstOrNull ?? provider.model)
        : draft.selectedModel.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      // Provider cards sit on the same glass background as the rest of the
      // page, so keep the translucent fill but add a restrained outline and
      // shadow to make each account boundary unambiguous.
      decoration: ShapeDecoration(
        color: AppColors.card(scheme),
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        shape: ContinuousRectangleBorder(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.58),
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      provider.type == AiProviderType.deepseek
                          ? CupertinoIcons.sparkles
                          : CupertinoIcons.cloud,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                draft.label,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.rowTitle(scheme).copyWith(
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            if (provider.builtIn) ...[
                              const SizedBox(width: 6),
                              Text('内置', style: AppType.caption(scheme)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          !provider.enabled
                              ? '已停用'
                              : provider.isUsable
                                  ? model
                                  : provider.hasCredential ||
                                          draft.apiKey.text.trim().isNotEmpty
                                      ? '配置未完成'
                                      : '未配置凭据',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.secondary(scheme).copyWith(
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          health.averageLatencyMs > 0
                              ? '${health.statusLabel} · 首字 ${health.averageLatencyMs}ms'
                              : health.statusLabel,
                          style: AppType.caption(scheme).copyWith(
                            color: health.isCoolingDown
                                ? AppColors.warning
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppCircleButton.custom(
                        iconWidget: Icon(
                          CupertinoIcons.trash,
                          size: 17,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.42),
                        ),
                        size: 30,
                        iconSize: 17,
                        semanticLabel: '删除 ${draft.label}',
                        onPressed: onDelete,
                      ),
                    ),
                  AppSwitch(
                    value: provider.enabled,
                    onChanged: busy ? null : onEnabledChanged,
                    semanticLabel: '${draft.label}启用状态',
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 0.5, color: AppColors.hairline(scheme)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                children: [
                  AppLabeledField(
                    label: draft.authMethod == AiAuthMethod.oauth
                        ? 'OAuth Token'
                        : 'API Key',
                    child: TextField(
                      controller: draft.apiKey,
                      obscureText: draft.obscureKey,
                      readOnly: draft.authMethod == AiAuthMethod.oauth &&
                          OpenAiCodexOAuth.isAuthorizationUrl(
                            draft.oauthAuthorizationUrl.text,
                          ),
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontWeight: FontWeight.w300),
                      decoration: iosInputDecoration(
                        context,
                        hint: draft.authMethod == AiAuthMethod.oauth
                            ? '粘贴 OAuth access token'
                            : '输入 API Key',
                        fillColor: scheme.surface.withValues(alpha: 0.52),
                        inputBorderSide:
                            BorderSide(color: AppColors.hairline(scheme)),
                        radius: 14,
                      ).copyWith(
                        suffixIcon: AppCircleButton(
                          icon: draft.obscureKey
                              ? CupertinoIcons.eye
                              : CupertinoIcons.eye_slash,
                          size: 30,
                          iconSize: 18,
                          semanticLabel: draft.obscureKey ? '显示 API Key' : '隐藏 API Key',
                          onPressed: () => _toggleObscure(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '认证方式',
                    child: _ProviderOptionField(
                      value: draft.authMethod.label,
                      onTap: (anchor) {
                        showIosMenu(anchor, [
                          for (final method in AiAuthMethod.values)
                            IosMenuItem(
                              label: method.label,
                              icon: draft.authMethod == method
                                  ? Icons.check
                                  : Icons.key_outlined,
                              onTap: () {
                                draft.authMethod = method;
                                if (method == AiAuthMethod.oauth &&
                                    draft.oauthAuthorizationUrl.text
                                        .trim()
                                        .isEmpty) {
                                  draft.oauthAuthorizationUrl.text =
                                      AiProviderConfig
                                          .openAiOAuthAuthorizationUrl;
                                }
                                onChanged();
                              },
                            ),
                        ]);
                      },
                    ),
                  ),
                  if (draft.authMethod == AiAuthMethod.oauth) ...[
                    const SizedBox(height: 12),
                    AppLabeledField(
                      label: 'OAuth 授权地址',
                      child: TextField(
                        controller: draft.oauthAuthorizationUrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(fontWeight: FontWeight.w300),
                        decoration: iosInputDecoration(
                          context,
                          hint: AiProviderConfig.openAiOAuthAuthorizationUrl,
                          fillColor: scheme.surface.withValues(alpha: 0.52),
                          inputBorderSide:
                              BorderSide(color: AppColors.hairline(scheme)),
                          radius: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AppPillButton(
                            label: OpenAiCodexOAuth.isAuthorizationUrl(
                              draft.oauthAuthorizationUrl.text,
                            )
                                ? 'GPT OAuth 授权'
                                : '打开 OAuth 授权页',
                            onPressed: onOAuthAuthorize,
                          ),
                          if (OpenAiCodexOAuth.isAuthorizationUrl(
                            draft.oauthAuthorizationUrl.text,
                          ))
                            AppPillButton(
                              label: '粘贴回调地址',
                              onPressed: onOAuthCallbackPaste,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '上游格式',
                    child: _ProviderOptionField(
                      value: draft.endpointType.label,
                      onTap: (anchor) {
                        showIosMenu(anchor, [
                          for (final endpoint in AiEndpointType.values)
                            IosMenuItem(
                              label: endpoint.label,
                              icon: draft.endpointType == endpoint
                                  ? Icons.check
                                  : Icons.route_outlined,
                              onTap: () {
                                draft.endpointType = endpoint;
                                onChanged();
                              },
                            ),
                        ]);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '基础地址',
                    child: TextField(
                      controller: draft.baseUrl,
                      readOnly: provider.builtIn,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontWeight: FontWeight.w300),
                      decoration: iosInputDecoration(
                        context,
                        hint: 'https://api.example.com',
                        fillColor: scheme.surface.withValues(alpha: 0.52),
                        inputBorderSide:
                            BorderSide(color: AppColors.hairline(scheme)),
                        radius: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '服务商名称（可选）',
                    child: TextField(
                      controller: draft.displayName,
                      readOnly: provider.builtIn,
                      autocorrect: false,
                      style: const TextStyle(fontWeight: FontWeight.w300),
                      decoration: iosInputDecoration(
                        context,
                        hint: provider.type.label,
                        fillColor: scheme.surface.withValues(alpha: 0.52),
                        inputBorderSide:
                            BorderSide(color: AppColors.hairline(scheme)),
                        radius: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '普通模型',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                draft.models.isEmpty
                                    ? '尚未获取模型'
                                    : '已保留 ${draft.models.length} 个模型',
                                style: AppType.caption(scheme),
                              ),
                            ),
                            AppPillButton(
                              label: '获取模型',
                              onPressed: busy ? null : onManageModels,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _ProviderModelListBox(
                          draft: draft,
                          availableModels: draft.models,
                          onFetchModels: onManageModels,
                          isFetching: busy,
                          onTest: onTest,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AppPillButton(
                        label: '测试连接',
                        onPressed: busy ? null : onTest,
                      ),
                      const Spacer(),
                      AppPillButton(
                        label: busy ? '保存中' : '保存',
                        onPressed: busy ? null : onSave,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleObscure(BuildContext context) {
    // The draft is intentionally mutable so text controllers survive collapse.
    draft.obscureKey = !draft.obscureKey;
    (context as Element).markNeedsBuild();
  }
}

class _ProviderModelListBox extends StatefulWidget {
  final _ProviderDraft draft;
  final List<String> availableModels;
  final VoidCallback? onFetchModels;
  final bool isFetching;
  final VoidCallback onTest;

  const _ProviderModelListBox({
    required this.draft,
    required this.availableModels,
    required this.onFetchModels,
    required this.isFetching,
    required this.onTest,
  });

  @override
  State<_ProviderModelListBox> createState() => _ProviderModelListBoxState();
}

class _ProviderOptionField extends StatelessWidget {
  final String value;
  final ValueChanged<BuildContext> onTap;

  const _ProviderOptionField({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (anchorContext) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(anchorContext),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_down,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderModelListBoxState extends State<_ProviderModelListBox> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.availableModels.contains(widget.draft.selectedModel)
        ? widget.draft.selectedModel
        : widget.availableModels.firstOrNull;

    if (widget.availableModels.isEmpty) {
      return TextField(
        controller: widget.draft.model,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w300,
        ),
        decoration: iosInputDecoration(
          context,
          hint: '输入模型名称，或点击“获取模型”',
          fillColor: scheme.surface.withValues(alpha: 0.52),
          inputBorderSide: BorderSide(color: AppColors.hairline(scheme)),
          radius: 14,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('ai-provider-model-list'),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.hairline(scheme),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13.5),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: widget.availableModels.length,
              itemBuilder: (context, index) {
                final model = widget.availableModels[index];
                final isSelected = model == selected;
                return InkWell(
                  onTap: () {
                    setState(() {
                      widget.draft.selectedModel = model;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: scheme.primary,
                            ),
                          )
                        else
                          const SizedBox(width: 24),
                        Expanded(
                          child: Text(
                            model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AiUsageRoutingPage extends StatefulWidget {
  const _AiUsageRoutingPage();

  @override
  State<_AiUsageRoutingPage> createState() => _AiUsageRoutingPageState();
}

class _AiUsageRoutingPageState extends State<_AiUsageRoutingPage> {
  String? _selectedProviderId;
  String? _selectedModel;
  AiReasoningEffort _selectedEffort = AiReasoningEffort.none;
  bool _saving = false;

  static const _efforts = [
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
    AiReasoningEffort.ultra,
  ];

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final current = repo.aiProviderById(repo.recordAiProviderId);
    _selectedProviderId = current?.isUsable == true
        ? current?.id
        : repo.aiProviders
            .where((provider) => provider.isUsable)
            .firstOrNull
            ?.id;
    final models = repo.aiModelsForProvider(_selectedProviderId);
    _selectedModel = models.contains(repo.recordAiModel)
        ? repo.recordAiModel
        : models.firstOrNull;
    _selectedEffort = _chatCompatibleEffort(
      repo.aiReasoningEffortFor(AiTaskType.recordParse),
    );
  }

  AiReasoningEffort _chatCompatibleEffort(AiReasoningEffort effort) =>
      effort == AiReasoningEffort.none || effort == AiReasoningEffort.minimal
          ? AiReasoningEffort.low
          : effort;

  Future<void> _save() async {
    final id = _selectedProviderId;
    final model = _selectedModel;
    if (_saving || id == null || id.isEmpty || model == null || model.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().saveRecordAiSelection(
            providerId: id,
            model: model,
            reasoningEffort: _selectedEffort,
          );
      if (mounted) showAppToast(context, '普通记账设置已保存');
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '保存失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _effortLabel(AiReasoningEffort effort) =>
      _chatCompatibleEffort(effort) == AiReasoningEffort.ultra
          ? 'Ultracode'
          : _chatCompatibleEffort(effort).label;

  Widget _menuRow({
    required String title,
    String? subtitle,
    required String value,
    required List<IosMenuItem> items,
    bool enabled = true,
    double? menuWidth,
    ValueChanged<BuildContext>? customOnTap,
  }) {
    late BuildContext anchorContext;
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: Builder(
        builder: (context) {
          anchorContext = context;
          return _ValueChevron(value: value);
        },
      ),
      onTap: !enabled
          ? null
          : customOnTap == null
              ? () => showIosMenu(
                    anchorContext,
                    items,
                    width: menuWidth,
                  )
              : () => customOnTap(anchorContext),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final providers = repo.aiProviders;
    final selectedProviderId = providers.any((provider) =>
            provider.id == _selectedProviderId && provider.isUsable)
        ? _selectedProviderId
        : providers.where((provider) => provider.isUsable).firstOrNull?.id;
    final selectedProvider = providers
        .where((provider) => provider.id == selectedProviderId)
        .firstOrNull;
    final models = repo.aiModelsForProvider(selectedProviderId);
    final selectedModel = models.contains(_selectedModel)
        ? _selectedModel
        : selectedProviderId == repo.recordAiProviderId &&
                models.contains(repo.recordAiModel)
            ? repo.recordAiModel
            : models.firstOrNull;
    final modelOptions = [
      for (final model in models)
        AiModelOption(
          providerId: selectedProviderId ?? '',
          providerLabel: selectedProvider?.label ?? '',
          model: model,
        ),
    ];
    if (selectedProviderId != _selectedProviderId ||
        selectedModel != _selectedModel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedProviderId = selectedProviderId;
          _selectedModel = selectedModel;
        });
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('用途分配'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppPillButton(
              label: _saving ? '保存中…' : '保存',
              onPressed:
                  _saving || selectedProviderId == null || selectedModel == null
                      ? null
                      : _save,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _InfoBox(
                text: '这里可分别设置普通记账使用的服务商、模型和思考强度；喵助手和报告跟随当前对话模型。',
              ),
            ),
            const SettingsSectionLabel('普通记账'),
            SettingsGroup(
              children: [
                _menuRow(
                  title: '服务商',
                  value: selectedProvider?.label ?? '暂无可用服务商',
                  enabled: selectedProvider != null,
                  items: [
                    for (final provider
                        in providers.where((provider) => provider.isUsable))
                      IosMenuItem(
                        label: provider.label,
                        icon: provider.type == AiProviderType.deepseek
                            ? CupertinoIcons.sparkles
                            : CupertinoIcons.cloud,
                        selected: provider.id == selectedProviderId,
                        onTap: () {
                          final providerModels =
                              repo.aiModelsForProvider(provider.id);
                          final savedModel = provider.id ==
                                      repo.recordAiProviderId &&
                                  providerModels.contains(repo.recordAiModel)
                              ? repo.recordAiModel
                              : null;
                          setState(() {
                            _selectedProviderId = provider.id;
                            _selectedModel =
                                savedModel ?? providerModels.firstOrNull;
                          });
                        },
                      ),
                  ],
                ),
                _menuRow(
                  title: '模型',
                  subtitle:
                      selectedProvider == null ? '请先在 AI 账号设置中完成服务商配置' : null,
                  value: selectedModel ?? '暂无可用模型',
                  enabled: selectedModel != null,
                  menuWidth: 280,
                  items: [
                    for (final model in models)
                      IosMenuItem(
                        label: model,
                        icon: CupertinoIcons.cube_box,
                        selected: model == selectedModel,
                        onTap: () => setState(() => _selectedModel = model),
                      ),
                  ],
                  customOnTap: selectedModel == null
                      ? null
                      : (anchor) => showAiModelPickerPopup(
                            context: context,
                            anchor: anchor,
                            options: modelOptions,
                            currentKey:
                                '${selectedProviderId ?? ''}\u0000$selectedModel',
                            onSelected: (option) => setState(
                              () => _selectedModel = option.model,
                            ),
                          ),
                ),
                _menuRow(
                  title: '思考强度',
                  subtitle: '档位越高，解析可能更慢并消耗更多 Token',
                  value: _effortLabel(_selectedEffort),
                  menuWidth: 220,
                  items: [
                    for (final effort in _efforts)
                      IosMenuItem(
                        label: _effortLabel(effort),
                        icon: effort == AiReasoningEffort.none
                            ? CupertinoIcons.speedometer
                            : CupertinoIcons.sparkles,
                        selected: effort == _selectedEffort,
                        onTap: () => setState(() => _selectedEffort = effort),
                      ),
                  ],
                  customOnTap: (anchor) => showAiEffortPickerPopup(
                    context: context,
                    anchor: anchor,
                    currentEffort: _chatCompatibleEffort(_selectedEffort),
                    onChanged: (effort) => setState(
                      () => _selectedEffort = effort,
                    ),
                  ),
                ),
              ],
            ),
            if (providers.where((provider) => provider.isUsable).isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _CaptionText('请先在 AI 账号设置中添加并完成服务商配置。'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiPrivacyDataPage extends StatelessWidget {
  const _AiPrivacyDataPage();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('隐私与数据'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const SettingsSectionLabel('本机存储'),
            const SettingsGroup(
              children: [
                SettingsRow(
                  title: 'API Key',
                  subtitle: '只写入本机安全存储，不进入肥喵导出备份',
                  trailing: _PlainValue('安全存储'),
                ),
                SettingsRow(
                  title: '服务名称和模型',
                  subtitle: '不含密钥，可随应用设置一起保留',
                  trailing: _PlainValue('可备份'),
                ),
                SettingsRow(
                  title: '对话与报告',
                  subtitle: '属于应用业务数据，按现有记录策略保存',
                  trailing: _PlainValue('本机数据'),
                ),
              ],
            ),
            const SettingsSectionLabel('授权状态'),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: 'AI 隐私确认',
                  subtitle: '切换服务或用途分配后，会要求用户重新确认',
                  trailing: _PlainValue(
                    repo.aiPrivacyAccepted ? '已确认' : '待确认',
                  ),
                ),
                SettingsRow(
                  title: '重新确认 AI 隐私说明',
                  subtitle: '下次使用 AI 记账或喵助手时重新弹出说明',
                  titleColor: AppColors.warning, // 守不用红铁律
                  onTap: () async {
                    await context
                        .read<AppRepository>()
                        .setAiPrivacyAccepted(false);
                    if (context.mounted) {
                      showAppToast(context, '下次使用 AI 时会重新确认');
                    }
                  },
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _CaptionText(
                '使用第三方中转站时，数据会发送到所填服务地址，请同时确认该服务的隐私规则。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;

  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _MutedText(text),
    );
  }
}

class _ValueChevron extends StatelessWidget {
  final String value;

  const _ValueChevron({required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: AppType.trailingValue(scheme),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 17,
            color: scheme.outline,
          ),
        ],
      ),
    );
  }
}

class _PlainValue extends StatelessWidget {
  final String text;

  const _PlainValue(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(text, style: AppType.trailingValue(scheme));
  }
}

class _MutedText extends StatelessWidget {
  final String text;

  const _MutedText(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // UI 标准：说明文字一律 AppType.secondary（13/中灰），不再依赖 textTheme。
    return Text(text, style: AppType.secondary(scheme));
  }
}

class _CaptionText extends StatelessWidget {
  final String text;

  const _CaptionText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: AppType.caption(Theme.of(context).colorScheme),
    );
  }
}

String _shortError(Object e) {
  final text = e.toString().replaceFirst('LlmQueryException: ', '').trim();
  if (text.length <= 42) return text;
  return '${text.substring(0, 42)}…';
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(
    AppPageRoute<void>(builder: (_) => page),
  );
}

// ---------------------------------------------------------------------------
// 模型管理底部抽屉
// ---------------------------------------------------------------------------

class _ModelManagerResult {
  final List<String> models;
  final List<String> excludedModels;

  const _ModelManagerResult({
    required this.models,
    required this.excludedModels,
  });
}

class _ProviderModelManagerSheet extends StatefulWidget {
  final String providerLabel;
  final AiProviderConfig config;
  final List<String> savedModels;
  final List<String> excludedModels;

  const _ProviderModelManagerSheet({
    required this.providerLabel,
    required this.config,
    required this.savedModels,
    required this.excludedModels,
  });

  @override
  State<_ProviderModelManagerSheet> createState() =>
      _ProviderModelManagerSheetState();
}

class _ProviderModelManagerSheetState
    extends State<_ProviderModelManagerSheet> {
  late final List<String> _kept;
  late final Set<String> _removed;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _kept = <String>[];
    final seen = <String>{};
    for (final value in widget.savedModels) {
      final model = value.trim();
      if (model.isNotEmpty && seen.add(model)) _kept.add(model);
    }
    _removed = widget.excludedModels
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final configuredModel = widget.config.model.trim();
    if (_kept.isEmpty &&
        configuredModel.isNotEmpty &&
        !_removed.contains(configuredModel)) {
      _kept.add(configuredModel);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshFromUpstream();
    });
  }

  Future<void> _refreshFromUpstream() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final models = await LlmQuery.fetchModels(widget.config);
      if (!mounted) return;
      final seen = _kept.toSet();
      setState(() {
        for (final value in models) {
          final model = value.trim();
          if (model.isNotEmpty &&
              !_removed.contains(model) &&
              seen.add(model)) {
            _kept.add(model);
          }
        }
      });
      if (mounted) showAppToast(context, '已从上游更新 ${models.length} 个模型');
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '获取模型失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        children: [
          SheetHeader(
            title: '模型管理',
            subtitle: '${widget.providerLabel} · ${_kept.length} 个模型',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: _kept.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      _ModelManagerResult(
                        models: List<String>.from(_kept),
                        excludedModels: _removed.toList()..sort(),
                      ),
                    ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('${_kept.length} 个模型', style: AppType.secondary(scheme)),
            ),
          ),
          Flexible(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.inputFill(scheme),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _kept.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child:
                            Text('还没有保留模型', style: AppType.secondary(scheme)),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _kept.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 0.5,
                        indent: 14,
                        color: AppColors.hairline(scheme),
                      ),
                      itemBuilder: (context, index) {
                        final model = _kept[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                          trailing: AppCircleButton(
                            icon: CupertinoIcons.minus_circle,
                            iconSize: 18,
                            size: 30,
                            onPressed: () => setState(() {
                              _removed.add(model);
                              _kept.removeAt(index);
                            }),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '从上游获取只会新增模型，不会恢复你已删除的模型。',
                style: AppType.caption(scheme),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: AppPillButton(
              label: _refreshing ? '获取中' : '从上游获取',
              onPressed: _refreshing ? null : _refreshFromUpstream,
            ),
          ),
        ],
      ),
    );
  }
}
