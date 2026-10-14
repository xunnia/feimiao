import 'dart:async';

/// Runtime authority, never persisted as permission to mutate a restored DB.
class ChatOperationLease {
  ChatOperationLease({
    required this.owner,
    required this.sessionId,
    required this.sessionEpoch,
    required this.databaseGeneration,
    required this.bookId,
    required this.bookUuid,
  });

  static final Object _zoneKey = Object();
  static ChatOperationLease? get current =>
      Zone.current[_zoneKey] as ChatOperationLease?;

  final Object owner;
  final String sessionId;
  final int sessionEpoch;
  final int databaseGeneration;
  final int? bookId;
  final String bookUuid;
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});
}

class ChatOperationInvalidated implements Exception {
  const ChatOperationInvalidated();
  @override
  String toString() => '会话或账本已改变，这次操作未写入';
}
