import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('API Key 已保存'),
              ],
            ),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          ),
        );
      }
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
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant),
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
                              ?.copyWith(fontWeight: FontWeight.w600),
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
                    fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}
