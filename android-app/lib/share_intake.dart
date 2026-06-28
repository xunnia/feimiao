import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'views/quick_add/ai_quick_entry_view.dart';
import 'views/quick_add/screenshot_entry.dart';

/// 「分享到肥喵」：接收别的 App 通过系统分享发来的截图 / 文字，
/// 自动进入解析记账。原生侧见 MainActivity.kt（MethodChannel: feimiao/share）。
/// - 冷启动：首帧后主动 consumeInitialShare 取一次。
/// - 热启动：监听 onShare 推送。
class ShareIntake {
  ShareIntake._();

  /// 给 MaterialApp 用的全局导航 key（分享回来时不依赖某个页面的 context）。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const MethodChannel _channel = MethodChannel('feimiao/share');

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is Map) {
        _handle(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initial = await _channel.invokeMethod('consumeInitialShare');
        if (initial is Map) {
          _handle(Map<String, dynamic>.from(initial));
        }
      } catch (_) {
        // 没有分享内容或通道未就绪都正常，忽略。
      }
    });
  }

  static void _handle(Map<String, dynamic> data) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final type = data['type']?.toString();
    if (type == 'text') {
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) return;
      Navigator.of(ctx).push(CupertinoPageRoute<void>(
        builder: (_) => AiQuickEntryView(initialText: text),
      ));
    } else if (type == 'image') {
      final path = (data['path'] ?? '').toString();
      if (path.isEmpty) return;
      recognizeImagePathAndEntry(ctx, path);
    }
  }
}
