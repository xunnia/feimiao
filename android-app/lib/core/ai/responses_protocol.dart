import 'dart:convert';

import 'ai_provider_config.dart';

/// The request shape is deliberately a use-case policy, not a transport choice.
/// Reports keep their text input; chat supports attachments; entry parsing keeps
/// its schema and requires a complete stream before any JSON can be accepted.
enum ResponsesRequestKind { report, chat, entry }

enum ResponsesFailureKind { failed, incomplete, interrupted }

class ResponsesProtocolException implements Exception {
  final ResponsesFailureKind kind;
  final String message;

  const ResponsesProtocolException(this.kind, this.message);

  @override
  String toString() => message;
}

/// Shared wire protocol only. Credentials, routing, timeouts, retries, UI and
/// transaction commits remain owned by their existing callers.
abstract final class ResponsesProtocol {
  static Map<String, dynamic> bodyFromChat(
    Map<String, dynamic> chatBody,
    AiProviderConfig config, {
    required ResponsesRequestKind kind,
  }) {
    final entry = kind == ResponsesRequestKind.entry;
    final codex = config.isOpenAiCodexOAuth;
    final richContent = kind != ResponsesRequestKind.report;
    final instructions = <String>[];
    final textInput = <String>[];
    final messageInput = <Map<String, dynamic>>[];
    var hasAttachment = false;
    final messages = chatBody['messages'];
    if (messages is List) {
      for (final item in messages) {
        if (item is! Map) continue;
        final role = (item['role'] as String?)?.trim().toLowerCase() ?? 'user';
        final raw = item['content'];
        final text = stringContent(raw).trim();
        if (text.isEmpty && !(richContent && raw is List)) continue;
        if (role == 'system' || role == 'developer') {
          instructions.add(text);
          continue;
        }
        final attached = raw is List &&
            raw.any((part) =>
                part is Map &&
                (part['type'] == 'image_url' || part['type'] == 'file'));
        hasAttachment |= richContent && attached;
        textInput.add(role == 'assistant' ? 'assistant: $text' : text);
        messageInput.add({
          'type': 'message',
          'role': role == 'assistant' ? 'assistant' : 'user',
          'content': richContent && (entry || attached)
              ? contentParts(raw, assistant: role == 'assistant')
              : [
                  {
                    'type': role == 'assistant' ? 'output_text' : 'input_text',
                    'text': text,
                  },
                ],
        });
      }
    }
    final instructionText = instructions.join('\n\n').trim();
    final body = <String, dynamic>{
      'model': chatBody['model'],
      'input': entry || codex
          ? messageInput
          : hasAttachment
              ? inputFromMessages(messages)
              : textInput.join('\n\n').trim(),
      // Ledger, report and chat data must never inherit server retention.
      'store': false,
    };
    if (entry || codex || instructionText.isNotEmpty) {
      body['instructions'] = instructionText.isEmpty
          ? 'You are a helpful assistant.'
          : instructionText;
    }
    if (entry) {
      body['stream'] = codex || config.isGptModel;
    } else if (codex) {
      body['stream'] = true;
    } else {
      final maxTokens = chatBody['max_tokens'];
      if (maxTokens is int && maxTokens > 0) {
        body['max_output_tokens'] = maxTokens;
      }
    }
    final effort = entry || codex
        ? config.reasoningEffort.codexResponsesApiValue
        : config.reasoningEffort.responsesApiValue;
    if (effort != null) body['reasoning'] = {'effort': effort};
    if (entry) {
      final format = chatBody['response_format'];
      final schema = chatBody['response_schema'];
      if (format is Map && format['type'] == 'json_object' && schema is Map) {
        body['text'] = {
          'format': {
            'type': 'json_schema',
            'name': 'codex_output_schema',
            'strict': true,
            'schema': Map<String, dynamic>.from(schema),
          },
        };
      }
    } else {
      final tools = config.responsesWebSearchTools;
      final includes = config.responsesWebSearchIncludes;
      if (tools.isNotEmpty) body['tools'] = tools;
      if (includes.isNotEmpty) body['include'] = includes;
    }
    return body;
  }

