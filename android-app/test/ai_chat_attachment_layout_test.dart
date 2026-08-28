import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

void main() {
  test('已发送三张图片在可用宽度内等分且不溢出', () {
    const width = 276.0;
    final tileWidth = sentAttachmentTileWidth(width, 3);

    expect(tileWidth, 88);
    expect(tileWidth * 3 + 6 * 2, width);
    expect(sentAttachmentTileHeight(width, 3), closeTo(88, 0.001));
  });

  test('一张与两张图片仍保留原有宽度标准', () {
    expect(sentAttachmentTileWidth(276, 1), 276);
    expect(sentAttachmentTileWidth(276, 2), 135);
  });

  test('输入框附件首屏严格容纳三张，第四张从下一屏开始', () {
    const width = 326.0;
    final tileWidth = draftAttachmentTileWidth(width);

    expect(tileWidth * 3 + 8 * 2, width);
    expect(tileWidth * 3 + 8 * 3, greaterThan(width));
  });

  test('草稿附件累计添加时共享三张图片和十个文件的上限', () {
    ChatAttachment image(int index) => ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: 'image-$index.png',
          name: '图片$index.png',
          mimeType: 'image/png',
          sizeBytes: 1,
        );
    ChatAttachment file(int index) => ChatAttachment(
          kind: ChatAttachmentKind.file,
          path: 'file-$index.txt',
          name: '文件$index.txt',
          mimeType: 'text/plain',
          sizeBytes: 1,
        );

    final firstBatch = [image(1), image(2)];
    final secondBatch = [image(3), image(4), file(1)];
    final accepted = fitDraftAttachments(firstBatch, secondBatch);

    expect(accepted.map((item) => item.name), ['图片3.png', '文件1.txt']);
    expect(
      fitDraftAttachments(
        [for (var i = 0; i < 10; i++) file(i)],
        [file(11)],
      ),
      isEmpty,
    );
  });

  test('聊天历史上拉最多越界 88dp，松手仍回到真实边界', () {
    final physics = aiChatScrollPhysicsForTesting();
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: 100,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(physics.applyBoundaryConditions(metrics, 150), 0);
    expect(physics.applyBoundaryConditions(metrics, 188), 0);
    expect(physics.applyBoundaryConditions(metrics, 220), 32);
    expect(physics.applyBoundaryConditions(metrics, -120), -32);
  });
}
