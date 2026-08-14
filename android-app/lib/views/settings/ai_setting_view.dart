import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/llm_query.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

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
    final configured = providers.where((provider) => provider.hasKey).length;
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
    if (!config.hasKey) {
      showAppToast(context, '先填写 API Key', icon: Icons.info_outline);
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
    if (!config.hasKey) {
      showAppToast(context, '先填写 API Key', icon: Icons.info_outline);
      return;
    }
    if (!_ensureSecureBaseUrl(provider, draft)) return;
    final result = await showBlurSheet<List<String>>(
      context,
      child: _ProviderModelManagerSheet(
        providerLabel: draft.label,
        config: config,
        savedModels: draft.models,
      ),
    );
    if (result == null || !mounted) return;
    final selectedModel = result.contains(draft.selectedModel)
        ? draft.selectedModel
        : result.firstOrNull;
    try {
      final updated = provider.copyWith(
        displayName: draft.displayName.text.trim(),
        baseUrl: draft.baseUrl.text.trim(),
        apiKey: draft.apiKey.text.trim(),
        model: selectedModel,
        models: result,
      );
      await context.read<AppRepository>().saveAiConfiguredProvider(updated);
      if (!mounted) return;
      setState(() {
        draft.models
          ..clear()
          ..addAll(result);
        draft.selectedModel = selectedModel ?? '';
      });
      showAppToast(context, '已保留 ${result.length} 个模型');
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
    return provider.toConfig().copyWith(
          apiKey: draft.apiKey.text,
          baseUrl: draft.baseUrl.text,
          model: _selectedModel(draft),
          displayName: draft.displayName.text,
        );
  }

  String _selectedModel(_ProviderDraft draft) {
    final selected = draft.selectedModel.trim();
    if (selected.isNotEmpty) return selected;
    return draft.models.firstOrNull ?? AiProviderConfig.customDefaultModel;
  }

  static bool _isInsecureBaseUrl(String raw) {
    final url = raw.trim().toLowerCase();
    if (!url.startsWith('http://')) return false;
    final host = Uri.tryParse(url)?.host ?? '';
    return !(host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<AppRepository>().aiProviders;

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
            const SettingsSectionLabel('服务商'),
            for (final provider in providers)
              _ProviderCard(
                key: ValueKey(provider.id),
                provider: provider,
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
                onDelete:
                    provider.builtIn ? null : () => _deleteProvider(provider),
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
  final List<String> models;
  bool obscureKey = true;

  _ProviderDraft(AiConfiguredProvider provider)
      : displayName = TextEditingController(text: provider.displayName),
        apiKey = TextEditingController(text: provider.apiKey),
        baseUrl = TextEditingController(text: provider.baseUrl),
        model = TextEditingController(text: provider.model),
        models = List<String>.from(provider.models);

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
  }
}

class _ProviderCard extends StatelessWidget {
  final AiConfiguredProvider provider;
  final _ProviderDraft draft;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onManageModels;
  final VoidCallback? onDelete;

  const _ProviderCard({
    super.key,
    required this.provider,
    required this.draft,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onSave,
    required this.onTest,
    required this.onManageModels,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = draft.selectedModel.trim().isEmpty
        ? (draft.models.firstOrNull ?? provider.model)
        : draft.selectedModel.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: appCardDecoration(scheme),
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
                                  fontWeight: FontWeight.normal,
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
                          provider.hasKey || draft.apiKey.text.trim().isNotEmpty
                              ? model
                              : '未配置 API Key',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.secondary(scheme).copyWith(
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.trash, size: 17),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 18,
                    color: scheme.onSurfaceVariant,
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
                    label: 'API Key',
                    child: TextField(
                      controller: draft.apiKey,
                      obscureText: draft.obscureKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontWeight: FontWeight.normal),
                      decoration: iosInputDecoration(
                        context,
                        hint: '输入 API Key',
                      ).copyWith(
                        filled: true,
                        fillColor: Colors.transparent,
                        suffixIcon: IconButton(
                          icon: Icon(
                            draft.obscureKey
                                ? CupertinoIcons.eye
                                : CupertinoIcons.eye_slash,
                            size: 18,
                          ),
                          onPressed: () => _toggleObscure(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
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
                      ).copyWith(
                        filled: true,
                        fillColor: Colors.transparent,
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
                      ).copyWith(
                        filled: true,
                        fillColor: Colors.transparent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppLabeledField(
                    label: '模型列表',
                    child: _ProviderModelListBox(
                      draft: draft,
                      availableModels: draft.models,
                      onFetchModels: onManageModels,
                      isFetching: busy,
                      onTest: onTest,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AppPillButton(
                        label: busy ? '获取中' : '从上游获取',
                        onPressed: busy ? null : onManageModels,
                      ),
                      const SizedBox(width: 8),
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
        style: const TextStyle(fontWeight: FontWeight.normal),
        decoration: iosInputDecoration(
          context,
          hint: AiProviderConfig.customDefaultModel,
        ).copyWith(
          filled: true,
          fillColor: Colors.transparent,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
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

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 1.4,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
      ),
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final current = repo.aiProviderById(repo.recordAiProviderId);
    _selectedProviderId = current?.hasKey == true
        ? current?.id
        : repo.aiProviders.where((provider) => provider.hasKey).firstOrNull?.id;
  }

  Future<void> _save() async {
    final id = _selectedProviderId;
    if (_saving || id == null || id.isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().setRecordAiProvider(id);
      if (mounted) showAppToast(context, '普通记账服务商已保存');
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

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<AppRepository>().aiProviders;
    final selected = providers.any(
            (provider) => provider.id == _selectedProviderId && provider.hasKey)
        ? _selectedProviderId
        : providers.where((provider) => provider.hasKey).firstOrNull?.id;
    if (selected != _selectedProviderId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedProviderId = selected);
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
              onPressed: _saving || selected == null ? null : _save,
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
                text: '这里仅设置普通记账使用的服务商。喵助手和报告跟随当前对话模型。',
              ),
            ),
            const SettingsSectionLabel('普通记账'),
            SettingsGroup(
              children: [
                for (final provider in providers)
                  SettingsRow(
                    leading: Icon(
                      provider.type == AiProviderType.deepseek
                          ? CupertinoIcons.sparkles
                          : CupertinoIcons.cloud,
                    ),
                    title: provider.label,
                    subtitle: provider.hasKey ? '已配置 API Key' : '未配置 API Key',
                    trailing: _RadioDot(selected: provider.id == selected),
                    onTap: provider.hasKey
                        ? () =>
                            setState(() => _selectedProviderId = provider.id)
                        : null,
                  ),
              ],
            ),
            if (providers.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _CaptionText('请先在 AI 账号设置中添加服务商。'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
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

class _ProviderModelManagerSheet extends StatefulWidget {
  final String providerLabel;
  final AiProviderConfig config;
  final List<String> savedModels;

  const _ProviderModelManagerSheet({
    required this.providerLabel,
    required this.config,
    required this.savedModels,
  });

  @override
  State<_ProviderModelManagerSheet> createState() =>
      _ProviderModelManagerSheetState();
}

class _ProviderModelManagerSheetState
    extends State<_ProviderModelManagerSheet> {
  late final List<String> _kept;
  final Set<String> _removed = {};
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
                : () => Navigator.pop(context, List<String>.from(_kept)),
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
                            style: const TextStyle(fontSize: 14),
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