  static String stringContent(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) {
            if (part is String) return part;
            return part is Map ? part['text']?.toString() ?? '' : '';
          })
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
    }
    return content?.toString() ?? '';
  }

  static List<Map<String, dynamic>> contentParts(
    Object? content, {
    required bool assistant,
  }) {
    final textType = assistant ? 'output_text' : 'input_text';
    if (content is! List) {
      return [
        {'type': textType, 'text': content?.toString() ?? ''}
      ];
    }
    return [
      for (final part in content)
        if (part is Map && part['type'] == 'text')
          {'type': textType, 'text': part['text']?.toString() ?? ''}
        else if (part is Map && part['type'] == 'image_url')
          {
            'type': 'input_image',
            'image_url':
                (part['image_url'] is Map ? part['image_url']['url'] : null)
                    ?.toString(),
          }
        else if (part is Map && part['type'] == 'file')
          {
            'type': 'input_file',
            'filename': (part['file'] is Map ? part['file']['filename'] : null)
                ?.toString(),
            'file_data':
                (part['file'] is Map ? part['file']['file_data'] : null)
                    ?.toString(),
          },
    ];
  }

  static List<Map<String, dynamic>> inputFromMessages(Object? messages) {
    if (messages is! List) return const [];
    final input = <Map<String, dynamic>>[];
    for (final message in messages.whereType<Map>()) {
      final role = message['role']?.toString().trim().toLowerCase() ?? 'user';
      if (role == 'system' || role == 'developer') continue;
      final content = message['content'];
      if (content == null) continue;
      final parts = contentParts(content, assistant: role == 'assistant');
      if (parts.isEmpty) continue;
      input.add({
        'type': 'message',
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': parts,
      });
    }
    return input;
  }

  static String extractText(Object? decoded) {
    if (decoded is! Map) return '';
    final outputText = decoded['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) return outputText;
    final buffer = StringBuffer();
    void walk(Object? value) {
      if (value is Map) {
        final text = value['text'];
        if ((value['type'] == 'output_text' || value['type'] == 'text') &&
            text is String &&
            text.trim().isNotEmpty) {
          buffer.writeln(text.trim());
        }
        walk(value['content']);
        walk(value['output']);
      } else if (value is List) {
        for (final item in value) {
          walk(item);
        }
      }
    }

    walk(decoded['output']);
    return buffer.toString().trim();
  }

  /// Decode a single SSE data payload. Malformed optional/vendor events do not
  /// become visible text; terminal failures are handled by the consumer.
  static Map<String, dynamic>? decodeEvent(String data) {
    if (data.trim().isEmpty || data.trim() == '[DONE]') return null;
    try {
      final value = jsonDecode(data);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on FormatException {
      return null;
    }
  }

  static String eventType(Map<String, dynamic> event) =>
      event['type']?.toString().trim().toLowerCase() ?? '';

  static Iterable<Map<String, dynamic>> sseEvents(String body) sync* {
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data.trim() == '[DONE]') break;
      final event = decodeEvent(data);
      if (event != null) yield event;
    }
  }

  static String? textDelta(Map<String, dynamic> event) {
    final type = eventType(event);
    final delta = event['delta'];
    if (delta is String &&
        delta.isNotEmpty &&
        (type.contains('output_text.delta') ||
            type.contains('content_part.delta') ||
            type.isEmpty)) {
      return delta;
    }
    if (type.endsWith('.done') ||
        type.contains('completed') ||
        (type.isNotEmpty &&
            !type.contains('output_text') &&
            !type.contains('content_part'))) {
      return null;
    }
    final fallback = event['text'] ?? event['output_text'];
    return fallback is String && fallback.isNotEmpty ? fallback : null;
  }

  static String? completedText(Map<String, dynamic> event) {
    if (eventType(event) == 'response.output_text.done') {
      final text = event['text'];
      return text is String && text.trim().isNotEmpty ? text : null;
    }
    if (eventType(event) != 'response.completed') return null;
    final text = extractText(event['response']);
    return text.isEmpty ? null : text;
  }

  static ResponsesProtocolException? failure(Map<String, dynamic> event) {
    final type = eventType(event);
    if (type == 'response.incomplete') {
      final response = event['response'];
      final details = response is Map ? response['incomplete_details'] : null;
      final reason =
          details is Map ? details['reason']?.toString() : details?.toString();
      return ResponsesProtocolException(
          ResponsesFailureKind.incomplete,
          reason == null || reason.trim().isEmpty
              ? 'Responses 输出未完成'
              : 'Responses 输出未完成：${reason.trim()}');
    }
    if (type != 'response.failed' && type != 'error') return null;
    final response = event['response'];
    final error = response is Map ? response['error'] : event['error'];
    final message =
        error is Map ? error['message']?.toString() : error?.toString();
    return ResponsesProtocolException(
        ResponsesFailureKind.failed,
        message == null || message.trim().isEmpty
            ? 'Responses 生成失败'
            : message.trim());
  }

  static String collectSseText(String body, {bool requireComplete = false}) {
    final buffer = StringBuffer();
    String? completed;
    var finished = false;
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data.trim() == '[DONE]') {
        finished = true;
        break;
      }
      final event = decodeEvent(data);
      if (event == null) continue;
      final error = failure(event);
      if (error != null) throw error;
      completed = completedText(event) ?? completed;
      if (eventType(event) == 'response.completed') finished = true;
      final delta = textDelta(event);
      if (delta != null) buffer.write(delta);
    }
    if (requireComplete && !finished) {
      throw const ResponsesProtocolException(
          ResponsesFailureKind.interrupted, 'Responses 流式响应意外中断');
    }
    final result = buffer.toString().trim();
    final finalText = completed?.trim() ?? '';
    if (requireComplete) {
      return finalText.length >= result.length ? finalText : result;
    }
    return result.isNotEmpty ? result : finalText;
  }
}
