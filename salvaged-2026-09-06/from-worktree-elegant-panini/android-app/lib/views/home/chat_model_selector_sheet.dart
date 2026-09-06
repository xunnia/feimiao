import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/llm_query.dart';
import '../../data/app_repository.dart';

/// 喵助手模型选择器底部抽屉
Future<void> showChatModelSelectorSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ChatModelSelectorSheet(),
  );
}

class _ChatModelSelectorSheet extends StatefulWidget {
  const _ChatModelSelectorSheet();

  @override
  State<_ChatModelSelectorSheet> createState() =>
      _ChatModelSelectorSheetState();
}

class _ChatModelSelectorSheetState extends State<_ChatModelSelectorSheet> {
  List<String>? _models;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final repo = context.read<AppRepository>();
    final config = await repo.aiProviderConfigFor(AiTaskType.chat);
    if (config == null) return;

    if (config.isDeepSeek) {
      // DeepSeek 使用内置列表
      setState(() {
        _models = ['deepseek-v4-flash', 'deepseek-chat'];
        _loading = false;
      });
    } else {
      // 自定义服务商：从数据库读取筛选后的模型列表
      try {
        final rows = await repo.getFilteredModels(config.providerId ?? 'custom');
        if (mounted) {
          final modelIds = rows.map((r) => r['model_id'] as String).toList();
          setState(() {
            _models = modelIds.isEmpty ? null : modelIds;
            _loading = false;
            _error = modelIds.isEmpty ? '请先在 AI 账号设置中获取并筛选模型' : null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _models = null;
            _loading = false;
            _error = '加载失败：$e';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();

    return FutureBuilder<AiProviderConfig?>(
      future: repo.aiProviderConfigFor(AiTaskType.chat),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final config = snapshot.data!;
        final currentModel = config.model;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择喵助手模型',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.providerLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),

          // 模型列表
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else if (_models == null || _models!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 48,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error ?? '无可用模型',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null && _error!.contains('请先在')) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // TODO: 跳转到 AI 账号设置页面
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('前往设置'),
                    ),
                  ],
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _models!.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final model = _models![index];
                  final selected = model == currentModel;

                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      model,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    onTap: () async {
                      await repo.setChatModelOverride(model);
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
      },
    );
  }
}
