import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/chat_answer_metadata.dart';
import 'package:qingji/core/ai/ai_context.dart';
import 'package:qingji/core/ai/web_search.dart';

void main() {
  const source =
      AiWebSource(title: '参考', url: 'https://example.com', snippet: '摘要');
  test('兼容旧来源数组和损坏元数据', () {
    final old =
        ChatAnswerMetadata.decode(AiWebSearchContext.encodeSources([source]));
    expect(old.sources.single.url, source.url);
    expect(old.interrupted, isFalse);
    expect(old.thinking, isNull);
    expect(ChatAnswerMetadata.decode('{broken').sources, isEmpty);
  });
  test('中断与真实思考耗时摘要可以编码恢复', () {
    const metadata = ChatAnswerMetadata(
      sources: [source],
      interrupted: true,
      thinking: {
        'startedAt': '2026-10-04T10:00:00',
        'completedAt': '2026-10-04T10:00:11',
        'steps': [
          {'detail': '供应商返回的可展示摘要'}
        ]
      },
    );
    final restored = ChatAnswerMetadata.decode(metadata.encode());
    expect(restored.interrupted, isTrue);
    expect(restored.thinking, metadata.thinking);
    expect(restored.sources.single.title, source.title);
  });
  test('压缩上下文保留附件引用，不把本地路径当正文', () {
    final turns = AiContextCompressor.compactTurns([
      {
        'role': 'user',
        'content': '请看图片',
        'attachments_json': '[{"path":"private/image.png"}]'
      },
      {'role': 'assistant', 'content': '已有回复'},
    ]);
    expect(turns.first['attachments_json'], contains('private/image.png'));
    expect(turns.first['content'], isNot(contains('private/')));
  });
}
