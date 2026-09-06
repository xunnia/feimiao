import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/model_fetcher.dart';
import '../../data/app_repository.dart';

/// 模型管理器底部抽屉
/// 用于选择和管理服务商的可用模型列表
class ModelManagerSheet extends StatefulWidget {
  final String providerId;
  final List<AiModelInfo> availableModels;

  const ModelManagerSheet({
    super.key,
    required this.providerId,
    required this.availableModels,
  });

  @override
  State<ModelManagerSheet> createState() => _ModelManagerSheetState();
}

class _ModelManagerSheetState extends State<ModelManagerSheet> {
  final Set<String> _selectedModels = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSavedModels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedModels() async {
    final repo = context.read<AppRepository>();
    final rows = await repo.getFilteredModels(widget.providerId);
    setState(() {
      _selectedModels.addAll(rows.map((r) => r['model_id'] as String));
    });
  }

  List<AiModelInfo> get _filteredModels {
    if (_searchQuery.isEmpty) return widget.availableModels;
    final query = _searchQuery.toLowerCase();
    return widget.availableModels
        .where((m) => m.id.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filteredModels = _filteredModels;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择模型',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${widget.availableModels.length} 个可用模型',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedModels.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '已选 ${_selectedModels.length}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: '搜索模型...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 快捷操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedModels.addAll(
                        filteredModels.map((m) => m.id),
                      );
                    });
                  },
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('全选'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _selectedModels.clear());
                  },
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 模型列表
          if (filteredModels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 48,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '没有找到匹配的模型',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredModels.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final model = filteredModels[index];
                  final selected = _selectedModels.contains(model.id);

                  return CheckboxListTile(
                    value: selected,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedModels.add(model.id);
                        } else {
                          _selectedModels.remove(model.id);
                        }
                      });
                    },
                    title: Text(
                      model.id,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                    subtitle: model.ownedBy != null
                        ? Text(
                            'by ${model.ownedBy}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  );
                },
              ),
            ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _selectedModels.isEmpty
                          ? null
                          : () => Navigator.pop(
                                context,
                                _selectedModels.toList(),
                              ),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(
                        _selectedModels.isEmpty
                            ? '确定'
                            : '确定 (${_selectedModels.length})',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
