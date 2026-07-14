// 临时工具测试：把全部分类图标渲成网格 PNG 供人工审查（不进 CI 断言）。
// 用法：UPDATE_ICON_GRID=1 flutter test test/icon_grid_render_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/cat_svg_icon.dart';
import 'package:qingji/core/models/category_seed.dart';
import 'package:qingji/core/widgets/widget_card_renderer.dart';

void main() {
  testWidgets('render all category icons to grid png', (tester) async {
    if (Platform.environment['UPDATE_ICON_GRID'] != '1') return;
    final keys = kSvgCategoryKeys.toList()..sort();
    final names = {for (final s in CategorySeed.all) s.key: s.nameZh};
    const perRow = 8;

    final grid = Container(
      color: const Color(0xFFFFFDF7),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r * perRow < keys.length; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (var c = 0;
                      c < perRow && r * perRow + c < keys.length;
                      c++)
                    Expanded(
                      child: Column(
                        children: [
                          CatIcon(
                            categoryKey: keys[r * perRow + c],
                            emoji: CategorySeed.emojiOf(keys[r * perRow + c]),
                            size: 44,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            names[keys[r * perRow + c]] ??
                                keys[r * perRow + c],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    final png = await tester.runAsync(() => renderWidgetToPng(
          grid,
          logicalSize: const Size(560, 2400),
          naturalHeight: true,
          pixelRatio: 2,
          fontFamily: 'PreviewCJK',
        ));
    await tester.runAsync(() => File(
          Platform.environment['ICON_GRID_OUT'] ?? 'icon_grid.png',
        ).writeAsBytes(png!));
  });
}
