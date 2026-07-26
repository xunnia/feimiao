import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

void main() {
  test('typewriter reveals complete Unicode grapheme clusters', () {
    const text = 'A👨‍👩‍👧‍👦👍🏽e\u0301🇨🇳B';

    expect(aiTypewriterLength(text), 6);
    expect(aiTypewriterPrefix(text, -1), '');
    expect(aiTypewriterPrefix(text, 1), 'A');
    expect(aiTypewriterPrefix(text, 2), 'A👨‍👩‍👧‍👦');
    expect(aiTypewriterPrefix(text, 3), 'A👨‍👩‍👧‍👦👍🏽');
    expect(aiTypewriterPrefix(text, 4), 'A👨‍👩‍👧‍👦👍🏽e\u0301');
    expect(aiTypewriterPrefix(text, 5), 'A👨‍👩‍👧‍👦👍🏽e\u0301🇨🇳');
    expect(aiTypewriterPrefix(text, 99), text);
  });
}
