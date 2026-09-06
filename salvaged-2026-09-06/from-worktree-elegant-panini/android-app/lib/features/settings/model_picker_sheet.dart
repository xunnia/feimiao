import 'package:flutter/material.dart';

import '../../core/ai/ai_model_info.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';

/// 模型选择器底部弹层。
///
/// 显示内置模型列表（[AiModelInfo.builtInModels]），
/// 每项显示 emoji + 名称，当前选中项高亮（主色边框 + 背景色 + ✓ 图标）。
class ModelPickerSheet extends StatefulWidget {
  final String? currentModelId;
  final ValueChanged<String> onModelSelected;

  const ModelPickerSheet({
    super.key,
    required this.currentModelId,
    required this.onModelSelected,
  });

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  late String? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _selectedModelId = widget.currentModelId;
  }

  void _handleConfirm() {
    if (_selectedModelId != null) {
      widget.onModelSelected(_selectedModelId!);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '选择模型',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: AiModelInfo.builtInModels.length,
                itemBuilder: (context, index) {
                  final model = AiModelInfo.builtInModels[index];
                  final isSelected = model.id == _selectedModelId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ModelItem(
                      model: model,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedModelId = model.id;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _handleConfirm,
                  child: const Text('确定'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelItem extends StatelessWidget {
  final AiModelInfo model;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModelItem({
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          color: isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : AppColors.card(scheme),
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(34),
            side: isSelected
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Text(
              model.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.displayName,
                    style: AppType.rowTitle(scheme),
                  ),
                  if (model.supportsReasoning) ...[
                    const SizedBox(height: 2),
                    Text(
                      '支持推理',
                      style: AppType.caption(scheme),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: scheme.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
