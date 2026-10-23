import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'transaction_books_sheet.dart';

/// 常用账本模板（对齐团团记账的预置账本，去掉共享类）。
/// [cover] 是成品封面图（用户 GPT 生成的蓝白英短猫插画）；
/// 还没出图的模板 cover 为 null，用 emoji+浅色底占位。
class BookTemplate {
  final String key;
  final String name;
  final String emoji;
  final Color tint;

  /// 封面资源路径（assets/book_covers/<key>.png），无图为 null。
  final String? cover;

  const BookTemplate(this.key, this.name, this.emoji, this.tint, {this.cover});
}

const List<BookTemplate> kBookTemplates = [
  // 「日常生活」封面给了总账本用，模板里不再重复列出。
  BookTemplate('dining', '餐饮账本', '🍜', Color(0xFFFDEBD8),
      cover: 'assets/book_covers/dining.png'),
  BookTemplate('shopping', '网购账本', '📦', Color(0xFFE8F0E4),
      cover: 'assets/book_covers/shopping.png'),
  BookTemplate('travel', '旅游账本', '🧳', Color(0xFFDDEFF7),
      cover: 'assets/book_covers/travel.png'),
  BookTemplate('beauty', '美妆账本', '💄', Color(0xFFFBE9EE),
      cover: 'assets/book_covers/beauty.png'),
  BookTemplate('business', '生意账本', '💼', Color(0xFFE4E9F2),
      cover: 'assets/book_covers/business.png'),
  BookTemplate('couple', '情侣账本', '💑', Color(0xFFF9E4EA),
      cover: 'assets/book_covers/couple.png'),
  BookTemplate('multi', '多人账本', '👥', Color(0xFFEFEBE2),
      cover: 'assets/book_covers/multi.png'),
  BookTemplate('pet', '宠物账本', '🐱', Color(0xFFF6E8DC),
      cover: 'assets/book_covers/pet.png'),
  BookTemplate('baby', '母婴账本', '🍼', Color(0xFFFBE9EE),
      cover: 'assets/book_covers/baby.png'),
  BookTemplate('family', '家庭账本', '🏠', Color(0xFFEFEBE2),
      cover: 'assets/book_covers/family.png'),
];

/// 弹「新建账本」半屏页；[edit] 传入则是编辑既有账本。
Future<void> showBookSheet(BuildContext context, {BookEntity? edit}) async {
  final result = await showBlurSheet<_BookSheetResult>(context,
      child: _BookSheet(edit: edit));
  if (result == null || !result.addExisting || !context.mounted) return;
  final book = context
      .read<AppRepository>()
      .books
      .where((b) => b.id == result.id)
      .firstOrNull;
  if (book != null) await showBookTransactionsSheet(context, book: book);
}

class _BookSheetResult {
  final int id;
  final bool addExisting;
  const _BookSheetResult(this.id, this.addExisting);
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
  late final TextEditingController _remarkCtrl =
      TextEditingController(text: widget.edit?.remark ?? '');
  late String _icon = widget.edit?.icon ?? '📒';
  late String _cover = widget.edit?.cover ?? '';
  String? _pickedTemplate;
  bool _addExisting = false;
  bool _saving = false;

