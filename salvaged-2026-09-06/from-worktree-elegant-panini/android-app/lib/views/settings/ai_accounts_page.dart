import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/llm_query.dart';
import '../../core/ai/model_fetcher.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import 'model_manager_sheet.dart';

/// AI 服务配置数据模型
class AiServiceConfig {
  final String id;
  final String emoji;
  final String name;
  final String? apiKey;
  final String? baseUrl;
  final String? defaultModel;
  final bool isCustom;

  const AiServiceConfig({
    required this.id,
    required this.emoji,
    required this.name,
    this.apiKey,
    this.baseUrl,
    this.defaultModel,
    this.isCustom = false,
  });

  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  AiServiceConfig copyWith({
    String? emoji,
    String? name,
    String? apiKey,
    String? baseUrl,
    String? defaultModel,
  }) =>
      AiServiceConfig(
        id: id,
        emoji: emoji ?? this.emoji,
        name: name ?? this.name,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        defaultModel: defaultModel ?? this.defaultModel,
        isCustom: isCustom,
      );
}

/// AI 账号设置页面：多服务商管理
class AiAccountsPage extends StatefulWidget {
  const AiAccountsPage({super.key});

  @override
  State<AiAccountsPage> createState() => _AiAccountsPageState();
}

class _AiAccountsPageState extends State<AiAccountsPage> {
  final Map<String, bool> _expanded = {};
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, TextEditingController> _modelControllers = {};
  final Map<String, bool> _obscure = {};
  final Map<String, bool> _testing = {};

  late List<AiServiceConfig> _services;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final deepSeekKey = repo.deepSeekApiKey;

    _services = [
      AiServiceConfig(
        id: 'deepseek',
        emoji: '🤖',
        name: 'DeepSeek',
        apiKey: deepSeekKey,
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
      ),
      const AiServiceConfig(
        id: 'openai',
        emoji: '🧠',
        name: 'OpenAI',
      ),
      const AiServiceConfig(
        id: 'claude',
        emoji: '🎯',
        name: 'Claude',
      ),
    ];

    for (final svc in _services) {
      _expanded[svc.id] = false;
      _obscure[svc.id] = true;
      _testing[svc.id] = false;
      _keyControllers[svc.id] = TextEditingController(text: svc.apiKey ?? '');
      _urlControllers[svc.id] = TextEditingController(text: svc.baseUrl ?? '');
      _modelControllers[svc.id] =
          TextEditingController(text: svc.defaultModel ?? '');
    }
  }

  @override
  void dispose() {
    for (final ctrl in _keyControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _urlControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _modelControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String id) async {
    if (id == 'deepseek') {
      final repo = context.read<AppRepository>();
      await repo.saveApiKey(_keyControllers[id]!.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('已保存'),
              ],
            ),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          ),
        );
      }
    }
  }

  Future<void> _test(String id) async {
    final key = _keyControllers[id]!.text.trim();
    if (key.isEmpty) {
      _showResult(ok: false, message: '先填 API Key 再测试');
      return;
    }
    setState(() => _testing[id] = true);
    String? error;
    try {
      if (id == 'deepseek') {
        await LlmQuery.testConnection(key);
      } else {
        await Future.delayed(const Duration(seconds: 1));
        throw Exception('暂不支持此服务商测试');
      }
    } on LlmQueryException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => _testing[id] = false);
    }
    if (!mounted) return;
    _showResult(
      ok: error == null,
      message: error == null ? '连接成功 🎉' : '连接失败：$error',
    );
  }

  void _showResult({required bool ok, required String message}) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? scheme.primary : scheme.error,
          size: 32,
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _deleteCustom(String id) {
    setState(() {
      _services.removeWhere((s) => s.id == id);
      _keyControllers[id]?.dispose();
      _urlControllers[id]?.dispose();
      _modelControllers[id]?.dispose();
      _keyControllers.remove(id);
      _urlControllers.remove(id);
      _modelControllers.remove(id);
      _expanded.remove(id);
      _obscure.remove(id);
      _testing.remove(id);
    });
  }

  Future<void> _fetchModels(String id) async {
    final key = _keyControllers[id]!.text.trim();
    final url = _urlControllers[id]!.text.trim();

    if (key.isEmpty || url.isEmpty) {
      _showResult(ok: false, message: '请先填写 API Key 和 Base URL');
      return;
    }

    // 显示加载对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在获取模型列表...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final models = await AiModelFetcher.fetchAvailableModels(
        baseUrl: url,
        apiKey: key,
      );

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (models.isEmpty) {
        _showResult(ok: false, message: '未获取到任何模型');
        return;
      }

      // 打开模型管理器
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => ModelManagerSheet(
          providerId: id,
          availableModels: models,
        ),
      );

      if (result != null && result.isNotEmpty && mounted) {
        // 保存筛选后的模型列表
        final repo = context.read<AppRepository>();
        await repo.saveFilteredModels(
          providerId: id,
          modelIds: result,
        );

        // 更新默认模型输入框（显示第一个选中的模型）
        _modelControllers[id]!.text = result.first;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('已保存 ${result.length} 个模型'),
                ],
              ),
              duration: const Duration(milliseconds: 1500),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            ),
          );
        }
      }
    } on AiModelFetchException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框
      _showResult(ok: false, message: '获取失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框
      _showResult(ok: false, message: '未知错误：$e');
    }
  }

  void _addCustomService() {
    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newService = AiServiceConfig(
      id: newId,
      emoji: '⚙️',
      name: '自定义服务',
      isCustom: true,
    );
    setState(() {
      _services.add(newService);
      _expanded[newId] = true;
      _obscure[newId] = true;
      _testing[newId] = false;
      _keyControllers[newId] = TextEditingController();
      _urlControllers[newId] = TextEditingController();
      _modelControllers[newId] = TextEditingController();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 服务配置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 24),
            onPressed: _addCustomService,
            tooltip: '添加自定义服务',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '配置多个 AI 服务商，根据用途自动选择最合适的模型',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final svc in _services) _buildServiceCard(svc, scheme),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addCustomService,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('添加自定义服务'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard(AiServiceConfig svc, ColorScheme scheme) {
    final isExpanded = _expanded[svc.id] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: svc.isConfigured
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded[svc.id] = !isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(svc.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          svc.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: svc.isConfigured
                                    ? Colors.green
                                    : scheme.outlineVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              svc.isConfigured ? '已配置' : '未配置',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                            if (_testing[svc.id] == true) ...{
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '测试中...',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                    ),
                              ),
                            },
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (svc.isCustom) ...[
                    Text(
                      '服务名称',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: '例如：私有部署',
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'API Key',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyControllers[svc.id],
                    obscureText: _obscure[svc.id] ?? true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxx',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure[svc.id] == true
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                            () => _obscure[svc.id] = !(_obscure[svc.id]!)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Base URL',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlControllers[svc.id],
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: 'https://api.example.com',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '默认模型',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelControllers[svc.id],
                          decoration: InputDecoration(
                            hintText: '例如：gpt-4',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _fetchModels(svc.id),
                        icon: const Icon(Icons.cloud_download, size: 18),
                        label: const Text('获取'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _save(svc.id),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('保存'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing[svc.id] == true
                              ? null
                              : () => _test(svc.id),
                          icon: _testing[svc.id] == true
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('测试'),
                        ),
                      ),
                    ],
                  ),
                  if (svc.isCustom) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _deleteCustom(svc.id),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除此服务'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(
                            color: scheme.error.withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
