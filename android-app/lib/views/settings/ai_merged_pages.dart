import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../widgets/app_buttons.dart';
import '../../widgets/sliding_segment.dart';
import 'ai_companion_views.dart';
import 'memory_view.dart';

/// 设置首页「AI」分组里的合并页（01 §4「账号与设置」），和 iOS `AIMergedPages.swift` 对应：
/// 「可控记忆」和「喵学到的分类」合成「记忆」；任务中心和诊断合成「任务与诊断」。
/// 两页都用顶部分段切换，内容沿用原页面。

enum MemoryHubTab { aiMemory, categories }

class MemoryHubView extends StatefulWidget {
  const MemoryHubView({super.key, this.initialTab = MemoryHubTab.aiMemory});

  final MemoryHubTab initialTab;

  @override
  State<MemoryHubView> createState() => _MemoryHubViewState();
}

class _MemoryHubViewState extends State<MemoryHubView> {
  late MemoryHubTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return _MergedPageScaffold(
      title: '记忆',
      segment: SlidingSegment<MemoryHubTab>(
        key: const ValueKey('memory-hub-tabs'),
        items: const [
          (MemoryHubTab.aiMemory, '可控记忆'),
          (MemoryHubTab.categories, '喵学到的分类'),
        ],
        value: _tab,
        onChanged: (tab) => setState(() => _tab = tab),
      ),
      // 分类记忆没有「添加」，学错了在列表里删。
      action: _tab == MemoryHubTab.aiMemory
          ? AppCircleButton(
              icon: CupertinoIcons.add,
              semanticLabel: '添加一条记忆',
              onPressed: () => addAiMemory(context),
            )
          : null,
      body: switch (_tab) {
        MemoryHubTab.aiMemory => const AiMemoryControlBody(),
        MemoryHubTab.categories => const CategoryMemoryBody(),
      },
    );
  }
}

enum AiTaskDiagnosticsTab { tasks, diagnostics }

class AiTaskDiagnosticsView extends StatefulWidget {
  const AiTaskDiagnosticsView({
    super.key,
    this.initialTab = AiTaskDiagnosticsTab.tasks,
  });

  final AiTaskDiagnosticsTab initialTab;

  @override
  State<AiTaskDiagnosticsView> createState() => _AiTaskDiagnosticsViewState();
}

class _AiTaskDiagnosticsViewState extends State<AiTaskDiagnosticsView> {
  late AiTaskDiagnosticsTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return _MergedPageScaffold(
      title: '任务与诊断',
      segment: SlidingSegment<AiTaskDiagnosticsTab>(
        key: const ValueKey('task-diagnostics-tabs'),
        items: const [
          (AiTaskDiagnosticsTab.tasks, '任务'),
          (AiTaskDiagnosticsTab.diagnostics, '诊断'),
        ],
        value: _tab,
        onChanged: (tab) => setState(() => _tab = tab),
      ),
      action: _tab == AiTaskDiagnosticsTab.diagnostics
          ? AppCircleButton(
              icon: CupertinoIcons.doc_on_clipboard,
              semanticLabel: '复制诊断摘要',
              onPressed: () => copyAiDiagnostics(context),
            )
          : null,
      body: switch (_tab) {
        AiTaskDiagnosticsTab.tasks => const AiTaskCenterBody(),
        AiTaskDiagnosticsTab.diagnostics => const AiDiagnosticsBody(),
      },
    );
  }
}

class _MergedPageScaffold extends StatelessWidget {
  const _MergedPageScaffold({
    required this.title,
    required this.segment,
    required this.body,
    this.action,
  });

  final String title;
  final Widget segment;
  final Widget body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(title),
        centerTitle: true,
        actions: [
          if (action != null)
            Padding(padding: const EdgeInsets.only(right: 12), child: action),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: segment,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