  bool get _isEdit => widget.edit != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  void _pickTemplate(BookTemplate t) {
    Haptics.selection();
    setState(() {
      _pickedTemplate = t.key;
      _icon = t.emoji;
      _cover = t.cover ?? '';
      // 用户没自己敲过名字时跟着模板走
      if (_nameCtrl.text.trim().isEmpty ||
          kBookTemplates.any((k) => k.name == _nameCtrl.text.trim())) {
        _nameCtrl.text = t.name;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final repo = context.read<AppRepository>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final remark = _remarkCtrl.text.trim();
    setState(() => _saving = true);
    try {
      final int id;
      if (_isEdit) {
        id = widget.edit!.id;
        await repo.updateBook(id,
            name: name, icon: _icon, cover: _cover, remark: remark);
      } else {
        id = await repo.addBook(
            name: name, icon: _icon, cover: _cover, remark: remark);
        await repo.switchBook(id);
      }
      Haptics.of(Haptic.success);
      if (mounted) Navigator.pop(context, _BookSheetResult(id, _addExisting));
    } catch (error) {
      if (mounted) {
        showAppToast(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final isSceneBook = widget.edit?.id != repo.defaultBookId;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;

    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  .88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 统一弹层头：✕ 关闭 + 居中标题 + 右上角「创建/保存」。
              SheetHeader(
                title: largeText
                    ? (_isEdit ? '编辑' : '新建')
                    : (_isEdit ? '编辑账本' : '新建账本'),
                subtitle: _isEdit ? null : '选一个常用账本，或直接起名自定义',
                onClose: _saving ? null : () => Navigator.pop(context),
                actionLabel: _isEdit ? '保存' : '创建',
                onAction:
                    _saving || _nameCtrl.text.trim().isEmpty ? null : _submit,
              ),
              Flexible(
                  child: SingleChildScrollView(
                      child: AbsorbPointer(
                absorbing: _saving,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (!_isEdit) ...[
                    const SizedBox(height: 12),
                    // ── 封面横滑（对齐 Claude 选图交互）──
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
                        SizedBox(
                          width: 34,
                          child: Center(
                            child: Text(_icon,
                                style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            // 先展示归集入口，避免自动键盘遮住已有账单管理。
                            autofocus: false,
                            maxLength: 12,
                            decoration:
                                iosInputDecoration(context, hint: '账本名称'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── 备注（显示在抽屉账本名下方）──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '备注',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _remarkCtrl,
                            maxLength: 20,
                            decoration:
                                iosInputDecoration(context, hint: '可选，如"日常开销"'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 总账本是全量视图；场景账本仅为归集，不再提供排除开关。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            widget.edit?.includeInTotal == false
                                ? '总账本现包含全部账单，原先排除的账本也会计入'
                                : '总账本自动包含全部账单，同一笔账可以同时归入多个场景账本。',
                            style: AppType.secondary(scheme))),
                  ),
                  if (isSceneBook)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SettingsGroup(children: [
                          if (!_isEdit)
                            SettingsRow(
                                title: '创建后添加已有账单',
                                subtitle: '从历史收支中选择，不复制账单',
                                trailing: AppSwitch(
                                    value: _addExisting,
                                    semanticLabel: '创建后添加已有账单',
                                    onChanged: (value) =>
                                        setState(() => _addExisting = value))),
                          if (_isEdit) ...[
                            SettingsRow(
                                title: '添加已有账单',
                                leading: const AppLineIcon(AppLineIcons.book,
                                    size: 20),
                                subtitle: '从总账本选择，可搜索和批量添加',
                                onTap: () => showBookTransactionsSheet(context,
                                    book: widget.edit!)),
                            SettingsRow(
                                title: '管理已关联账单',
                                leading: const AppLineIcon(AppLineIcons.pencil,
                                    size: 20),
                                subtitle: '移出当前账本，原始账单仍保留',
                                onTap: () => showBookTransactionsSheet(context,
                                    book: widget.edit!, removeOnly: true)),
                          ],
                        ])),
                  const SizedBox(height: 18),
                ]),
              ))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面卡：3:4 竖卡。有成品封面图用图（名字压在底部渐变上），
/// 还没出图的模板用 emoji+浅色底占位。
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
    final cover = template.cover;
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
            color: selected
                ? scheme.primary.withValues(alpha: 0.42)
                : AppColors.hairline(scheme, strength: 0.8),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: cover != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    cover,
                    fit: BoxFit.cover,
                    // 图加载失败兜底回 emoji 占位，不崩不空白。
                    errorBuilder: (_, __, ___) => _placeholder(scheme),
                  ),
                  // 底部渐变压字，保证名字在任何封面上都可读。
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x8A000000)],
                        ),
                      ),
                      child: Text(
                        template.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CornerSelectionPainter(
                          color: scheme.primary,
                          radius: 16,
                        ),
                      ),
                    ),
                ],
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Column(
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
    );
  }
}

class _CornerSelectionPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _CornerSelectionPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const inset = 4.0;
    const len = 17.0;

    void drawCorner(double x, double y, int sx, int sy) {
      canvas.drawLine(
        Offset(x, y + sy * radius),
        Offset(x, y + sy * len),
        paint,
      );
      canvas.drawLine(
        Offset(x + sx * radius, y),
        Offset(x + sx * len, y),
        paint,
      );
    }

    drawCorner(inset, inset, 1, 1);
    drawCorner(size.width - inset, inset, -1, 1);
    drawCorner(inset, size.height - inset, 1, -1);
    drawCorner(size.width - inset, size.height - inset, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CornerSelectionPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
