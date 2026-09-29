import 'dart:io' show File, Platform;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/ai_account_import_controller.dart';
import '../../core/ai/ai_account_json.dart';
import '../../core/ai/ai_account_verification.dart';
import '../../core/ai/ai_logger.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_provider_health.dart';
import '../../core/ai/ai_provider_url_policy.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/openai_codex_oauth.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

/// Keep Android's OAuth browser leg on Chrome. It first attempts an isolated
/// Custom Tab, then a Chrome Incognito tab, then a normal Chrome tab; only when
/// Chrome is unavailable does it use the generic browser resolver. The latter
/// is deliberately last because an installed ChatGPT app can otherwise claim
/// auth.openai.com and silently reuse its current personal workspace.
LaunchMode openAiOAuthLaunchMode({bool? isAndroid}) =>
    (isAndroid ?? Platform.isAndroid)
        ? LaunchMode.externalApplication
        : LaunchMode.inAppBrowserView;

/// AI 账号：自己填的服务商、密钥和 OAuth。「隐私与数据」是设置首页单独一行。
/// 从设置首页「AI」分组进入（原来的「AI 记账设置」入口页已取消，01 §4）。
class AiAccountSettingsPage extends StatefulWidget {
  const AiAccountSettingsPage({super.key});

  @override
  State<AiAccountSettingsPage> createState() => _AiAccountSettingsPageState();
}

