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
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';

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
                    value:
                        '${repo.aiRouteModeFor(AiTaskType.recordParse).label} · ${repo.aiResolvedProviderLabelFor(AiTaskType.recordParse)}',
                  ),
                  onTap: () => _push(
                    context,
                    const _AiUsageRoutingPage(),
                  ),
                ),
                SettingsRow(
                  title: '高级参数设置',
                  trailing: _ValueChevron(
                    value:
                        '${repo.aiEndpointTypeFor(AiTaskType.report).label} · ${repo.aiReasoningEffortFor(AiTaskType.report).label}',
                  ),
                  onTap: () => _push(
                    context,
                    const _AiAdvancedSettingsPage(),
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
                '自动分配会根据任务选择可用服务：记账优先速度，报告优先分析能力。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _accountSummary(AppRepository repo) {
    final selected = repo.aiProviderLabel(repo.aiProviderType);
    final keyReady = repo.aiProviderType == AiProviderType.custom
        ? (repo.customAiApiKey?.trim().isNotEmpty ?? false)
        : (repo.deepSeekApiKey?.trim().isNotEmpty ?? false);
    return '$selected · ${keyReady ? '已配置' : '未配置'}';
  }
}

class _AiAccountSettingsPage extends StatefulWidget {
  const _AiAccountSettingsPage();

  @override
  State<_AiAccountSettingsPage> createState() => _AiAccountSettingsPageState();
}

class _AiAccountSettingsPageState extends State<_AiAccountSettingsPage> {
  late AiProviderType _provider;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelCtrl;
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _provider = repo.aiProviderType;
    _displayNameCtrl = TextEditingController(text: repo.customAiDisplayName);
    _keyCtrl = TextEditingController(text: _apiKeyFor(repo, _provider));
    _baseUrlCtrl = TextEditingController(text: repo.customAiBaseUrl);
    _modelCtrl = TextEditingController(text: repo.customAiModel);
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _keyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  String _apiKeyFor(AppRepository repo, AiProviderType type) {
    return type == AiProviderType.custom
        ? (repo.customAiApiKey ?? '')
        : (repo.deepSeekApiKey ?? '');
  }

  void _switchProvider(AiProviderType type) {
    if (_provider == type) return;
    final repo = context.read<AppRepository>();
    setState(() {
      _provider = type;
      _keyCtrl.text = _apiKeyFor(repo, type);
      if (type == AiProviderType.custom) {
        if (_displayNameCtrl.text.trim().isEmpty) {
          _displayNameCtrl.text = '自定义';
        }
        if (_baseUrlCtrl.text.trim().isEmpty) {
          _baseUrlCtrl.text = AiProviderConfig.customDefaultBaseUrl;
        }
        if (_modelCtrl.text.trim().isEmpty) {
          _modelCtrl.text = AiProviderConfig.customDefaultModel;
        }
      }
    });
  }

