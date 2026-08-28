import 'ai_provider_config.dart';

/// Controls whether a normal Chats conversation may use 肥喵's account,
/// record and web-search tools. It is a session-level preference, matching the
/// Claude-style "Tool access" row rather than a provider/account setting.
enum AiChatToolAccess { auto, onDemand, alwaysAvailable }

extension AiChatToolAccessX on AiChatToolAccess {
  String get storageKey => switch (this) {
        AiChatToolAccess.auto => 'auto',
        AiChatToolAccess.onDemand => 'on_demand',
        AiChatToolAccess.alwaysAvailable => 'always_available',
      };

  String get label => switch (this) {
        AiChatToolAccess.auto => '自动',
        AiChatToolAccess.onDemand => '按需加载',
        AiChatToolAccess.alwaysAvailable => '始终可用',
      };

  static AiChatToolAccess fromStorage(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'on_demand' || 'off' => AiChatToolAccess.onDemand,
        'always_available' || 'always' => AiChatToolAccess.alwaysAvailable,
        _ => AiChatToolAccess.auto,
      };
}

/// A persisted conversation shown in the Chats list.
///
/// The record session is a product invariant: there is exactly one session
/// with [isRecord] set to true and it cannot be deleted or renamed.
class ChatSession {
  static const recordId = 'record';
  static const recordTitle = '记一记';

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool starred;
  final bool isRecord;
  final String? providerId;
  final String? model;
  final AiReasoningEffort effort;

  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.starred = false,
    this.isRecord = false,
    this.providerId,
    this.model,
    this.effort = AiReasoningEffort.low,
  });

  factory ChatSession.fromMap(Map<String, Object?> row) {
    final id = (row['session_id'] as String? ?? '').trim();
    final record = (row['is_record'] as num?)?.toInt() == 1 || id == recordId;
    final createdMs = (row['created_ms'] as num?)?.toInt() ?? 0;
    final updatedMs = (row['updated_ms'] as num?)?.toInt() ?? createdMs;
    var effort = AiReasoningEffortX.fromStorage(
      row['effort'] as String?,
      fallback: AiReasoningEffort.low,
    );
    // 旧版曾允许关闭/Minimal；Chats 的产品口径从 Low 起步，升级后不再
    // 让历史值在任一会话里重新显示为 Off 或 Minimal。
    if (effort == AiReasoningEffort.none ||
        effort == AiReasoningEffort.minimal) {
      effort = AiReasoningEffort.low;
    }
    return ChatSession(
      id: id.isEmpty ? recordId : id,
      title: record
          ? recordTitle
          : ((row['title'] as String? ?? '').trim().isEmpty
              ? '新对话'
              : (row['title'] as String).trim()),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      starred: (row['starred'] as num?)?.toInt() == 1,
      isRecord: record,
      providerId: _nullableString(row['provider_id']),
      model: _nullableString(row['model']),
      effort: effort,
    );
  }

  Map<String, Object?> toMap() => {
        'session_id': id,
        'title': isRecord ? recordTitle : title,
        'created_ms': createdAt.millisecondsSinceEpoch,
        'updated_ms': updatedAt.millisecondsSinceEpoch,
        'starred': starred ? 1 : 0,
        'is_record': isRecord ? 1 : 0,
        'provider_id': providerId ?? '',
        'model': model ?? '',
        'effort': effort.storageKey,
      };

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    bool? starred,
    String? providerId,
    String? model,
    AiReasoningEffort? effort,
  }) {
    if (isRecord) return this;
    return ChatSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      starred: starred ?? this.starred,
      isRecord: false,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      effort: effort ?? this.effort,
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
