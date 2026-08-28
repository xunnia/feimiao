import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AiContextBlockKind { question, history, ledger, memory, attachment, tool }

extension AiContextBlockKindX on AiContextBlockKind {
  String get storageKey => name;

  String get label => switch (this) {
        AiContextBlockKind.question => '当前问题',
        AiContextBlockKind.history => '会话历史',
        AiContextBlockKind.ledger => '账本上下文',
        AiContextBlockKind.memory => '已授权记忆',
        AiContextBlockKind.attachment => '附件',
        AiContextBlockKind.tool => '工具结果',
      };
}

class AiContextBlock {
  final AiContextBlockKind kind;
  final String label;
  final int itemCount;
  final int estimatedTokens;
  final bool sensitive;
  final String digest;

  const AiContextBlock({
    required this.kind,
    required this.label,
    this.itemCount = 0,
    this.estimatedTokens = 0,
    this.sensitive = false,
    this.digest = '',
  });

  Map<String, Object?> toJson() => {
        'kind': kind.storageKey,
        'label': label,
        'itemCount': itemCount,
        'estimatedTokens': estimatedTokens,
        'sensitive': sensitive,
        'digest': digest,
      };

  factory AiContextBlock.fromJson(Map<String, Object?> json) {
    final kind = AiContextBlockKind.values.firstWhere(
      (value) => value.storageKey == json['kind']?.toString(),
      orElse: () => AiContextBlockKind.tool,
    );
    return AiContextBlock(
      kind: kind,
      label: json['label']?.toString() ?? kind.label,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      estimatedTokens: (json['estimatedTokens'] as num?)?.toInt() ?? 0,
      sensitive: json['sensitive'] == true,
      digest: json['digest']?.toString() ?? '',
    );
  }
}

class AiContextSnapshot {
  final List<AiContextBlock> blocks;
  final int estimatedTokens;

  /// Caller-provided character estimate for the provider prompt. Only the
  /// count is retained; raw prompt text is intentionally never persisted.
  final int promptCharacters;
  final int maxTokens;
  final bool truncated;
  final int createdMs;

  const AiContextSnapshot({
    required this.blocks,
    required this.estimatedTokens,
    this.promptCharacters = 0,
    this.maxTokens = 0,
    this.truncated = false,
    required this.createdMs,
  });

  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  Map<String, Object?> toJson() => {
        'blocks': blocks.map((block) => block.toJson()).toList(),
        'estimatedTokens': estimatedTokens,
        'promptCharacters': promptCharacters,
        'maxTokens': maxTokens,
        'truncated': truncated,
        'createdMs': createdMs,
      };

  String encode() => jsonEncode(toJson());

