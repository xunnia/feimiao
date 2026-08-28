import 'dart:convert';

/// A persisted AI operation.  The UI may disappear, but the run remains
/// inspectable and replayable from SQLite.
enum AiRunMode {
  record,
  chat,
  query,
  report,
  import,
  scheduledReport,
  localModel,
}

extension AiRunModeX on AiRunMode {
  String get storageKey => name;

  String get label => switch (this) {
        AiRunMode.record => 'AI 记账',
        AiRunMode.chat => '喵助手聊天',
        AiRunMode.query => '账本查询',
        AiRunMode.report => '报告生成',
        AiRunMode.import => '账单导入',
        AiRunMode.scheduledReport => '定时报表',
        AiRunMode.localModel => '本地模型',
      };

  static AiRunMode fromStorage(Object? value) => AiRunMode.values.firstWhere(
        (item) => item.storageKey == value?.toString(),
        orElse: () => AiRunMode.chat,
      );
}

enum AiRunStatus {
  queued,
  preparing,
  toolCall,
  awaitingConfirmation,
  thinking,
  streaming,
  background,
  completed,
  rolledBack,
  failed,
  cancelled,
}

extension AiRunStatusX on AiRunStatus {
  String get storageKey => name;

  String get label => switch (this) {
        AiRunStatus.queued => '排队中',
        AiRunStatus.preparing => '准备中',
        AiRunStatus.toolCall => '调用工具',
        AiRunStatus.awaitingConfirmation => '等待确认',
        AiRunStatus.thinking => '思考中',
        AiRunStatus.streaming => '生成中',
        AiRunStatus.background => '后台处理中',
        AiRunStatus.completed => '已完成',
        AiRunStatus.rolledBack => '已撤销',
        AiRunStatus.failed => '失败',
        AiRunStatus.cancelled => '已取消',
      };

  static AiRunStatus fromStorage(Object? value) =>
      AiRunStatus.values.firstWhere(
        (item) => item.storageKey == value?.toString(),
        orElse: () => AiRunStatus.queued,
      );
}

enum AiRunEventType {
  runStarted,
  stageChanged,
  contextReady,
  attachmentReady,
  toolRequested,
  toolResult,
  confirmationRequired,
  delta,
  reasoning,
  source,
  proposalReady,
  retry,
  committed,
  rolledBack,
  completed,
  failed,
  cancelled,
}

extension AiRunEventTypeX on AiRunEventType {
  String get storageKey => name;

  static AiRunEventType fromStorage(Object? value) =>
      AiRunEventType.values.firstWhere(
        (item) => item.storageKey == value?.toString(),
        orElse: () => AiRunEventType.stageChanged,
      );
}

/// Configuration captured at the beginning of a run. Secrets are deliberately
/// absent; the actual credential stays in SecureKeyStore/provider config.
class AiRunConfigSnapshot {
  final String providerId;
  final String providerLabel;
  final String model;
  final String effort;
  final String endpointType;

  const AiRunConfigSnapshot({
    required this.providerId,
    required this.providerLabel,
    required this.model,
    required this.effort,
    required this.endpointType,
  });

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        'providerLabel': providerLabel,
        'model': model,
        'effort': effort,
        'endpointType': endpointType,
      };

  factory AiRunConfigSnapshot.fromJson(Map<String, Object?> json) =>
      AiRunConfigSnapshot(
        providerId: json['providerId']?.toString() ?? '',
        providerLabel: json['providerLabel']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        effort: json['effort']?.toString() ?? 'none',
        endpointType: json['endpointType']?.toString() ?? 'auto',
      );
}

class AiRun {
  final String id;
  final String idempotencyKey;
  final String sessionId;
  final AiRunMode mode;
  final AiRunConfigSnapshot config;
  final AiRunStatus status;
  final String inputDigest;
  final String contextDigest;
  final String proposalJson;
  final String resultJson;
  final String errorCode;
  final String errorMessage;
  final int retryCount;
  final bool requiresConfirmation;
  final int createdMs;
  final int updatedMs;

