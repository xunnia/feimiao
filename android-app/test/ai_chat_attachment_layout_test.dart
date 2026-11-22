import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/widgets/glass_input.dart';

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

  test('草稿附件累计添加时共享四张图片和十个文件的上限', () {
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

    expect(
        accepted.map((item) => item.name), ['图片3.png', '图片4.png', '文件1.txt']);
    expect(
        fitDraftAttachments([...firstBatch, ...accepted], [image(5)]), isEmpty);
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

    // 边界检查不再通过 applyBoundaryConditions 提前截断回弹动画；越界上限在
    // applyPhysicsToUserOffset 与 createBallisticSimulation 中约束。
    expect(physics.applyBoundaryConditions(metrics, 220), 0);
    expect(physics.applyBoundaryConditions(metrics, -120), 0);

    // 拖动拉过底部 / 顶部时，越界偏移最多到达 ±kAiChatMaxOverscroll。
    final atMaxOverscroll = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: 100 + kAiChatMaxOverscroll,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(physics.applyPhysicsToUserOffset(atMaxOverscroll, -50), 0);

    final atMinOverscroll = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: -kAiChatMaxOverscroll,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(physics.applyPhysicsToUserOffset(atMinOverscroll, 50), 0);
  });

  testWidgets('下拉越界松手（含快甩惯性）稳定回弹到边界，不悬停', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 390,
          height: 600,
          child: ListView(
            controller: controller,
            physics: aiChatScrollPhysicsForTesting(),
            children: const [
              SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.position.pixels, 0);

    // 1. 强力向下快甩（在顶边界继续往负方向给惯性速度）——修复前会触发
    // applyBoundaryConditions 返回非零，导致 BallisticScrollActivity 提前
    // goIdle() 并悬停在 -88dp。
    await tester.fling(find.byType(ListView), const Offset(0, 600), 2200);
    await tester.pump();
    // 越界幅度仍被限制在 kAiChatMaxOverscroll 内。
    expect(controller.position.pixels, greaterThanOrEqualTo(-kAiChatMaxOverscroll - 0.1));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(0.0, 0.5));

    // 2. 慢拉到顶边界外再松手，同样回到 0。
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    expect(controller.position.pixels, lessThan(0));
    expect(controller.position.pixels, greaterThanOrEqualTo(-kAiChatMaxOverscroll - 0.1));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(0.0, 0.5));

    // 3. 滑到底部后再向上快甩，同样限幅且回弹到 maxScrollExtent。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2200);
    await tester.pump();
    expect(
      controller.position.pixels,
      lessThanOrEqualTo(
        controller.position.maxScrollExtent + kAiChatMaxOverscroll + 0.1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.position.pixels,
      closeTo(controller.position.maxScrollExtent, 0.5),
    );
  });

  testWidgets('输入框暂停模糊（键盘/降动效）时自动抬高不透明度保障可读性', (tester) async {
    Future<double> renderedAlpha({
      required bool blurEnabled,
      required bool disableAnimations,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Center(
                child: AppGlassInputShell(
                  blur: 10,
                  blurEnabled: blurEnabled,
                  child: const Text('聊点什么'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(AppGlassInputShell),
          matching: find.byType(Container),
        ),
      );
      final fill = containers
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color != null)
          .color!;
      return fill.a;
    }

    expect(
      await renderedAlpha(blurEnabled: true, disableAnimations: false),
      closeTo(0.78, 0.01),
    );
    expect(
      await renderedAlpha(blurEnabled: false, disableAnimations: false),
      closeTo(0.88, 0.01),
    );
    expect(
      await renderedAlpha(blurEnabled: true, disableAnimations: true),
      closeTo(0.88, 0.01),
    );
  });
}
