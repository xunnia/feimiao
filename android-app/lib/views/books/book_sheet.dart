import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/pressable_scale.dart';
import '../common/app_sheet.dart';

/// 常用账本模板（对齐团团记账的预置账本，去掉共享类）。
/// 封面现用 emoji+浅色底占位；用户提供成品封面图后换成
/// `assets/book_covers/<key>.png` 的 Image.asset。
class BookTemplate {
  final String key;
  final String name;
  final String emoji;
  final Color tint;

  const BookTemplate(this.key, this.name, this.emoji, this.tint);
}

const List<BookTemplate> kBookTemplates = [
  BookTemplate('daily', '日常生活', '📒', Color(0xFFEDF1F5)),
  BookTemplate('dining', '餐饮账本', '🍜', Color(0xFFFDEBD8)),
  BookTemplate('shopping', '网购账本', '📦', Color(0xFFE8F0E4)),
  BookTemplate('travel', '旅游账本', '🧳', Color(0xFFDDEFF7)),
  BookTemplate('pet', '宠物账本', '🐱', Color(0xFFF6E8DC)),
  BookTemplate('baby', '母婴账本', '🍼', Color(0xFFFBE9EE)),
  BookTemplate('family', '家庭账本', '🏠', Color(0xFFEFEBE2)),
  BookTemplate('business', '生意账本', '💼', Color(0xFFE4E9F2)),
  BookTemplate('couple', '情侣账本', '💑', Color(0xFFF9E4EA)),
];

/// 弹「新建账本」半屏页；[edit] 传入则是编辑既有账本。
Future<void> showBookSheet(BuildContext context, {BookEntity? edit}) {
  return appSheet<void>(context, child: _BookSheet(edit: edit));
}

class _BookSheet extends StatefulWidget {
  final BookEntity? edit;

  const _BookSheet({this.edit});

  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.edit?.name ?? '');
  late String _icon = widget.edit?.icon ?? '📒';
  late bool _includeInTotal = widget.edit?.includeInTotal ?? true;
  String? _pickedTemplate;

  bool get _isEdit => widget.edit != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pickTemplate(BookTemplate t) {
    Haptics.selection();
    setState(() {
      _pickedTemplate = t.key;
      _icon = t.emoji;
      // 用户没自己敲过名字时跟着模板走
      if (_nameCtrl.text.trim().isEmpty ||
          kBookTemplates.any((k) => k.name == _nameCtrl.text.trim())) {
        _nameCtrl.text = t.name;
      }
    });
  }

  Future<void> _submit() async {
    final repo = context.read<AppRepository>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Haptics.of(Haptic.success);
    if (_isEdit) {
      await repo.updateBook(
        widget.edit!.id,
        name: name,
        icon: _icon,
        includeInTotal: _includeInTotal,
      );
    } else {
      final id = await repo.addBook(
        name: name,
        icon: _icon,
        includeInTotal: _includeInTotal,
      );
      await repo.switchBook(id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                _isEdit ? '编辑账本' : '新建账本',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            if (!_isEdit) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '选一个常用账本，或直接起名自定义',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
              // ── 封面横滑（对齐 Claude 选图交互；封面图就位后换 Image.asset）──
              SizedBox(
                height: 118,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in kBookTemplates) ...[
                      _CoverCard(
                        template: t,
                        selected: _pickedTemplate == t.key,
                        onTap: () => _pickTemplate(t),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // ── 名称 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(_icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      // 编辑就是来改名的，直接聚焦弹键盘；新建先让用户看模板。
                      autofocus: _isEdit,
                      maxLength: 12,
                      decoration: iosInputDecoration(hint: '账本名称'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // ── 计入总账本 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('账单计入总账本',
                            style: TextStyle(fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '开启后，这本账的账单也会出现在总账本里一起统计',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _includeInTotal,
                    onChanged: (v) => setState(() => _includeInTotal = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ── 创建 / 保存 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: PressableScale(
                  onPressed: _nameCtrl.text.trim().isEmpty ? null : _submit,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _nameCtrl.text.trim().isEmpty
                          ? scheme.onSurface.withValues(alpha: 0.3)
                          : scheme.onSurface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _isEdit ? '保存' : '创建账本',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.surface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面卡：3:4 竖卡，emoji 占位（将来换成品封面 PNG）。
class _CoverCard extends StatelessWidget {
  final BookTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _CoverCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      haptic: null, // _pickTemplate 里已振动
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 86,
        decoration: BoxDecoration(
          color: template.tint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.05),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(template.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(
              template.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