  /// 自定义服务地址必须走 https：http 明文会把 API Key 和账本上下文裸奔。
  /// 本机调试地址（localhost / 127.0.0.1 / ::1）除外。
  static bool _isInsecureBaseUrl(String raw) {
    final url = raw.trim().toLowerCase();
    if (!url.startsWith('http://')) return false;
    final host = Uri.tryParse(url)?.host ?? '';
    return !(host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  /// 校验自定义地址，非 https 时 toast 提示并返回 false（拦下保存/测试）。
  /// key 为空时放行（没有 key 就不会发出任何数据，且「清除 Key」不能被拦）。
  bool _ensureSecureBaseUrl() {
    if (_provider != AiProviderType.custom) return true;
    if (_keyCtrl.text.trim().isEmpty) return true;
    if (!_isInsecureBaseUrl(_baseUrlCtrl.text)) return true;
    showAppToast(
      context,
      '为保护数据安全，自定义服务地址必须是 https',
      icon: Icons.error_outline,
    );
    return false;
  }

  AiProviderConfig _formConfig() {
    if (_provider == AiProviderType.custom) {
      return AiProviderConfig.custom(
        apiKey: _keyCtrl.text,
        baseUrl: _baseUrlCtrl.text,
        model: _modelCtrl.text,
        displayName: _displayNameCtrl.text,
      );
    }
    return AiProviderConfig.deepSeek(apiKey: _keyCtrl.text);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_ensureSecureBaseUrl()) return;
    setState(() => _saving = true);
    final repo = context.read<AppRepository>();
    try {
      await repo.saveAiProviderConfig(
        type: _provider,
        apiKey: _keyCtrl.text,
        customDisplayName: _displayNameCtrl.text,
        customBaseUrl: _baseUrlCtrl.text,
        customModel: _modelCtrl.text,
        reportModel: repo.reportAiModel,
      );
      if (mounted) showAppToast(context, 'AI 账号已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final config = _formConfig();
    if (!config.hasKey) {
      showAppToast(context, '先填写 API Key', icon: Icons.info_outline);
      return;
    }
    if (!_ensureSecureBaseUrl()) return;
    setState(() => _testing = true);
    try {
      await LlmQuery.testConnection(config);
      if (mounted) {
        showAppToast(context, '${config.providerLabel} 连接成功');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          '连接失败：${_shortError(e)}',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearCurrentKey() async {
    _keyCtrl.clear();
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final isCustom = _provider == AiProviderType.custom;
    final hasSavedKey = _provider == AiProviderType.custom
        ? (repo.customAiApiKey?.trim().isNotEmpty ?? false)
        : (repo.deepSeekApiKey?.trim().isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('AI 账号设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const SettingsSectionLabel('服务'),
            SettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ChoiceWrap<AiProviderType>(
                    values: AiProviderType.values,
                    value: _provider,
                    labelOf: (type) => repo.aiProviderLabel(type),
                    onChanged: _switchProvider,
                  ),
                ),
              ],
            ),
            const SettingsSectionLabel('密钥'),
            SettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: AppLabeledField(
                    label: 'API Key',
                    child: TextField(
                      controller: _keyCtrl,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: iosInputDecoration(
                        context,
                        hint: 'sk-xxxxxxxxxxxxxxxx',
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (isCustom) ...[
              const SettingsSectionLabel('自定义服务'),
              SettingsGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: AppLabeledField(
                      label: '服务名称',
                      child: TextField(
                        controller: _displayNameCtrl,
                        decoration: iosInputDecoration(
                          context,
                          hint: '例如 GPT 中转站',
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: AppLabeledField(
                      label: '基础地址',
                      child: TextField(
                        controller: _baseUrlCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.url,
                        decoration: iosInputDecoration(
                          context,
                          hint: AiProviderConfig.customDefaultBaseUrl,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: AppLabeledField(
                      label: '普通模型',
                      child: TextField(
                        controller: _modelCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: iosInputDecoration(
                          context,
                          hint: AiProviderConfig.customDefaultModel,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: _CaptionText(
                isCustom
                    ? '适用于 GPT 官方、中转站或其他 OpenAI 兼容服务。API Key 只保存在本机。'
                    : '适合记账等高频任务，响应快且成本更容易控制。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_saving || _testing) ? null : _testConnection,
                      child: Text(_testing ? '测试中…' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_saving || _testing) ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
            ),
            if (hasSavedKey)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    // 守不用红铁律：危险操作用超支橙。
                    foregroundColor: AppColors.warning,
                  ),
                  onPressed: (_saving || _testing) ? null : _clearCurrentKey,
                  child: Text('清除${repo.aiProviderLabel(_provider)}密钥'),
                ),
              ),
          ],
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
  late AiRouteMode _recordRouteMode;
  late AiRouteMode _chatRouteMode;
  late AiRouteMode _reportRouteMode;
  late AiProviderType _recordProvider;
  late AiProviderType _chatProvider;
  late AiProviderType _reportProvider;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _recordRouteMode = repo.aiRouteModeFor(AiTaskType.recordParse);
    _chatRouteMode = repo.aiRouteModeFor(AiTaskType.chatQuery);
    _reportRouteMode = repo.aiRouteModeFor(AiTaskType.report);
    _recordProvider = repo.aiProviderTypeFor(AiTaskType.recordParse);
    _chatProvider = repo.aiProviderTypeFor(AiTaskType.chatQuery);
    _reportProvider = repo.aiProviderTypeFor(AiTaskType.report);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().saveAiTaskRouting(
            recordRouteMode: _recordRouteMode,
            chatRouteMode: _chatRouteMode,
            reportRouteMode: _reportRouteMode,
            recordProviderType: _recordProvider,
            chatProviderType: _chatProvider,
            reportProviderType: _reportProvider,
          );
      if (mounted) showAppToast(context, '用途分配已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('用途分配'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _InfoBox(
                text:
                    '自动模式会按任务选择更合适的 AI：普通记账优先速度，报告生成优先深度。没有配置对应密钥时，会自动回退到可用服务。',
              ),
            ),
            const SettingsSectionLabel('分配规则'),
            SettingsGroup(
              children: [
                _RouteEditor(
                  task: AiTaskType.recordParse,
                  subtitle: '一句话记账、截图识别、导入分类，优先最快响应',
                  mode: _recordRouteMode,
                  provider: _recordProvider,
                  resolvedLabel: _resolvedLabel(
                    repo,
                    AiTaskType.recordParse,
                    _recordRouteMode,
                    _recordProvider,
                  ),
                  onModeChanged: (value) =>
                      setState(() => _recordRouteMode = value),
                  onProviderChanged: (value) =>
                      setState(() => _recordProvider = value),
                ),
                _RouteEditor(
                  task: AiTaskType.chatQuery,
                  subtitle: '日常查账、消费问答，优先稳定和响应速度',
                  mode: _chatRouteMode,
                  provider: _chatProvider,
                  resolvedLabel: _resolvedLabel(
                    repo,
                    AiTaskType.chatQuery,
                    _chatRouteMode,
                    _chatProvider,
                  ),
                  onModeChanged: (value) =>
                      setState(() => _chatRouteMode = value),
                  onProviderChanged: (value) =>
                      setState(() => _chatProvider = value),
                ),
                _RouteEditor(
                  task: AiTaskType.report,
                  subtitle: '周报、月报、年报，优先结构、洞察和长文质量',
                  mode: _reportRouteMode,
                  provider: _reportProvider,
                  resolvedLabel: _resolvedLabel(
                    repo,
                    AiTaskType.report,
                    _reportRouteMode,
                    _reportProvider,
                  ),
                  onModeChanged: (value) =>
                      setState(() => _reportRouteMode = value),
                  onProviderChanged: (value) =>
                      setState(() => _reportProvider = value),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存用途分配'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resolvedLabel(
    AppRepository repo,
    AiTaskType task,
    AiRouteMode mode,
    AiProviderType provider,
  ) {
    final resolved =
        mode == AiRouteMode.fixed ? provider : _autoProviderTypeFor(repo, task);
    return repo.aiProviderLabel(resolved);
  }

  AiProviderType _autoProviderTypeFor(AppRepository repo, AiTaskType task) {
    final hasDeepSeek = repo.deepSeekApiKey?.trim().isNotEmpty ?? false;
    final hasCustom = repo.customAiApiKey?.trim().isNotEmpty ?? false;
    if (task == AiTaskType.report) {
      if (hasCustom) return AiProviderType.custom;
      if (hasDeepSeek) return AiProviderType.deepseek;
      return AiProviderType.custom;
    }
    if (hasDeepSeek) return AiProviderType.deepseek;
    if (hasCustom) return AiProviderType.custom;
    return AiProviderType.deepseek;
  }
}

class _AiAdvancedSettingsPage extends StatefulWidget {
  const _AiAdvancedSettingsPage();

  @override
  State<_AiAdvancedSettingsPage> createState() =>
      _AiAdvancedSettingsPageState();
}

class _AiAdvancedSettingsPageState extends State<_AiAdvancedSettingsPage> {
  late final TextEditingController _normalModelCtrl;
  late final TextEditingController _reportModelCtrl;
  late AiEndpointType _chatEndpoint;
  late AiEndpointType _reportEndpoint;
  late AiReasoningEffort _chatReasoning;
  late AiReasoningEffort _reportReasoning;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _normalModelCtrl = TextEditingController(text: repo.customAiModel);
    _reportModelCtrl = TextEditingController(text: repo.reportAiModel);
    _chatEndpoint = repo.aiEndpointTypeFor(AiTaskType.chatQuery);
    _reportEndpoint = repo.aiEndpointTypeFor(AiTaskType.report);
    _chatReasoning = repo.aiReasoningEffortFor(AiTaskType.chatQuery);
    _reportReasoning = repo.aiReasoningEffortFor(AiTaskType.report);
  }

  @override
  void dispose() {
    _normalModelCtrl.dispose();
    _reportModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().saveAiAdvancedConfig(
            customModel: _normalModelCtrl.text,
            reportModel: _reportModelCtrl.text,
            chatEndpointType: _chatEndpoint,
            reportEndpointType: _reportEndpoint,
            chatReasoningEffort: _chatReasoning,
            reportReasoningEffort: _reportReasoning,
          );
      if (mounted) showAppToast(context, '高级参数已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('高级参数设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const SettingsSectionLabel('模型'),
            SettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: AppLabeledField(
                    label: '普通模型',
                    child: TextField(
                      controller: _normalModelCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: iosInputDecoration(
                        context,
                        hint: AiProviderConfig.customDefaultModel,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: AppLabeledField(
                    label: '报告模型',
                    child: TextField(
                      controller: _reportModelCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: iosInputDecoration(
                        context,
                        hint: AiProviderConfig.customReportDefaultModel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SettingsSectionLabel('接口'),
            SettingsGroup(
              children: [
                _ChoiceEditor<AiEndpointType>(
                  title: '喵助手接口',
                  subtitle: 'OpenAI 官方建议 Responses；普通兼容站可用 Chat Completions',
                  values: const [
                    AiEndpointType.auto,
                    AiEndpointType.chatCompletions,
                    AiEndpointType.responses,
                  ],
                  value: _chatEndpoint,
                  labelOf: (value) => value.label,
                  onChanged: (value) => setState(() => _chatEndpoint = value),
                ),
                _ChoiceEditor<AiEndpointType>(
                  title: '报告接口',
                  subtitle: '报告默认使用 Responses，方便长文和深度思考',
                  values: const [
                    AiEndpointType.auto,
                    AiEndpointType.chatCompletions,
                    AiEndpointType.responses,
                  ],
                  value: _reportEndpoint,
                  labelOf: (value) => value.label,
                  onChanged: (value) => setState(() => _reportEndpoint = value),
                ),
              ],
            ),
            const SettingsSectionLabel('思考深度'),
            SettingsGroup(
              children: [
                _ChoiceEditor<AiReasoningEffort>(
                  title: '喵助手',
                  subtitle: '日常问答建议 Low 或关闭，避免拖慢反馈',
                  values: const [
                    AiReasoningEffort.none,
                    AiReasoningEffort.low,
                    AiReasoningEffort.medium,
                    AiReasoningEffort.high,
                  ],
                  value: _chatReasoning,
                  labelOf: (value) => value.label,
                  onChanged: (value) => setState(() => _chatReasoning = value),
                ),
                _ChoiceEditor<AiReasoningEffort>(
                  title: '报告生成',
                  subtitle: '月报、年报建议 XHigh，换取更完整的分析',
                  values: const [
                    AiReasoningEffort.none,
                    AiReasoningEffort.medium,
                    AiReasoningEffort.high,
                    AiReasoningEffort.xhigh,
                  ],
                  value: _reportReasoning,
                  labelOf: (value) => value.label,
                  onChanged: (value) =>
                      setState(() => _reportReasoning = value),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: _CaptionText(
                '普通记账始终使用轻量接口并关闭思考，优先保证响应速度。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存高级参数'),
              ),
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

class _RouteEditor extends StatelessWidget {
  final AiTaskType task;
  final String subtitle;
  final AiRouteMode mode;
  final AiProviderType provider;
  final String resolvedLabel;
  final ValueChanged<AiRouteMode> onModeChanged;
  final ValueChanged<AiProviderType> onProviderChanged;

  const _RouteEditor({
    required this.task,
    required this.subtitle,
    required this.mode,
    required this.provider,
    required this.resolvedLabel,
    required this.onModeChanged,
    required this.onProviderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.label,
              style: AppType.rowTitle(Theme.of(context).colorScheme)),
          const SizedBox(height: 3),
          _MutedText(subtitle),
          const SizedBox(height: 12),
          _ChoiceWrap<AiRouteMode>(
            values: AiRouteMode.values,
            value: mode,
            labelOf: (value) => value.label,
            onChanged: onModeChanged,
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: mode == AiRouteMode.fixed
                ? Align(
                    key: const ValueKey('fixed'),
                    alignment: Alignment.centerLeft,
                    child: _ChoiceWrap<AiProviderType>(
                      values: AiProviderType.values,
                      value: provider,
                      labelOf: (value) => repo.aiProviderLabel(value),
                      onChanged: onProviderChanged,
                    ),
                  )
                : _AutoResolvedLine(
                    key: const ValueKey('auto'),
                    label: resolvedLabel,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceEditor<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<T> values;
  final T value;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  const _ChoiceEditor({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.rowTitle(Theme.of(context).colorScheme)),
          const SizedBox(height: 3),
          _MutedText(subtitle),
          const SizedBox(height: 12),
          _ChoiceWrap<T>(
            values: values,
            value: value,
            labelOf: labelOf,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  final List<T> values;
  final T value;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  const _ChoiceWrap({
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in values)
          _ChoiceChipButton(
            label: labelOf(item),
            selected: item == value,
            onTap: () => onChanged(item),
          ),
      ],
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : AppColors.hairline(scheme),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? scheme.primary : AppTextColor.secondary(scheme),
          ),
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

class _AutoResolvedLine extends StatelessWidget {
  final String label;

  const _AutoResolvedLine({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '自动选择：$label',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w400,
          ),
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
