import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../home/ai_chat_panel.dart';

/// AI 记账设置页：配置 DeepSeek API Key。
class AiSettingView extends StatefulWidget {
  const AiSettingView({super.key});

  @override
  State<AiSettingView> createState() => _AiSettingViewState();
}

class _AiSettingViewState extends State<AiSettingView> {
  late final TextEditingController _keyCtrl;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppRepository>().deepSeekApiKey ?? '';
    _keyCtrl = TextEditingController(text: existing);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = context.read<AppRepository>();
    setState(() => _saving = true);
    try {
      await repo.saveApiKey(_keyCtrl.text);
      if (mounted) showAppToast(context, 'API Key 已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // 说明卡片
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(scheme),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.smart_toy_outlined,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '什么是 AI 记账？',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '接入 DeepSeek 大模型后，你可以用一句话一次性记多笔账。\n'
                      '例如：「昨天买了20块肉、30的衣服、前天交房租1500」，'
                      'AI 会自动拆成 3 笔，识别分类和日期。\n\n'
                      'API Key 仅保存在本机，不会上传到任何服务器。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Key 输入区
            Text(
              'DeepSeek API Key',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                hintText: 'sk-xxxxxxxxxxxxxxxx',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.open_in_new, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '前往 platform.deepseek.com 注册并获取 API Key',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 保存按钮
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
              onPressed: _saving ? null : _save,
            ),

            // 清除按钮（仅在已配置时显示）
            if ((context.watch<AppRepository>().deepSeekApiKey ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除 API Key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                  ),
                  onPressed: () async {
                    _keyCtrl.clear();
                    await _save();
                  },
                ),
              ),

            const SizedBox(height: 32),

            // ── 对话记录 ──
            Text(
              '对话记录',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            const _ChatRetentionCard(),
          ],
        ),
      ),
    );
  }
}

/// 对话保存时长选择（一个月 / 半年）+ 清空对话。
class _ChatRetentionCard extends StatelessWidget {
  const _ChatRetentionCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final days = repo.chatRetentionDays;

    Widget option(String label, int value) {
      final selected = days == value;
      return InkWell(
        onTap: () => repo.setChatRetentionDays(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
              if (selected)
                Icon(Icons.check, size: 20, color: scheme.primary),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('保存一个月', 30),
          Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
          option('保存半年', 180),
          Divider(
              height: 0.5,
              thickness: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
          InkWell(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空对话'),
                  content: const Text('确认清空全部 AI 对话记录？此操作不可撤销。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空')),
                  ],
                ),
              );
              if (ok == true) {
                clearChatHistoryMemory();
                await repo.clearChatMessages();
              }
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: scheme.error),
                  const SizedBox(width: 8),
                  Text('清空对话',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: scheme.error)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
