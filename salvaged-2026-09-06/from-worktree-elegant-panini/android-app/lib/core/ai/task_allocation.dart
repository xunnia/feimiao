import 'ai_model_info.dart';

/// 任务分配规则封装：任务类型、自动/手动分配、自定义模型、推理档位。
///
/// 配合 AI 设置界面，让用户为三类任务（快捷录入、助手对话、生成报告）
/// 分别指定使用哪个模型、以及推理强度（Faster / Balanced / Smarter）。
class TaskAllocation {
  /// 任务类型：快捷录入 / 助手对话 / 生成报告
  final String taskType;

  /// 是否自动分配（true = 由系统选模型；false = 用户指定）
  final bool isAuto;

  /// 自定义模型 ID（当 [isAuto] = false 时有效）
  final String? customModelId;

  /// 推理档位：0.0 ~ 1.0（0=最快，1=最强推理）
  final double customEffort;

  const TaskAllocation({
    required this.taskType,
    required this.isAuto,
    this.customModelId,
    required this.customEffort,
  });

  /// 任务类型常量：快捷录入（语音/图片转账目）
  static const String QUICK_ENTRY = 'quick_entry';

  /// 任务类型常量：助手对话（喵助手查账、消费分析）
  static const String ASSISTANT = 'assistant';

  /// 任务类型常量：生成报告（月报、年度总结）
  static const String REPORT = 'report';

  /// 获取自定义模型信息：从 [customModelId] 查找 [AiModelInfo]。
  /// 若 [isAuto] = true 或 [customModelId] 为空，返回 null。
  AiModelInfo? get customModel {
    if (isAuto || customModelId == null || customModelId!.isEmpty) {
      return null;
    }
    return AiModelInfo.fromId(customModelId!);
  }

  /// 推理档位标签：将 [customEffort] 映射为可读文案。
  /// - 0.00 ~ 0.33 → Faster（快速响应）
  /// - 0.33 ~ 0.66 → Balanced（平衡）
  /// - 0.66 ~ 1.00 → Smarter（深度推理）
  String get effortLabel {
    if (customEffort < 0.33) {
      return 'Faster';
    } else if (customEffort < 0.66) {
      return 'Balanced';
    } else {
      return 'Smarter';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAllocation &&
          runtimeType == other.runtimeType &&
          taskType == other.taskType &&
          isAuto == other.isAuto &&
          customModelId == other.customModelId &&
          customEffort == other.customEffort;

  @override
  int get hashCode =>
      taskType.hashCode ^
      isAuto.hashCode ^
      customModelId.hashCode ^
      customEffort.hashCode;
}
