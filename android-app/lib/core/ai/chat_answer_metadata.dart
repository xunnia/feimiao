import 'dart:convert';

import 'web_search.dart';

/// Versioned payload in the existing attachments_json column; old source
/// arrays remain readable without a database migration.
class ChatAnswerMetadata {
  const ChatAnswerMetadata({
    this.sources = const [],
    this.thinking,
    this.interrupted = false,
  });

  final List<AiWebSource> sources;
  final Map<String, dynamic>? thinking;
  final bool interrupted;

  String encode() => jsonEncode({
        'version': 1,
        'sources': jsonDecode(AiWebSearchContext.encodeSources(sources)),
        if (thinking != null) 'thinking': thinking,
        'interrupted': interrupted,
      });

  static ChatAnswerMetadata decode(Object? raw) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '');
      if (decoded is! Map) {
        return ChatAnswerMetadata(
            sources: AiWebSearchContext.decodeSources(raw));
      }
      return ChatAnswerMetadata(
        sources:
            AiWebSearchContext.decodeSources(jsonEncode(decoded['sources'])),
        thinking: decoded['thinking'] is Map
            ? Map<String, dynamic>.from(decoded['thinking'] as Map)
            : null,
        interrupted: decoded['interrupted'] == true,
      );
    } catch (_) {
      return const ChatAnswerMetadata();
    }
  }
}
