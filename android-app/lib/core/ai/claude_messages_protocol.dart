import 'dart:math' as math;

import 'ai_provider_config.dart';

/// Preserve the existing use-case contracts while sharing the wire encoding.
/// The report path intentionally keeps only its last non-empty system message;
/// query and entry combine system messages, and only streamChat sets stream.
enum ClaudeRequestKind { report, query, streamChat, entry }

abstract final class ClaudeMessagesProtocol {
  static Map<String, dynamic> bodyFromChat(
    Map<String, dynamic> chatBody,
    AiProviderConfig config, {
    required ClaudeRequestKind kind,
  }) {
    final report = kind == ClaudeRequestKind.report;
    final stream = kind == ClaudeRequestKind.streamChat;
    final messages = chatBody['messages'] as List<dynamic>?;
    if (messages == null && !report) return chatBody;

    final system = <String>[];
    final input = <Map<String, dynamic>>[];
    for (final message in messages ?? const []) {
      if (message is! Map) continue;
      if (!report && message is! Map<String, dynamic>) continue;
      final role = report
          ? (message['role'] as String?)?.trim() ?? 'user'
          : message['role'] as String?;
      final content = message['content'];
      if (report) {
        final text = _stringContent(content).trim();
        if (text.isEmpty) continue;
        if (role == 'system') {
          system
            ..clear()
            ..add(text);
        } else {
          input.add({'role': role, 'content': text});
        }
      } else if (role == 'system') {
        system.add(stream
            ? '$content'
            : kind == ClaudeRequestKind.entry
                ? _entrySystemContent(content)
                : _stringContent(content));
      } else {
        final typed = Map<String, dynamic>.from(message);
        input.add(kind == ClaudeRequestKind.entry || stream
            ? messageFromChat(kind == ClaudeRequestKind.entry
                ? {...typed, 'content': content ?? ''}
                : typed)
            : typed);
      }
    }

    final budget = config.reasoningEffort.claudeBudgetTokens;
    final requested = (chatBody['max_tokens'] as int?) ?? 4096;
    return {
      'model': chatBody['model'],
      'messages': input,
      'max_tokens':
          budget == null ? requested : math.max(requested, budget + 4096),
      if (system.isNotEmpty) 'system': system.join('\n\n'),
      if (stream) 'stream': true,
      if (budget != null) ...{
        'thinking': {'type': 'enabled', 'budget_tokens': budget},
        'temperature': 1,
      },
    };
  }

  static Map<String, dynamic> messageFromChat(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is! List) return message;
    return {
      ...message,
      'content': [
        for (final part in content)
          if (part is Map && part['type'] == 'text')
            {'type': 'text', 'text': part['text']?.toString() ?? ''}
          else if (part is Map && part['type'] == 'image_url')
            {
              'type': 'image',
              'source': _source(
                  (part['image_url'] is Map ? part['image_url']['url'] : null)
                      ?.toString()),
            }
          else if (part is Map && part['type'] == 'file')
            {
              'type': 'document',
              'source': _source(
                  (part['file'] is Map ? part['file']['file_data'] : null)
                      ?.toString()),
              'title': (part['file'] is Map ? part['file']['filename'] : null)
                  ?.toString(),
            },
      ],
    };
  }

  static Map<String, String> _source(String? uri) {
    final value = uri ?? '';
    final match = RegExp(r'^data:([^;]+);base64,').firstMatch(value);
    final comma = value.indexOf(',');
    return {
      'type': 'base64',
      'media_type': match?.group(1) ?? 'image/jpeg',
      'data': comma < 0 ? value : value.substring(comma + 1),
    };
  }

  static String _stringContent(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) => part is String
              ? part
              : part is Map
                  ? part['text']?.toString() ?? ''
                  : '')
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
    }
    return content?.toString() ?? '';
  }

  static String _entrySystemContent(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .where((part) => part['type'] == 'text')
          .map((part) => part['text'] as String? ?? '')
          .join(' ');
    }
    return '';
  }
}
