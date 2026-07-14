import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;

import '../../theme/app_colors.dart';

class WidgetCardRenderSizes {
  WidgetCardRenderSizes._();

  // 宽 340 + 自然高度：接近 App 内卡片实际宽度（不截断长金额），
  // 4x2 格子里按高度贴合显示，字号≈App 原大。height 只是自然高度的上限。
  static const Size overview = Size(340, 380);
  static const Size pace = Size(340, 380);
}

Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required Size logicalSize,
  double pixelRatio = 2.0,
  // 宽度固定、高度跟内容走：预算模式卡天然比 2:1 高，硬塞固定高度画布
  // 会被 FittedBox 整体缩小、字变小一圈。开了这个开关 logicalSize.height
  // 只当上限用，画布高度=内容自然高度。
  bool naturalHeight = false,
  // 仅供桌面测试环境生成预览图用：测试引擎只有 Ahem 占位字体，
  // 传入已 FontLoader 注册的字族名可让全部文字用真字形。设备端不要传。
  String? fontFamily,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final binding = WidgetsBinding.instance;
  final views = binding.platformDispatcher.views;
  final view =
      views.isNotEmpty ? views.first : binding.platformDispatcher.implicitView;
  if (view == null) {
    throw StateError('No FlutterView available for offscreen widget render.');
  }

  final logicalConstraints = naturalHeight
      ? BoxConstraints(
          minWidth: logicalSize.width,
          maxWidth: logicalSize.width,
          maxHeight: logicalSize.height,
        )
      : BoxConstraints.tight(logicalSize);
  final repaintBoundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: logicalConstraints,
      physicalConstraints: logicalConstraints * pixelRatio,
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(
      alignment: Alignment.topLeft,
      child: repaintBoundary,
    ),
  );
  final pipelineOwner = PipelineOwner();
  // onBuildScheduled 必须给：图片解码完成会 setState 触发 scheduleBuildFor，
  // 没回调会断言崩。我们用固定次数的重刷收集脏元素，回调本身留空即可。
  final buildOwner = BuildOwner(
    focusManager: FocusManager(),
    onBuildScheduled: () {},
  );
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: _WidgetRenderRoot(
      logicalSize: logicalSize,
      pixelRatio: pixelRatio,
      naturalHeight: naturalHeight,
      fontFamily: fontFamily,
      child: widget,
    ),
  ).attachToRenderTree(buildOwner);

  void flushFrame() {
    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();
  }

  flushFrame();
  // Image.asset（猫/封面）解码是真实异步，要等真实时间再重刷几轮，
  // 否则真机上图片位置渲成空白。⚠️ 这里用了真实 Timer——
  // 在 testWidgets 里调用本函数必须包 tester.runAsync()，
  // 否则假异步时钟里 Timer 和引擎 Future 永远不完成（就是之前卡死的根因）。
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    flushFrame();
  }

  final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  final width = image.width;
  final height = image.height;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (byteData == null) {
    throw StateError('Failed to read offscreen widget pixels.');
  }
  return _encodeRgbaToPngInBackground(
    byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ),
    width: width,
    height: height,
  );
}

Future<Uint8List> _encodeRgbaToPngInBackground(
  Uint8List rgba, {
  required int width,
  required int height,
}) async {
  final pixels = TransferableTypedData.fromList([rgba]);
  final encoded = await Isolate.run(() {
    final bytes = pixels.materialize().asUint8List();
    final image = image_lib.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      numChannels: 4,
      order: image_lib.ChannelOrder.rgba,
    );
    return TransferableTypedData.fromList([
      image_lib.encodePng(image, level: 6),
    ]);
  });
  return encoded.materialize().asUint8List();
}

class WidgetCardCanvas extends StatelessWidget {
  final Size logicalSize;
  final Widget child;

  const WidgetCardCanvas({
    super.key,
    required this.logicalSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: logicalSize,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(width: logicalSize.width, child: child),
        ),
      ),
    );
  }
}

class _WidgetRenderRoot extends StatelessWidget {
  final Size logicalSize;
  final double pixelRatio;
  final bool naturalHeight;
  final String? fontFamily;
  final Widget child;

  const _WidgetRenderRoot({
    required this.logicalSize,
    required this.pixelRatio,
    required this.child,
    this.naturalHeight = false,
    this.fontFamily,
  });

  ThemeData _themeData() {
    final base = AppTheme.light();
    final ff = fontFamily;
    if (ff == null) return base;
    // 从主题层整体换字族：Card/Material 的 DefaultTextStyle 都来自 textTheme，
    // 这样连卡片内部的文字也能拿到真字形。fallback 也带上——
    // copyWith(fontFamily:'Nunito') 的样式会保留 fallback，中文字才有着落。
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: ff, fontFamilyFallback: [ff]),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamily: ff, fontFamilyFallback: [ff]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultAssetBundle(
      bundle: rootBundle,
      child: MediaQuery(
        data: MediaQueryData(
          size: logicalSize,
          devicePixelRatio: pixelRatio,
          textScaler: TextScaler.noScaling,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: _themeData(),
            // 离屏树没人推帧：关掉 Ticker（猫呼吸等动画停在初始帧），
            // 避免 AnimationController 在树外空转/泄漏警告。
            child: TickerMode(
              enabled: false,
              child: Material(
                type: MaterialType.transparency,
                // 自然高度：解除高度约束（unbounded），卡片内部
                // mainAxisSize.max 的 Column 才会收缩到内容高度，
                // 否则会撑满上限、PNG 底部一大截空白。
                child: naturalHeight
                    ? UnconstrainedBox(
                        constrainedAxis: Axis.horizontal,
                        alignment: Alignment.topLeft,
                        child: SizedBox(width: logicalSize.width, child: child),
                      )
                    : SizedBox.fromSize(size: logicalSize, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
