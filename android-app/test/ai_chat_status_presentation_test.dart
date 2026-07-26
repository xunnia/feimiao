import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

void main() {
  test('AI response presentation constants stay compact and predictable', () {
    expect(
      kAiBackgroundResponseNoticeDelay,
      const Duration(seconds: 15),
    );
    expect(kAiResponseActionIconExtent, 17.2);
    expect(kAiResponseActionTouchExtent, 36);
  });

  test('thinking status changes only after the background notice delay', () {
    final beforeThreshold = aiThinkingStatusText(
      elapsed: const Duration(milliseconds: 14999),
      canContinueInBackground: true,
    );
    final backgroundAtThreshold = aiThinkingStatusText(
      elapsed: const Duration(seconds: 15),
      canContinueInBackground: true,
    );
    final foregroundAtThreshold = aiThinkingStatusText(
      elapsed: const Duration(seconds: 15),
      canContinueInBackground: false,
    );

    expect(beforeThreshold, '思考中…');
    expect(backgroundAtThreshold, '喵会在后台继续处理，完成后会显示在这里。');
    expect(foregroundAtThreshold, '喵还在思考，完成后会显示在这里。');

    for (final status in <String>[
      beforeThreshold,
      backgroundAtThreshold,
      foregroundAtThreshold,
    ]) {
      expect(status, isNot(contains('拆分账单')));
      expect(status, isNot(contains('分析结构')));
      expect(status, isNot(contains('秒')));
    }
  });
}
