import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_context.dart';

void main() {
  test('context snapshot round trips block metadata', () {
    final original = AiContextInspector.inspect(
      question: 'how much did I spend',
      historyTurns: 2,
      ledgerRows: 5,
      memoryItems: 1,
      attachmentCount: 2,
      toolResults: 1,
      estimatedPromptCharacters: 480,
    );
    final restored = AiContextSnapshot.fromJson(original.toJson());
    expect(restored.blocks.map((item) => item.label), contains('当前问题'));
    expect(restored.estimatedTokens, original.estimatedTokens);
    expect(restored.promptCharacters, 480);
    expect(restored.digest, original.digest);
  });

  test('prompt character estimate is included without persisting raw text', () {
    final compact = AiContextInspector.inspect(
      question: 'x',
      estimatedPromptCharacters: 4000,
    );
    final withoutPrompt = AiContextInspector.inspect(question: 'x');
    expect(compact.promptCharacters, 4000);
    expect(compact.estimatedTokens, greaterThan(withoutPrompt.estimatedTokens));
    expect(compact.encode(), isNot(contains('xxxx')));
  });

  test('conversation compression keeps recent turns and bounds long text', () {
    final turns = [
      {'role': 'user', 'content': '最早的问题'},
      {'role': 'assistant', 'content': '很长的回答' * 900},
      {'role': 'user', 'content': '最新的问题'},
    ];
    final compact = AiContextCompressor.compactTurns(
      turns,
      maxCharacters: 180,
      maxCharactersPerTurn: 90,
    );
    expect(compact, isNotEmpty);
    expect(compact.last['content'], '最新的问题');
    expect(compact.map((turn) => turn['content']).join(), contains('本段上下文已压缩'));
    expect(
      compact.fold<int>(0, (sum, turn) => sum + turn['content']!.length),
      lessThanOrEqualTo(180),
    );
  });
}
