import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/ai_attachment_pipeline.dart';
import '../../core/haptics.dart';
import '../../core/media/recent_photos.dart';
import '../../core/media/chat_attachment.dart';
import '../../core/ai/chat_session.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

/// The attachment/tools sheet used by the full-screen Chats experience.
///
/// This deliberately has its own surface instead of reusing
/// [showRecordExtrasSheet]. The home record launcher still owns the old
/// screenshot/import/export actions; Chats only exposes chat actions here.
Future<void> showChatAddSheet(
  BuildContext context, {
  required Future<void> Function(List<ChatAttachment> attachments)
      onAttachmentsPicked,
  required bool webSearchEnabled,
  required Future<void> Function(bool enabled) onWebSearchChanged,
  AiChatToolAccess toolAccess = AiChatToolAccess.auto,
  Future<void> Function(AiChatToolAccess access)? onToolAccessChanged,
  Future<List<ChatRecentPhoto>>? recentPhotos,
}) {
  return showBlurSheet<void>(
    context,
    inset: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    radius: 30,
    blurBackground: false,
    barrierOpacity: 0.16,
    child: _ChatAddSheet(
      onAttachmentsPicked: onAttachmentsPicked,
      webSearchEnabled: webSearchEnabled,
      onWebSearchChanged: onWebSearchChanged,
      toolAccess: toolAccess,
      onToolAccessChanged: onToolAccessChanged ?? (_) async {},
      recentPhotos: recentPhotos,
    ),
  );
}

/// Production widget exposed to focused visual tests without opening a route.
@visibleForTesting
Widget buildClaudeChatAddSheetForTesting({
  required Future<void> Function(List<ChatAttachment> attachments)
      onAttachmentsPicked,
  bool webSearchEnabled = true,
  Future<void> Function(bool enabled)? onWebSearchChanged,
  AiChatToolAccess toolAccess = AiChatToolAccess.auto,
  Future<void> Function(AiChatToolAccess access)? onToolAccessChanged,
  Future<List<ChatRecentPhoto>>? recentPhotos,
}) =>
    _ChatAddSheet(
      onAttachmentsPicked: onAttachmentsPicked,
      webSearchEnabled: webSearchEnabled,
      onWebSearchChanged: onWebSearchChanged ?? (_) async {},
      toolAccess: toolAccess,
      onToolAccessChanged: onToolAccessChanged ?? (_) async {},
      recentPhotos: recentPhotos,
    );

class _ChatAddSheet extends StatefulWidget {
  final Future<void> Function(List<ChatAttachment> attachments)
      onAttachmentsPicked;
  final bool webSearchEnabled;
  final Future<void> Function(bool enabled) onWebSearchChanged;
  final AiChatToolAccess toolAccess;
  final Future<void> Function(AiChatToolAccess access) onToolAccessChanged;
  final Future<List<ChatRecentPhoto>>? recentPhotos;

  const _ChatAddSheet({
    required this.onAttachmentsPicked,
    required this.webSearchEnabled,
    required this.onWebSearchChanged,
    required this.toolAccess,
    required this.onToolAccessChanged,
    this.recentPhotos,
  });

  @override
  State<_ChatAddSheet> createState() => _ChatAddSheetState();
}

class _ChatAddSheetState extends State<_ChatAddSheet> {
  late bool _webSearchEnabled;
  late AiChatToolAccess _toolAccess;
  bool _picking = false;
  final Set<String> _selectedRecentIds = <String>{};
  late final Future<List<ChatRecentPhoto>> _recentPhotos;

