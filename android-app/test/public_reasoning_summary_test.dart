import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/public_reasoning_summary.dart';

void main() {
  test('真实增量保留空白、段落和超过420字符的前文', () {
    final summary = PublicReasoningSummary();
    for (final part in ['**核对范围**', '\n\n', '前文', 'a' * 500, '\n\n', '后文']) {
      summary.append(part);
    }
    expect(summary.text, '**核对范围**\n\n前文${'a' * 500}\n\n后文');
    expect(summary.truncated, isFalse);
  });
  test('内存有上限，不切断 emoji，也不丢弃开头', () {
    final summary = PublicReasoningSummary();
    summary.append('a' * (PublicReasoningSummary.maxCharacters - 1));
    summary.append('😀后文');
    expect(summary.truncated, isTrue);
    expect(summary.text, 'a' * (PublicReasoningSummary.maxCharacters - 1));
    expect(summary.append(''), isFalse);
  });
}