class _AiAccountSettingsPageState extends State<AiAccountSettingsPage> {
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
    final started = DateTime.now();
    try {
      final testConfig = config.copyWith(model: _selectedModel(draft));
      await LlmQuery.testConnection(testConfig);
      try {
        await context.read<AppRepository>().recordAiProviderVerification(
              provider.id,
              status: AiAccountVerificationStatus.available.name,
              latencyMs: DateTime.now().difference(started).inMilliseconds,
            );
      } catch (_) {
        // Diagnostics must never turn a successful provider probe into a
        // failed user action (for example while a database is closing).
      }
      if (mounted) showAppToast(context, '${draft.label}连接成功');
    } catch (e) {
      try {
        await context.read<AppRepository>().recordAiProviderVerification(
              provider.id,
              status: _verificationStatusForError(e).name,
              message: _shortError(e),
              latencyMs: DateTime.now().difference(started).inMilliseconds,
            );
      } catch (_) {}
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

  Future<void> _verifyProvider(
    AiConfiguredProvider provider,
    _ProviderDraft draft,
  ) async {
    if (_busy.contains(provider.id)) return;
    final repo = context.read<AppRepository>();
    final config = repo.aiProviderConfigForProvider(provider.id);
    if (config == null) {
      showAppToast(context, '账号配置不存在', icon: Icons.error_outline);
      return;
    }
    setState(() => _busy.add(provider.id));
    try {
      final result = await const AiAccountVerificationService().verify(config);
      await repo.recordAiProviderVerification(
        provider.id,
        status: result.status.name,
        message: result.message,
        latencyMs: result.latencyMs,
      );
      if (result.models.isNotEmpty) {
        final latest = repo.aiProviderById(provider.id) ?? provider;
        await repo.saveAiConfiguredProvider(
          latest.copyWith(
            model: result.models.first,
            models: result.models,
          ),
        );
        draft.models
          ..clear()
          ..addAll(result.models);
        draft.selectedModel = result.models.first;
      }
      if (mounted) {
        showAppToast(
          context,
          '${draft.label}：${result.summary}',
          icon: result.isAvailable
              ? Icons.check_circle_outline
              : Icons.info_outline,
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '验证失败：${_shortError(error)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider.id));
    }
  }

  static AiAccountVerificationStatus _verificationStatusForError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('401') || text.contains('403') || text.contains('凭据')) {
      return AiAccountVerificationStatus.invalidCredential;
    }
    if (text.contains('模型') || text.contains('model')) {
      return AiAccountVerificationStatus.modelUnavailable;
    }
    if (text.contains('proxy') || text.contains('vpn') || text.contains('网络')) {
      return AiAccountVerificationStatus.needsProxy;
    }
    return AiAccountVerificationStatus.networkError;
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
        draft.apiKey.text.trim().isEmpty) {
      return true;
    }
    final error = AiProviderUrlPolicy.validateBaseUrl(draft.baseUrl.text);
    if (error == null) return true;
    showAppToast(
      context,
      switch (error) {
        AiProviderUrlError.invalid => '请输入有效的服务地址',
        AiProviderUrlError.unsupportedScheme =>
          '服务地址需使用 https，本机或局域网服务可使用 http',
        AiProviderUrlError.insecureRemote =>
          '为保护数据安全，公网服务地址必须是 https，本机或局域网可使用 http',
      },
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
    final expectedAccessToken = provider.apiKey.trim();
    final expectedRefreshToken = provider.oauthRefreshToken.trim();
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
        if ((expectedAccessToken.isNotEmpty &&
                current.apiKey.trim() != expectedAccessToken) ||
            (expectedRefreshToken.isNotEmpty &&
                current.oauthRefreshToken.trim() != expectedRefreshToken)) {
          return;
        }
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

    // Keep the normal button on Cockpit's browser PKCE flow. Device
    // authorization is an explicit optional API, but its user-code endpoint
    // is region-gated and returns unsupported_country_region on some mobile
    // exits before a browser/VPN can be used. Android still gets the native
    // callback keep-alive and isolated Chrome session below.
    if (_busy.contains(provider.id)) return;
    setState(() => _busy.add(provider.id));
    try {
      final session = await OpenAiCodexOAuth.service.start(
        providerId: provider.id,
        authorizationUrl: raw,
      );
      final authorizationUri = Uri.parse(session.authorizationUrl);
      final isolated = Platform.isAndroid &&
          await OpenAiCodexOAuthKeepAlive.openEphemeralBrowser(
            authorizationUri.toString(),
          );
      final incognito = !isolated &&
          Platform.isAndroid &&
          await OpenAiCodexOAuthKeepAlive.openIncognitoBrowser(
            authorizationUri.toString(),
          );
      final chrome = !isolated &&
          !incognito &&
          Platform.isAndroid &&
          await OpenAiCodexOAuthKeepAlive.openChromeBrowser(
            authorizationUri.toString(),
          );
      final opened = isolated ||
          incognito ||
          chrome ||
          await launchUrl(
            authorizationUri,
            mode: openAiOAuthLaunchMode(),
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
    // Persist the token exchange before attempting model discovery. OAuth
    // login and catalogue discovery are separate network operations; a
    // transient VPN/proxy or 401 must not make a successful login disappear.
    final fallbackModels = <String>[];
    final seenFallback = <String>{};
    for (final candidate in [
      draft.selectedModel,
      provider.selectedModel,
      provider.model,
      AiProviderConfig.openAiCodexDefaultModel,
    ]) {
      final value = candidate.trim();
      if (value.isNotEmpty && seenFallback.add(value)) {
        fallbackModels.add(value);
      }
    }
    var saved = await context.read<AppRepository>().saveAiOAuthTokens(
          providerId: provider.id,
          tokens: tokens,
          models: fallbackModels,
        );
    draft.apiKey.text = saved.apiKey;
    draft.baseUrl.text = saved.baseUrl;
    draft.model.text = saved.model;
    draft.models
      ..clear()
      ..addAll(saved.models);
    draft.endpointType = saved.endpointType;
    draft.authMethod = saved.authMethod;

    List<String> models = const [];
    Object? modelFetchError;
    Object? probeError;
    try {
      // Route discovery through the same config path as normal requests. It
      // shares refresh-token persistence and retries an expired/rotated access
      // token instead of querying the just-exchanged token in isolation.
      models = await LlmQuery.fetchModels(_formConfig(saved, draft));
    } catch (error) {
      // Token exchange is the login result.  A transient /codex/models
      // failure must not discard a valid OAuth account; save a known official
      // model and let the user refresh the catalogue later.
      modelFetchError = error;
    }
    if (models.isNotEmpty) {
      final modelNames = <String>[];
      final seen = <String>{};
      for (final candidate in models) {
        final value = candidate.trim();
        if (value.isNotEmpty && seen.add(value)) modelNames.add(value);
      }
      final latest = context.read<AppRepository>().aiProviderById(saved.id);
      if (latest != null && modelNames.isNotEmpty) {
        await context.read<AppRepository>().saveAiConfiguredProvider(
              latest.copyWith(
                model: modelNames.first,
                models: modelNames,
              ),
            );
        saved = context.read<AppRepository>().aiProviderById(saved.id) ??
            latest.copyWith(model: modelNames.first, models: modelNames);
      }
    }
    saved = context.read<AppRepository>().aiProviderById(saved.id) ?? saved;
    draft.apiKey.text = saved.apiKey;
    draft.baseUrl.text = saved.baseUrl;
    draft.model.text = saved.model;
    draft.models
      ..clear()
      ..addAll(saved.models);
    draft.endpointType = saved.endpointType;
    draft.authMethod = saved.authMethod;
    if (modelFetchError == null) {
      try {
        await LlmQuery.testConnection(
          _formConfig(saved, draft).copyWith(model: saved.selectedModel),
        );
      } catch (error) {
        probeError = error;
      }
    }
    final verificationStatus = modelFetchError != null
        ? _verificationStatusForError(modelFetchError!)
        : probeError != null
            ? _verificationStatusForError(probeError!)
            : AiAccountVerificationStatus.available;
    try {
      await context.read<AppRepository>().recordAiProviderVerification(
            saved.id,
            status: verificationStatus.name,
            message: _shortError(probeError ?? modelFetchError ?? ''),
          );
    } catch (_) {}
    if (mounted) {
      setState(() {});
      showAppToast(
        context,
        modelFetchError != null
            ? 'GPT 已授权，但模型目录暂时失败，可稍后点“获取模型”'
            : probeError != null
                ? 'GPT 已授权，${_shortError(probeError)}'
                : 'GPT 已授权，获取到 ${saved.models.length} 个模型，连接测试成功',
        icon: modelFetchError == null && probeError == null
            ? Icons.check_circle_outline
            : Icons.info_outline,
      );
    }
  }

  Future<void> _importAccountsFromFile() async {
    if (_busy.isNotEmpty) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
        // Android document providers may return a content:// identifier with
        // no directly readable filesystem path. Keep a stream fallback so a
        // valid Cockpit export is not rejected just because it came from
        // Drive, Downloads, or another document provider.
        withReadStream: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.readStream == null
              ? null
              : await file.readStream!.fold<List<int>>(
                  <int>[],
                  (buffer, chunk) => buffer..addAll(chunk),
                )) ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      final text = bytes == null ? '' : AiAccountJsonCodec.decodeBytes(bytes);
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
    try {
      final result = await AiAccountImportController().import(
        AppRepositoryAiAccountImportAdapter(repo),
        [
          for (final choice in selections)
            AiAccountImportRequest(
              account: choice.account,
              action: choice.action,
              existingProviderId: choice.action == AiAccountImportAction.update
                  ? choice.duplicate?.id
                  : null,
              enabled: choice.enabled,
            ),
        ],
      );
      if (mounted) {
        final suffix = [
          if (result.skipped > 0) '跳过 ${result.skipped}',
          if (result.failed > 0)
            '问题 ${result.failed}（${result.issues.take(2).map((issue) => issue.summary).join('；')}）',
          if (result.verificationSkipped > 0)
            '停用账号未验证 ${result.verificationSkipped}',
          for (final status in AiAccountVerificationStatus.values)
            if ((result.verificationCounts[status] ?? 0) > 0)
              '${status.label} ${result.verificationCounts[status]}',
          if (parsed.warnings.isNotEmpty) parsed.warnings.join('；'),
        ].join('；');
        showAppToast(
          context,
          '已导入 ${result.imported} 个 AI 账号${suffix.isEmpty ? '' : '（$suffix）'}',
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
        title: const Text('AI 账号'),
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
                onVerify: () => _verifyProvider(provider, _draftFor(provider)),
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

class _AiAccountImportChoice {
  final AiAccountImportEntry account;
  final AiConfiguredProvider? duplicate;
  AiAccountImportAction action;
  bool enabled;

  _AiAccountImportChoice({
    required this.account,
    required this.duplicate,
  })  : action = duplicate == null
            ? AiAccountImportAction.create
            : AiAccountImportAction.update,
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
        AiAccountImportAction.update => AiAccountImportAction.create,
        AiAccountImportAction.create => AiAccountImportAction.skip,
        AiAccountImportAction.skip => AiAccountImportAction.update,
      };
    });
  }

  String _actionLabel(_AiAccountImportChoice choice) => switch (choice.action) {
        AiAccountImportAction.create =>
          choice.duplicate == null ? '新建账号' : '新建副本',
        AiAccountImportAction.update => '更新已有',
        AiAccountImportAction.skip => '跳过',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedCount = _choices
        .where((choice) => choice.action != AiAccountImportAction.skip)
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
                        choice.action == AiAccountImportAction.skip;
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
  final VoidCallback onVerify;
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
    required this.onVerify,
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
                      child: AppPlainIconButton.custom(
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
                          semanticLabel:
                              draft.obscureKey ? '显示 API Key' : '隐藏 API Key',
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppPillButton(
                        label: '验证账号',
                        onPressed: busy ? null : onVerify,
                      ),
                      AppPillButton(
                        label: '测试连接',
                        onPressed: busy ? null : onTest,
                      ),
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


/// 隐私与数据：所有人都能进（01 §4），从设置首页「AI」分组打开。
class AiPrivacyDataPage extends StatelessWidget {
  const AiPrivacyDataPage({super.key});

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
                  subtitle: '切换服务后，会要求用户重新确认',
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
  final text = switch (e) {
    OpenAiCodexOAuthException(:final message) => message,
    LlmQueryException(:final message) => message,
    _ => e
        .toString()
        .replaceFirst('LlmQueryException: ', '')
        .replaceFirst('OpenAiCodexOAuthException: ', '')
        .trim(),
  };
  final normalized = AiLogger.sanitizeErrorForDisplay(text)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.length <= 120) return normalized;
  return '${normalized.substring(0, 117)}…';
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