  @override
  void initState() {
    super.initState();
    _webSearchEnabled = widget.webSearchEnabled;
    _toolAccess = widget.toolAccess;
    _recentPhotos = widget.recentPhotos ?? RecentPhotoStore.load();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = source == ImageSource.gallery
          ? await ImagePicker().pickMultiImage(imageQuality: 92)
          : <XFile>[
              if (await ImagePicker().pickImage(
                source: source,
                imageQuality: 92,
              )
                  case final XFile file)
                file,
            ];
      if (files.isNotEmpty) {
        final selectedFiles = files.length > AiAttachmentPipeline.maxImages
            ? files.take(AiAttachmentPipeline.maxImages).toList(growable: false)
            : files;
        if (files.length > selectedFiles.length && mounted) {
          showAppToast(context, '一次最多添加 3 张图片，已保留前 3 张');
        }
        await _deliverAttachments([
          for (final file in selectedFiles)
            await ChatAttachmentStore.persist(
              file.path,
              displayName: file.name,
              kind: ChatAttachmentKind.image,
            ),
        ]);
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, '打不开图片选择器：$error', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      final files = result?.files ?? const <PlatformFile>[];
      final attachments = <ChatAttachment>[];
      for (final file in files) {
        final path = file.path?.trim() ?? '';
        if (path.isEmpty) continue;
        attachments.add(await ChatAttachmentStore.persist(
          path,
          displayName: file.name,
        ));
      }
      if (attachments.isNotEmpty) await _deliverAttachments(attachments);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '打不开文件选择器：$error', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _deliverAttachments(List<ChatAttachment> attachments) async {
    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onAttachmentsPicked(attachments);
  }

  void _toggleRecentPhoto(ChatRecentPhoto photo) {
    if (_picking) return;
    final id = photo.id.trim();
    if (id.isEmpty) return;
    setState(() {
      if (_selectedRecentIds.contains(id)) {
        _selectedRecentIds.remove(id);
      } else if (_selectedRecentIds.length < 3) {
        _selectedRecentIds.add(id);
      } else {
        return;
      }
    });
    Haptics.selection();
  }

  Future<void> _addSelectedRecentPhotos() async {
    if (_picking || _selectedRecentIds.isEmpty) return;
    setState(() => _picking = true);
    try {
      final photos = await _recentPhotos;
      final selected = photos
          .where((photo) => _selectedRecentIds.contains(photo.id))
          .toList(growable: false);
      final attachments = <ChatAttachment>[];
      for (final photo in selected) {
        final path = await photo.loadPath();
        if (path == null || path.trim().isEmpty) {
          continue;
        }
        attachments.add(
          await ChatAttachmentStore.persist(
            path,
            displayName: '照片_${photo.id}.jpg',
            kind: ChatAttachmentKind.image,
          ),
        );
      }
      if (attachments.isEmpty) {
        if (mounted) {
          showAppToast(
            context,
            '所选图片暂时无法读取，请从相册重新选择',
            icon: Icons.error_outline,
          );
        }
        return;
      }
      await _deliverAttachments(attachments);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '读取图片失败：$error', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _showToolAccess() async {
    final selected = await showBlurSheet<AiChatToolAccess>(
      context,
      blurBackground: false,
      barrierOpacity: 0.10,
      child: _ToolAccessSheet(selected: _toolAccess),
    );
    if (!mounted || selected == null || selected == _toolAccess) return;
    setState(() => _toolAccess = selected);
    await widget.onToolAccessChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Container(
          key: const ValueKey('chat-add-sheet-surface'),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                _ChatAddHeader(
                  onClose: () => Navigator.of(context).pop(),
                  onAllPhotos: () => _pickImage(ImageSource.gallery),
                ),
                const SizedBox(height: 8),
                _PhotoStrip(
                  busy: _picking,
                  recentPhotos: _recentPhotos,
                  onCamera: () => _pickImage(ImageSource.camera),
                  onGallery: () => _pickImage(ImageSource.gallery),
                  selectedIds: _selectedRecentIds,
                  onRecentPhoto: _toggleRecentPhoto,
                ),
                if (_selectedRecentIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SelectedPhotosButton(
                    count: _selectedRecentIds.length,
                    busy: _picking,
                    onTap: _addSelectedRecentPhotos,
                  ),
                ],
                const SizedBox(height: 14),
                _ChatActionCard(
                  children: [
                    _ChatActionRow(
                      key: const ValueKey('chat-add-files-row'),
                      icon: CupertinoIcons.doc,
                      title: '添加文件',
                      onTap: _pickFile,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ChatActionCard(
                  children: [
                    _ChatActionRow(
                      key: const ValueKey('chat-tool-access-row'),
                      icon: CupertinoIcons.briefcase,
                      title: '工具权限',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _toolAccess.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(CupertinoIcons.chevron_right,
                              size: 18, color: scheme.onSurfaceVariant),
                        ],
                      ),
                      onTap: _showToolAccess,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ChatActionCard(
                  children: [
                    _ChatActionRow(
                      key: const ValueKey('chat-web-search-row'),
                      icon: CupertinoIcons.globe,
                      title: '联网搜索',
                      trailing: AppSwitch(
                        key: const ValueKey('chat-web-search-switch'),
                        value: _webSearchEnabled,
                        semanticLabel: '联网搜索',
                        onChanged: (value) async {
                          setState(() => _webSearchEnabled = value);
                          await widget.onWebSearchChanged(value);
                        },
                      ),
                      onTap: () async {
                        final next = !_webSearchEnabled;
                        setState(() => _webSearchEnabled = next);
                        await widget.onWebSearchChanged(next);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The reference uses a compact 94dp attachment rail: one camera tile followed
// by square recent-photo thumbnails. Keeping this as a single constant makes
// the fallback and the real gallery path use exactly the same proportions.
const double _chatAddPhotoTileSize = 94;
const double _chatAddPhotoGap = 8;

class _SelectedPhotosButton extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onTap;

  const _SelectedPhotosButton({
    required this.count,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: busy ? null : onTap,
      child: Container(
        key: const ValueKey('chat-add-selected-photos'),
        width: double.infinity,
        height: 42,
        decoration: BoxDecoration(
          color: scheme.onSurface,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                busy ? '上传中…' : '添加 $count 张照片',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolAccessSheet extends StatelessWidget {
  final AiChatToolAccess selected;

  const _ToolAccessSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text('工具权限',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurface)),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: AppCircleButton(
                        icon: CupertinoIcons.chevron_back,
                        size: 36,
                        iconSize: 19,
                        onPressed: () => Navigator.of(context).pop(),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ChatActionCard(
              children: [
                _ToolAccessOption(
                  value: AiChatToolAccess.auto,
                  selected: selected == AiChatToolAccess.auto,
                  title: '自动',
                  subtitle: '根据问题智能选择需要的工具',
                ),
                _ToolAccessOption(
                  value: AiChatToolAccess.onDemand,
                  selected: selected == AiChatToolAccess.onDemand,
                  title: '按需加载',
                  subtitle: '只有明确需要时才加载工具',
                ),
                _ToolAccessOption(
                  value: AiChatToolAccess.alwaysAvailable,
                  selected: selected == AiChatToolAccess.alwaysAvailable,
                  title: '始终可用',
                  subtitle: '每次对话都允许使用全部工具',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '肥喵可用工具',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            const _ToolInfoRow(
              icon: CupertinoIcons.book,
              title: '账本查询与统计',
              subtitle: '按日期、分类、金额查询账单并生成分析',
            ),
            const _ToolInfoRow(
              icon: CupertinoIcons.pencil,
              title: '记账与分类',
              subtitle: '创建和归类账目，低置信度结果先请求确认',
            ),
            const _ToolInfoRow(
              icon: CupertinoIcons.photo,
              title: '图片识别',
              subtitle: '从相机、相册或近期图片识别账单内容',
            ),
            const _ToolInfoRow(
              icon: CupertinoIcons.globe,
              title: '联网搜索',
              subtitle: '在上一级开关打开后查询公开网页并附来源',
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolAccessOption extends StatelessWidget {
  final AiChatToolAccess value;
  final bool selected;
  final String title;
  final String subtitle;

  const _ToolAccessOption({
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: () => Navigator.of(context).pop(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.34),
                  width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark, size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _ToolInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ToolInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        color: scheme.onSurface)),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAddHeader extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onAllPhotos;

  const _ChatAddHeader({required this.onClose, required this.onAllPhotos});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '添加到聊天',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppCircleButton(
              icon: CupertinoIcons.xmark,
              iconSize: 19,
              size: 38,
              onPressed: onClose,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppPillButton(
              key: const ValueKey('chat-add-all-photos'),
              label: '全部照片',
              onPressed: onAllPhotos,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final bool busy;
  final Future<List<ChatRecentPhoto>> recentPhotos;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final Set<String> selectedIds;
  final ValueChanged<ChatRecentPhoto> onRecentPhoto;

  const _PhotoStrip({
    required this.busy,
    required this.recentPhotos,
    required this.onCamera,
    required this.onGallery,
    required this.selectedIds,
    required this.onRecentPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<ChatRecentPhoto>>(
      future: recentPhotos,
      builder: (context, snapshot) {
        // Do not flash a large Photos card while the permission/gallery
        // request is in flight. Claude keeps the camera card in place and
        // reserves the rest of the rail for the recent thumbnails.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: _chatAddPhotoTileSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: _chatAddPhotoGap),
              itemBuilder: (_, index) => index == 0
                  ? _PhotoTile(
                      icon: CupertinoIcons.camera,
                      label: '相机',
                      onTap: busy ? null : onCamera,
                    )
                  : const _PhotoLoadingTile(),
            ),
          );
        }
        final photos = snapshot.data ?? const <ChatRecentPhoto>[];
        if (photos.isEmpty) {
          return SizedBox(
            height: _chatAddPhotoTileSize,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PhotoTile(
                  icon: CupertinoIcons.camera,
                  label: '相机',
                  onTap: busy ? null : onCamera,
                ),
                const SizedBox(width: _chatAddPhotoGap),
                _PhotoTile(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: '照片',
                  onTap: busy ? null : onGallery,
                  background:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.48),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          height: _chatAddPhotoTileSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length + 1,
            separatorBuilder: (_, __) =>
                const SizedBox(width: _chatAddPhotoGap),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _PhotoTile(
                  icon: CupertinoIcons.camera,
                  label: '相机',
                  onTap: busy ? null : onCamera,
                );
              }
              final photo = photos[index - 1];
              final selectionIndex =
                  selectedIds.toList(growable: false).indexOf(photo.id);
              return _RecentPhotoTile(
                key: ValueKey('chat-recent-photo-${index - 1}'),
                photo: photo,
                busy: busy,
                selected: selectionIndex >= 0,
                selectionNumber: selectionIndex < 0 ? null : selectionIndex + 1,
                onTap: onRecentPhoto,
              );
            },
          ),
        );
      },
    );
  }
}

class _RecentPhotoTile extends StatelessWidget {
  final ChatRecentPhoto photo;
  final bool busy;
  final bool selected;
  final int? selectionNumber;
  final ValueChanged<ChatRecentPhoto> onTap;

  const _RecentPhotoTile({
    super.key,
    required this.photo,
    required this.busy,
    required this.selected,
    required this.selectionNumber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: busy ? null : () => onTap(photo),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              photo.thumbnail,
              width: _chatAddPhotoTileSize,
              height: _chatAddPhotoTileSize,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const SizedBox(
                  width: _chatAddPhotoTileSize,
                  height: _chatAddPhotoTileSize,
                ),
              ),
            ),
          ),
          Positioned(
            top: 7,
            right: 7,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white.withValues(alpha: 0.86),
                  width: 1.4,
                ),
              ),
              child: Center(
                child: selected
                    ? Text(
                        '${selectionNumber ?? ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? background;

  const _PhotoTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: Container(
        width: _chatAddPhotoTileSize,
        height: _chatAddPhotoTileSize,
        decoration: BoxDecoration(
          color: background ?? scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 25, color: scheme.onSurface),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w300,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoLoadingTile extends StatelessWidget {
  const _PhotoLoadingTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _chatAddPhotoTileSize,
      height: _chatAddPhotoTileSize,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _ChatActionCard extends StatelessWidget {
  final List<Widget> children;

  const _ChatActionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ChatActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ChatActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              Icon(icon, size: 23, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
