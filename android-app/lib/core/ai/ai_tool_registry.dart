import 'chat_session.dart';

/// Tool risk is intentionally explicit: a bookkeeping assistant must not
/// silently turn a read request into a write.
enum AiToolRisk { readOnly, write, external }

enum AiToolAccessPolicy { automatic, readOnly, confirmWrites, disabled }

class AiToolDefinition {
  final String id;
  final String label;
  final AiToolRisk risk;
  final String description;

  const AiToolDefinition({
    required this.id,
    required this.label,
    required this.risk,
    required this.description,
  });
}

class AiToolRegistry {
  AiToolRegistry._();

  static const List<AiToolDefinition> builtIns = [
    AiToolDefinition(
      id: 'read_ledger',
      label: '读取账本',
      risk: AiToolRisk.readOnly,
      description: '按账本、日期、分类和金额查询本机流水',
    ),
    AiToolDefinition(
      id: 'read_statistics',
      label: '查看统计',
      risk: AiToolRisk.readOnly,
      description: '读取统计口径并生成消费分析',
    ),
    AiToolDefinition(
      id: 'parse_attachment',
      label: '识别附件',
      risk: AiToolRisk.readOnly,
      description: '读取用户主动选择的图片或账单文件',
    ),
    AiToolDefinition(
      id: 'web_search',
      label: '联网搜索',
      risk: AiToolRisk.external,
      description: '向已授权的搜索服务查询公开网页',
    ),
    AiToolDefinition(
      id: 'create_transactions',
      label: '新增账单',
      risk: AiToolRisk.write,
      description: '根据结构化提案新增收入、支出或转账',
    ),
    AiToolDefinition(
      id: 'edit_transactions',
      label: '修改账单',
      risk: AiToolRisk.write,
      description: '修改已有账单的分类、备注或金额',
    ),
    AiToolDefinition(
      id: 'delete_transactions',
      label: '删除账单',
      risk: AiToolRisk.write,
      description: '删除用户明确指定的账单',
    ),
    AiToolDefinition(
      id: 'export_bill',
      label: '导出账单',
      risk: AiToolRisk.external,
      description: '生成用户主动请求的导出文件',
    ),
  ];

  static AiToolDefinition? byId(String id) => builtIns
          .firstWhere(
            (tool) => tool.id == id,
            orElse: () => const AiToolDefinition(
              id: '',
              label: '',
              risk: AiToolRisk.external,
              description: '',
            ),
          )
          .id
          .isEmpty
      ? null
      : builtIns.firstWhere((tool) => tool.id == id);

  static AiToolAccessPolicy policyFromChatAccess(AiChatToolAccess access) =>
      switch (access) {
        AiChatToolAccess.auto => AiToolAccessPolicy.automatic,
        AiChatToolAccess.onDemand => AiToolAccessPolicy.confirmWrites,
        AiChatToolAccess.alwaysAvailable => AiToolAccessPolicy.automatic,
      };

  static bool allowed(
    String toolId, {
    required AiToolAccessPolicy policy,
    required bool recordMode,
    bool explicitlyConfirmed = false,
  }) {
    final tool = byId(toolId);
    if (tool == null || policy == AiToolAccessPolicy.disabled) return false;
    if (tool.risk == AiToolRisk.readOnly) {
      return policy != AiToolAccessPolicy.disabled;
    }
    if (tool.risk == AiToolRisk.external) {
      return policy == AiToolAccessPolicy.automatic ||
          policy == AiToolAccessPolicy.confirmWrites ||
          explicitlyConfirmed;
    }
    // The home "记一记" mode is explicitly pre-authorized for a fast, high
    // confidence single-entry commit. Chats still require confirmation.
    return recordMode || explicitlyConfirmed;
  }

  static bool needsConfirmation(
    String toolId, {
    required AiToolAccessPolicy policy,
    required bool recordMode,
    required bool highConfidence,
    required int itemCount,
  }) {
    final tool = byId(toolId);
    if (tool == null || tool.risk != AiToolRisk.write) return false;
    if (!recordMode) return true;
    if (policy == AiToolAccessPolicy.confirmWrites) return true;
    return !highConfidence || itemCount > 1;
  }
}