  const AiRun({
    required this.id,
    required this.idempotencyKey,
    required this.sessionId,
    required this.mode,
    required this.config,
    required this.status,
    required this.inputDigest,
    required this.contextDigest,
    required this.proposalJson,
    required this.resultJson,
    required this.errorCode,
    required this.errorMessage,
    required this.retryCount,
    required this.requiresConfirmation,
    required this.createdMs,
    required this.updatedMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedMs);
  bool get isTerminal => switch (status) {
        AiRunStatus.completed ||
        AiRunStatus.rolledBack ||
        AiRunStatus.failed ||
        AiRunStatus.cancelled =>
          true,
        _ => false,
      };

  Map<String, Object?> toMap() => {
        'id': id,
        'idempotency_key': idempotencyKey,
        'session_id': sessionId,
        'mode': mode.storageKey,
        'provider_id': config.providerId,
        'provider_label': config.providerLabel,
        'model': config.model,
        'effort': config.effort,
        'endpoint_type': config.endpointType,
        'status': status.storageKey,
        'input_digest': inputDigest,
        'context_digest': contextDigest,
        'proposal_json': proposalJson,
        'result_json': resultJson,
        'error_code': errorCode,
        'error_message': errorMessage,
        'retry_count': retryCount,
        'requires_confirmation': requiresConfirmation ? 1 : 0,
        'created_ms': createdMs,
        'updated_ms': updatedMs,
      };

  factory AiRun.fromMap(Map<String, Object?> map) => AiRun(
        id: map['id']?.toString() ?? '',
        idempotencyKey: map['idempotency_key']?.toString() ?? '',
        sessionId: map['session_id']?.toString() ?? '',
        mode: AiRunModeX.fromStorage(map['mode']),
        config: AiRunConfigSnapshot(
          providerId: map['provider_id']?.toString() ?? '',
          providerLabel: map['provider_label']?.toString() ?? '',
          model: map['model']?.toString() ?? '',
          effort: map['effort']?.toString() ?? 'none',
          endpointType: map['endpoint_type']?.toString() ?? 'auto',
        ),
        status: AiRunStatusX.fromStorage(map['status']),
        inputDigest: map['input_digest']?.toString() ?? '',
        contextDigest: map['context_digest']?.toString() ?? '',
        proposalJson: map['proposal_json']?.toString() ?? '',
        resultJson: map['result_json']?.toString() ?? '',
        errorCode: map['error_code']?.toString() ?? '',
        errorMessage: map['error_message']?.toString() ?? '',
        retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
        requiresConfirmation:
            (map['requires_confirmation'] as num?)?.toInt() == 1,
        createdMs: (map['created_ms'] as num?)?.toInt() ?? 0,
        updatedMs: (map['updated_ms'] as num?)?.toInt() ?? 0,
      );

  AiRun copyWith({
    AiRunStatus? status,
    String? proposalJson,
    String? resultJson,
    String? errorCode,
    String? errorMessage,
    int? retryCount,
    bool? requiresConfirmation,
    int? updatedMs,
  }) =>
      AiRun(
        id: id,
        idempotencyKey: idempotencyKey,
        sessionId: sessionId,
        mode: mode,
        config: config,
        status: status ?? this.status,
        inputDigest: inputDigest,
        contextDigest: contextDigest,
        proposalJson: proposalJson ?? this.proposalJson,
        resultJson: resultJson ?? this.resultJson,
        errorCode: errorCode ?? this.errorCode,
        errorMessage: errorMessage ?? this.errorMessage,
        retryCount: retryCount ?? this.retryCount,
        requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
        createdMs: createdMs,
        updatedMs: updatedMs ?? this.updatedMs,
      );
}

class AiRunEvent {
  final int? id;
  final String runId;
  final int sequence;
  final AiRunEventType type;
  final Map<String, Object?> payload;
  final int createdMs;

  const AiRunEvent({
    this.id,
    required this.runId,
    required this.sequence,
    required this.type,
    this.payload = const {},
    required this.createdMs,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'run_id': runId,
        'sequence': sequence,
        'type': type.storageKey,
        'payload_json': jsonEncode(payload),
        'created_ms': createdMs,
      };

  factory AiRunEvent.fromMap(Map<String, Object?> map) {
    Map<String, Object?> payload = const {};
    try {
      final decoded = jsonDecode(map['payload_json']?.toString() ?? '');
      if (decoded is Map) {
        payload = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return AiRunEvent(
      id: (map['id'] as num?)?.toInt(),
      runId: map['run_id']?.toString() ?? '',
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      type: AiRunEventTypeX.fromStorage(map['type']),
      payload: payload,
      createdMs: (map['created_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class AiLedgerProposalItem {
  final String amount;
  final String kind;
  final String categoryKey;
  final String date;
  final String note;
  final double confidence;
  final bool selected;
  final bool committed;

  const AiLedgerProposalItem({
    required this.amount,
    required this.kind,
    required this.categoryKey,
    required this.date,
    required this.note,
    required this.confidence,
    this.selected = true,
    this.committed = false,
  });

  Map<String, Object?> toJson() => {
        'amount': amount,
        'kind': kind,
        'categoryKey': categoryKey,
        'date': date,
        'note': note,
        'confidence': confidence,
        'selected': selected,
        'committed': committed,
      };

  factory AiLedgerProposalItem.fromJson(Map<String, Object?> json) =>
      AiLedgerProposalItem(
        amount: json['amount']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'expense',
        categoryKey: json['categoryKey']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        selected: json['selected'] != false,
        committed: json['committed'] == true,
      );

  AiLedgerProposalItem copyWith({
    String? amount,
    String? kind,
    String? categoryKey,
    String? date,
    String? note,
    double? confidence,
    bool? selected,
    bool? committed,
  }) =>
      AiLedgerProposalItem(
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        categoryKey: categoryKey ?? this.categoryKey,
        date: date ?? this.date,
        note: note ?? this.note,
        confidence: confidence ?? this.confidence,
        selected: selected ?? this.selected,
        committed: committed ?? this.committed,
      );
}

class AiLedgerProposal {
  final String runId;
  final List<AiLedgerProposalItem> items;
  final bool requiresConfirmation;
  final String explanation;
  final int createdMs;

  const AiLedgerProposal({
    required this.runId,
    required this.items,
    required this.requiresConfirmation,
    this.explanation = '',
    required this.createdMs,
  });

  List<AiLedgerProposalItem> get selectedItems =>
      items.where((item) => item.selected).toList(growable: false);

  Map<String, Object?> toJson() => {
        'runId': runId,
        'items': items.map((item) => item.toJson()).toList(),
        'requiresConfirmation': requiresConfirmation,
        'explanation': explanation,
        'createdMs': createdMs,
      };

  String encode() => jsonEncode(toJson());

  factory AiLedgerProposal.fromJson(Map<String, Object?> json) =>
      AiLedgerProposal(
        runId: json['runId']?.toString() ?? '',
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => AiLedgerProposalItem.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList(growable: false),
        requiresConfirmation: json['requiresConfirmation'] == true,
        explanation: json['explanation']?.toString() ?? '',
        createdMs: (json['createdMs'] as num?)?.toInt() ?? 0,
      );

  static AiLedgerProposal? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AiLedgerProposal.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }
}
