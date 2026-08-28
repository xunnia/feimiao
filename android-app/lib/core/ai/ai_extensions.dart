import 'dart:convert';

class AiMemory {
  final String id;
  final String phrase;
  final String content;
  final String source;
  final String sessionId;
  final bool consent;
  final String status;
  final int createdMs;
  final int updatedMs;
  final int? lastUsedMs;

  const AiMemory({
    required this.id,
    required this.phrase,
    required this.content,
    this.source = 'user',
    this.sessionId = '',
    this.consent = false,
    this.status = 'active',
    this.createdMs = 0,
    this.updatedMs = 0,
    this.lastUsedMs,
  });

  bool get isActive => status == 'active' && consent;

  Map<String, Object?> toMap() => {
        'id': id,
        'phrase': phrase,
        'content': content,
        'source': source,
        'session_id': sessionId,
        'consent': consent ? 1 : 0,
        'status': status,
        'created_ms': createdMs,
        'updated_ms': updatedMs,
        'last_used_ms': lastUsedMs,
      };

  factory AiMemory.fromMap(Map<String, Object?> map) => AiMemory(
        id: map['id']?.toString() ?? '',
        phrase: map['phrase']?.toString() ?? '',
        content: map['content']?.toString() ?? '',
        source: map['source']?.toString() ?? 'user',
        sessionId: map['session_id']?.toString() ?? '',
        consent: (map['consent'] as num?)?.toInt() == 1,
        status: map['status']?.toString() ?? 'active',
        createdMs: (map['created_ms'] as num?)?.toInt() ?? 0,
        updatedMs: (map['updated_ms'] as num?)?.toInt() ?? 0,
        lastUsedMs: (map['last_used_ms'] as num?)?.toInt(),
      );
}

class AiReportSchedule {
  final String id;
  final String sessionId;
  final String title;
  final String reportType;
  final String periodKind;
  final int dayValue;
  final bool enabled;
  final int nextRunMs;
  final String providerId;
  final String model;
  final String effort;
  final int createdMs;
  final int updatedMs;

  const AiReportSchedule({
    required this.id,
    this.sessionId = 'record',
    required this.title,
    this.reportType = 'monthly',
    this.periodKind = 'monthly',
    this.dayValue = 1,
    this.enabled = true,
    this.nextRunMs = 0,
    this.providerId = '',
    this.model = '',
    this.effort = 'low',
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  DateTime get nextRun => DateTime.fromMillisecondsSinceEpoch(nextRunMs);

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'title': title,
        'report_type': reportType,
        'period_kind': periodKind,
        'day_value': dayValue,
        'enabled': enabled ? 1 : 0,
        'next_run_ms': nextRunMs,
        'provider_id': providerId,
        'model': model,
        'effort': effort,
        'created_ms': createdMs,
        'updated_ms': updatedMs,
      };

  factory AiReportSchedule.fromMap(Map<String, Object?> map) =>
      AiReportSchedule(
        id: map['id']?.toString() ?? '',
        sessionId: map['session_id']?.toString() ?? 'record',
        title: map['title']?.toString() ?? '',
        reportType: map['report_type']?.toString() ?? 'monthly',
        periodKind: map['period_kind']?.toString() ?? 'monthly',
        dayValue: (map['day_value'] as num?)?.toInt() ?? 1,
        enabled: (map['enabled'] as num?)?.toInt() != 0,
        nextRunMs: (map['next_run_ms'] as num?)?.toInt() ?? 0,
        providerId: map['provider_id']?.toString() ?? '',
        model: map['model']?.toString() ?? '',
        effort: map['effort']?.toString() ?? 'low',
        createdMs: (map['created_ms'] as num?)?.toInt() ?? 0,
        updatedMs: (map['updated_ms'] as num?)?.toInt() ?? 0,
      );

  AiReportSchedule copyWith({
    String? title,
    String? reportType,
    String? periodKind,
    int? dayValue,
    bool? enabled,
    int? nextRunMs,
    String? providerId,
    String? model,
    String? effort,
    int? updatedMs,
  }) =>
      AiReportSchedule(
        id: id,
        sessionId: sessionId,
        title: title ?? this.title,
        reportType: reportType ?? this.reportType,
        periodKind: periodKind ?? this.periodKind,
        dayValue: dayValue ?? this.dayValue,
        enabled: enabled ?? this.enabled,
        nextRunMs: nextRunMs ?? this.nextRunMs,
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        effort: effort ?? this.effort,
        createdMs: createdMs,
        updatedMs: updatedMs ?? this.updatedMs,
      );
}

class AiSkillDefinition {
  final String id;
  final String label;
  final String description;
  final String risk;
  final List<String> allowedToolIds;

  const AiSkillDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.risk = 'read_only',
    this.allowedToolIds = const [],
  });
}

class AiSkillRegistry {
  AiSkillRegistry._();

  static const builtIns = <AiSkillDefinition>[
    AiSkillDefinition(
      id: 'ledger_assistant',
      label: '记账助手',
      description: '识别、预览并写入账单；写入前遵守本地确认策略。',
      risk: 'write',
      allowedToolIds: ['parse_attachment', 'create_transactions'],
    ),
    AiSkillDefinition(
      id: 'ledger_analyst',
      label: '账本分析',
      description: '读取账本和统计数据，生成可解释的分析。',
      allowedToolIds: ['read_ledger', 'read_statistics'],
    ),
    AiSkillDefinition(
      id: 'bill_import',
      label: '账单导入',
      description: '解析文件并在复核后批量归类。',
      risk: 'write',
      allowedToolIds: ['parse_attachment', 'create_transactions'],
    ),
    AiSkillDefinition(
      id: 'report_writer',
      label: '报告生成',
      description: '基于当前账本生成可保存的周期报告。',
      allowedToolIds: ['read_ledger', 'read_statistics'],
    ),
  ];
}

class AiConnectorDefinition {
  final String id;
  final String label;
  final String description;
  final List<String> hostAllowlist;
  final String risk;

  const AiConnectorDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.hostAllowlist,
    this.risk = 'external',
  });

  bool accepts(Uri uri) {
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    if (id == 'local_companion') {
      // A local companion is deliberately the only cleartext exception. The
      // host remains loopback-only; remote HTTP endpoints never pass this
      // gate and are rejected again by LocalModelCompanionClient.
      return uri.scheme == 'http' && hostAllowlist.contains(host);
    }
    return uri.scheme == 'https' && hostAllowlist.contains(host);
  }
}

class AiConnectorRegistry {
  AiConnectorRegistry._();

  static const builtIns = <AiConnectorDefinition>[
    AiConnectorDefinition(
      id: 'web_search',
      label: '联网搜索',
      description: '仅在用户打开联网搜索时访问搜索服务。',
      hostAllowlist: [
        'api.openai.com',
        'chatgpt.com',
        'api.anthropic.com',
        'api.duckduckgo.com',
      ],
    ),
    AiConnectorDefinition(
      id: 'local_companion',
      label: '本地模型伴侣',
      description: '只允许连接本机回环地址的可选 companion service。',
      hostAllowlist: ['127.0.0.1', 'localhost', '::1'],
    ),
  ];

  static AiConnectorDefinition? byId(String id) =>
      builtIns.where((connector) => connector.id == id.trim()).firstOrNull;
}

String encodeAiSkillState(Map<String, bool> values) => jsonEncode(values);

Map<String, bool> decodeAiSkillState(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value == true,
      };
    }
  } catch (_) {}
  return const {};
}
