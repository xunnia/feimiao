import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_model_info.dart';
import '../../core/ai/task_allocation.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_back_button.dart';
import 'effort_slider_sheet.dart';
import 'model_picker_sheet.dart';

/// 用途分配页面：为三种任务类型（普通记账/喵助手/报告生成）
/// 配置自动或自定义模型选择。
class TaskAllocationPage extends StatefulWidget {
  const TaskAllocationPage({super.key});

  @override
  State<TaskAllocationPage> createState() => _TaskAllocationPageState();
}

class _TaskAllocationPageState extends State<TaskAllocationPage> {
  late Map<String, TaskAllocation> _allocations;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllocations();
  }

  Future<void> _loadAllocations() async {
    final repo = context.read<AppRepository>();
    final data = await repo.getTaskAllocationsMap();

    setState(() {
      _allocations = data.map((key, value) {
        final map = value as Map<String, dynamic>;
        return MapEntry(
          key,
          TaskAllocation(
            taskType: map['taskType'] as String,
            isAuto: map['isAuto'] as bool,
            customModelId: map['customModelId'] as String?,
            customEffort: map['customEffort'] as double?,
          ),
        );
      });
      _isLoading = false;
    });
  }

  Future<void> _updateAllocation(String taskType, TaskAllocation updated) async {
    setState(() => _allocations[taskType] = updated);
  }

  Future<void> _saveAllocations() async {
    final repo = context.read<AppRepository>();

    // 转换为 Repository 需要的格式
    final dataMap = _allocations.map((key, allocation) {
      return MapEntry(key, {
        'taskType': allocation.taskType,
        'isAuto': allocation.isAuto,
        'customModelId': allocation.customModelId,
        'customEffort': allocation.customEffort,
      });
    });

    await repo.saveTaskAllocationsMap(dataMap);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('保存成功'),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('用途分配'),
          leading: const AppBackButton(),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('用途分配'),
        leading: const AppBackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明文案
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '自动模式会按任务选择更合适的 AI：普通记账优先速度，'
              '报告生成优先深度。没有配置对应密钥时，会自动回退到可用服务。',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            '分配规则',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // 三个任务类型卡片
          _buildTaskSection(
            title: '普通记账',
            description: '一句话记账、截图识别、导入分类,优先最快响应',
            allocation: _allocations['quick_entry']!,
            onUpdate: (updated) => _updateAllocation('quick_entry', updated),
          ),

          const SizedBox(height: 16),
          _buildTaskSection(
            title: '喵助手',
            description: '日常查账、消费问答,优先稳定和响应速度',
            allocation: _allocations['assistant']!,
            onUpdate: (updated) => _updateAllocation('assistant', updated),
          ),

          const SizedBox(height: 16),
          _buildTaskSection(
            title: '报告生成',
            description: '周报、月报、年报,优先结构、洞察和长文质量',
            allocation: _allocations['report']!,
            onUpdate: (updated) => _updateAllocation('report', updated),
          ),

          const SizedBox(height: 100),
        ],
      ),

      // 底部保存按钮
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _saveAllocations,
              child: const Text('保存用途分配'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskSection({
    required String title,
    required String description,
    required TaskAllocation allocation,
    required ValueChanged<TaskAllocation> onUpdate,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: AppType.caption(scheme),
          ),
          const SizedBox(height: 16),

          // 自动 / 自定义 切换
          Row(
            children: [
              _buildModeChip(
                '自动',
                allocation.isAuto,
                () => onUpdate(TaskAllocation(
                  taskType: allocation.taskType,
                  isAuto: true,
                )),
              ),
              const SizedBox(width: 12),
              _buildModeChip(
                '自定义',
                !allocation.isAuto,
                () => onUpdate(TaskAllocation(
                  taskType: allocation.taskType,
                  isAuto: false,
                  customModelId: allocation.customModelId ?? 'deepseek-chat',
                  customEffort: allocation.customEffort,
                )),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 当前配置卡片
          if (allocation.isAuto)
            _buildAutoSelectionCard()
          else
            _buildCustomSelectionCard(allocation, onUpdate),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                margin: const EdgeInsets.only(right: 6),
              ),
            Text(
              label,
              style: TextStyle(
                color: selected ? scheme.primary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSelectionCard() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DeepSeek Chat',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '自动选择 · 响应快',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSelectionCard(
    TaskAllocation allocation,
    ValueChanged<TaskAllocation> onUpdate,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final model = allocation.customModel;

    return GestureDetector(
      onTap: () => _showModelAndEffortPicker(allocation, onUpdate),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(model?.emoji ?? '🤖', style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    model?.displayName ?? '未选择',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),

            if (model?.supportsReasoning == true && allocation.customEffort != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '思考强度: ',
                    style: AppType.caption(scheme),
                  ),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: allocation.customEffort!,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    allocation.effortLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),
            Text(
              '点击调整 →',
              style: AppType.caption(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModelAndEffortPicker(
    TaskAllocation allocation,
    ValueChanged<TaskAllocation> onUpdate,
  ) async {
    // 先选模型
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelPickerSheet(
        currentModelId: allocation.customModelId,
        onModelSelected: (modelId) async {
          final model = AiModelInfo.builtInModels.firstWhere((m) => m.id == modelId);

          // 如果支持推理，继续选强度
          if (model.supportsReasoning) {
            if (!mounted) return;
            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (context) => EffortSliderSheet(
                currentEffort: allocation.customEffort ?? 0.5,
                onEffortChanged: (effort) {
                  onUpdate(TaskAllocation(
                    taskType: allocation.taskType,
                    isAuto: false,
                    customModelId: modelId,
                    customEffort: effort,
                  ));
                },
              ),
            );
          } else {
            // 不支持推理，直接保存
            onUpdate(TaskAllocation(
              taskType: allocation.taskType,
              isAuto: false,
              customModelId: modelId,
              customEffort: null,
            ));
          }
        },
      ),
    );
  }
}