  factory AiContextSnapshot.fromJson(Map<String, Object?> json) =>
      AiContextSnapshot(
        blocks: ((json['blocks'] as List?) ?? const [])
            .whereType<Map>()
            .map((block) => AiContextBlock.fromJson(
                  block.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList(growable: false),
        estimatedTokens: (json['estimatedTokens'] as num?)?.toInt() ?? 0,
        promptCharacters: (json['promptCharacters'] as num?)?.toInt() ?? 0,
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 0,
        truncated: json['truncated'] == true,
        createdMs: (json['createdMs'] as num?)?.toInt() ?? 0,
      );
}

/// Builds a privacy-safe inventory of the context sent to a provider. It
/// stores counts and digests, never the raw prompt, transaction rows or file
/// bytes.
class AiContextInspector {
  AiContextInspector._();

  static AiContextSnapshot inspect({
    String question = '',
    int historyTurns = 0,
    int ledgerRows = 0,
    int memoryItems = 0,
    int attachmentCount = 0,
    int toolResults = 0,
    int estimatedPromptCharacters = 0,
    int maxTokens = 0,
  }) {
    int estimate(int characters, int fallback) =>
        (characters > 0 ? characters : fallback * 24 + 8) ~/ 4;
    final blocks = <AiContextBlock>[
      AiContextBlock(
        kind: AiContextBlockKind.question,
        label: AiContextBlockKind.question.label,
        itemCount: question.trim().isEmpty ? 0 : 1,
        estimatedTokens:
            estimate(question.length, question.trim().isEmpty ? 0 : 1),
        digest: _digest(question),
      ),
      if (historyTurns > 0)
        AiContextBlock(
          kind: AiContextBlockKind.history,
          label: AiContextBlockKind.history.label,
          itemCount: historyTurns,
          estimatedTokens: estimate(0, historyTurns),
        ),
      if (ledgerRows > 0)
        AiContextBlock(
          kind: AiContextBlockKind.ledger,
          label: AiContextBlockKind.ledger.label,
          itemCount: ledgerRows,
          estimatedTokens: estimate(0, ledgerRows),
          sensitive: true,
        ),
      if (memoryItems > 0)
        AiContextBlock(
          kind: AiContextBlockKind.memory,
          label: AiContextBlockKind.memory.label,
          itemCount: memoryItems,
          estimatedTokens: estimate(0, memoryItems),
          sensitive: true,
        ),
      if (attachmentCount > 0)
        AiContextBlock(
          kind: AiContextBlockKind.attachment,
          label: AiContextBlockKind.attachment.label,
          itemCount: attachmentCount,
          estimatedTokens: estimate(0, attachmentCount * 220),
          sensitive: true,
        ),
      if (toolResults > 0)
        AiContextBlock(
          kind: AiContextBlockKind.tool,
          label: AiContextBlockKind.tool.label,
          itemCount: toolResults,
          estimatedTokens: estimate(0, toolResults * 80),
        ),
    ];
    final blockTotal = blocks.fold<int>(
      0,
      (sum, block) => sum + block.estimatedTokens,
    );
    // The caller may know the final assembled prompt is larger than the
    // structured block inventory (for example, provider instructions and
    // formatting wrappers). Use the larger estimate without double-counting
    // the same characters as another block.
    final promptTokens = estimatedPromptCharacters > 0
        ? estimate(estimatedPromptCharacters, 0)
        : 0;
    final total = blockTotal > promptTokens ? blockTotal : promptTokens;
    return AiContextSnapshot(
      blocks: List.unmodifiable(blocks),
      estimatedTokens: total,
      promptCharacters: estimatedPromptCharacters < 0
          ? 0
          : (estimatedPromptCharacters > (1 << 30)
              ? (1 << 30)
              : estimatedPromptCharacters),
      maxTokens: maxTokens,
      truncated: maxTokens > 0 && total > maxTokens,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _digest(String value) =>
      value.trim().isEmpty ? '' : sha256.convert(utf8.encode(value)).toString();
}

/// Keeps multi-turn prompts bounded without storing or sending a second copy
/// of the conversation. Recent turns win; long individual messages retain
/// both their beginning and ending so a question and its conclusion survive
/// compression.
class AiContextCompressor {
  AiContextCompressor._();

  static const defaultMaxCharacters = 12000;
  static const defaultMaxCharactersPerTurn = 2400;

  static List<Map<String, String>> compactTurns(
    Iterable<Map<String, String>> turns, {
    int maxCharacters = defaultMaxCharacters,
    int maxCharactersPerTurn = defaultMaxCharactersPerTurn,
  }) {
    final all = turns
        .map(
          (turn) => <String, String>{
            'role': turn['role']?.trim().isEmpty ?? true
                ? 'user'
                : turn['role']!.trim(),
            'content': turn['content'] ?? '',
          },
        )
        .where((turn) => turn['content']!.trim().isNotEmpty)
        .toList(growable: false);
    if (all.isEmpty || maxCharacters <= 0 || maxCharactersPerTurn <= 0) {
      return const [];
    }

    final kept = <Map<String, String>>[];
    var remaining = maxCharacters;
    var omittedTurns = 0;
    for (final turn in all.reversed) {
      if (remaining <= 0) {
        omittedTurns++;
        continue;
      }
      // Reserve a small amount for role/JSON framing that the caller adds.
      final budget = (remaining - 24).clamp(1, maxCharactersPerTurn).toInt();
      final content = compactText(turn['content']!, budget);
      kept.add({'role': turn['role']!, 'content': content});
      remaining -= content.length + 24;
    }
    if (kept.isEmpty) return const [];

    final result = kept.reversed.toList(growable: true);
    if (omittedTurns > 0) {
      final oldest = result.first;
      result[0] = {
        'role': oldest['role']!,
        'content': '【更早的 $omittedTurns 轮对话已压缩】\n${oldest['content']}',
      };
    }
    return List.unmodifiable(result);
  }

  static String compactText(String text, int maxCharacters) {
    final runes = text.runes.toList(growable: false);
    if (maxCharacters <= 0 || runes.length <= maxCharacters) return text;
    if (maxCharacters <= 24) {
      return String.fromCharCodes(runes.take(maxCharacters));
    }
    const marker = '\n…【本段上下文已压缩】…\n';
    final available = maxCharacters - marker.length;
    final head = (available * 0.62).floor();
    final tail = available - head;
    return String.fromCharCodes(runes.take(head)) +
        marker +
        String.fromCharCodes(runes.skip(runes.length - tail));
  }
}
