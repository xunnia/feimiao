import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 全 App 统一页面路由：Cupertino 转场（右滑返回）+ 自带不透明暖渐变底。
///
/// ⚠️ 为什么必须用它而不是裸 CupertinoPageRoute（2026-07-10 黑屏事故）：
/// 主题的 pageTransitionsTheme 只作用于 MaterialPageRoute，
/// CupertinoPageRoute 走自己的转场——渐变注入不到，页面 Scaffold 又是
/// 透明的（全局暖渐变方案），结果所有 push 页面露出引擎默认黑底。
/// 以后新页面一律 `AppPageRoute(builder: ...)`。
class AppPageRoute<T> extends CupertinoPageRoute<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
          builder: (context) => DecoratedBox(
            decoration:
                AppColors.pageBackground(Theme.of(context).brightness),
            child: builder(context),
          ),
        );
}
