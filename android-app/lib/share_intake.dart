import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'views/home/record_entry_sheet.dart';
import 'views/quick_add/ai_quick_entry_view.dart';
import 'views/quick_add/screenshot_entry.dart';
import 'views/statistics/category_txns_view.dart';
import 'views/statistics/statistics_view.dart';
import 'widgets/app_page_route.dart';

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
  static Future<void>? _repositoryReady;
  static bool Function()? _repositoryReadyCheck;
  static final List<void Function(BuildContext)> _pendingActions = [];
  static bool _flushing = false;

  static void init({
    Future<void>? repositoryReady,
    bool Function()? repositoryReadyCheck,
  }) {
    _repositoryReady = repositoryReady;
    _repositoryReadyCheck = repositoryReadyCheck;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is Map) {
        _handle(Map<String, dynamic>.from(call.arguments as Map));
      } else if (call.method == 'onOpen' && call.arguments is Map) {
        _handleOpen(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initial = await _channel.invokeMethod('consumeInitialShare');
        if (initial is Map) {
          _handle(Map<String, dynamic>.from(initial));
        }
        final open = await _channel.invokeMethod('consumeInitialOpen');
        if (open is Map) {
          _handleOpen(Map<String, dynamic>.from(open));
        }
      } catch (_) {
        // 没有分享内容或通道未就绪都正常，忽略。
      }
    });
  }

  static void _handle(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'text') {
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) return;
      _enqueue((ctx) {
        Navigator.of(ctx).push(AppPageRoute<void>(
          builder: (_) => AiQuickEntryView(initialText: text),
        ));
      });
    } else if (type == 'image') {
      final path = (data['path'] ?? '').toString();
      if (path.isEmpty) return;
      _enqueue((ctx) => recognizeImagePathAndEntry(ctx, path));
    }
  }

  static void _handleOpen(Map<String, dynamic> data) {
    _enqueue((ctx) => _dispatchOpen(ctx, data));
  }

  /// Cold-start shares can arrive before Navigator exists and before SQLite
  /// has loaded categories/accounts. Queue them instead of silently dropping
  /// the user's share or opening a half-empty quick-entry page.
  static void _enqueue(void Function(BuildContext) action) {
    _pendingActions.add(action);
    _flushPending();
  }

  static void _flushPending() {
    if (_flushing) return;
    _flushing = true;
    unawaited(_flushPendingAsync());
  }

  static Future<void> _flushPendingAsync() async {
    // 已经注册了帧回调重试时，finally 里不能再同步重入 _flushPending：
    // ctx 未就绪前那会变成「注册回调→finally 重入→再注册回调」的死循环。
    var retryScheduled = false;
    try {
      final ready = _repositoryReady;
      if (ready != null) await ready;
      if (_repositoryReadyCheck != null && !_repositoryReadyCheck!()) {
        // Initialization failed. Do not replay a share into a repository that
        // cannot save it; the native pending intent has already been consumed.
        _pendingActions.clear();
        return;
      }
      while (_pendingActions.isNotEmpty) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) {
          retryScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _flushPending());
          return;
        }
        final action = _pendingActions.removeAt(0);
        action(ctx);
        // Let a route push/image pipeline yield before replaying another item.
        await Future<void>.value();
      }
    } finally {
      _flushing = false;
      if (!retryScheduled && _pendingActions.isNotEmpty) _flushPending();
    }
  }

  static void _dispatchOpen(BuildContext ctx, Map<String, dynamic> data) {
    final target = data['target']?.toString();
    if (target == 'quick_add') {
      final repo = ctx.read<AppRepository>();
      showRecordEntrySheet(
        ctx,
        initialMode:
            repo.recordAiMode ? RecordEntryMode.ai : RecordEntryMode.manual,
        onModeChanged: repo.setRecordAiMode,
      );
      return;
    }
    if (target == 'statistics' || target == 'statistics_categories') {
      Navigator.of(ctx).push(AppPageRoute<void>(
        builder: (_) => const StatisticsView(),
      ));
      return;
    }
    if (target == 'statistics_category') {
      _openWidgetCategory(ctx, data);
    }
  }

  static void _openWidgetCategory(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final repo = context.read<AppRepository>();
    final id = int.tryParse(data['categoryId']?.toString() ?? '');
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1, 0);

    if (id == null) {
      Navigator.of(context).push(AppPageRoute<void>(
        builder: (_) => const StatisticsView(),
      ));
      return;
    }

    CategoryEntity? selected;
    for (final category in repo.categories) {
      if (category.id == id) {
        selected = category;
        break;
      }
    }

    final title = selected?.nameZh ?? '其他';
    final names = <String>{title};
    if (selected != null && selected.parentId == null) {
      for (final child in repo.childrenOf(selected.id)) {
        names.add(child.nameZh);
      }
    }

    Navigator.of(context).push(AppPageRoute<void>(
      builder: (_) => CategoryTxnsView(
        categoryName: title,
        categoryNames: names,
        start: start,
        end: end,
      ),
    ));
  }
}
