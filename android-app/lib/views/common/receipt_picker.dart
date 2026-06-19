import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_sheet.dart';

/// 弹「拍照 / 从相册选」选择，选一张收据图片 → 复制到 App 文档目录 →
/// 返回持久化后的本地路径。用户取消返回 null。
Future<String?> pickAndSaveReceipt(BuildContext context) async {
  final source = await appSheet<ImageSource>(
    context,
    isScrollControlled: false,
    child: const _SourceSheet(),
  );
  if (source == null) return null;

  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(
    source: source,
    imageQuality: 80,
    maxWidth: 2200,
  );
  if (picked == null) return null;

  // 复制到 App 文档目录下的 receipts/，避免临时文件被系统清掉。
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/receipts');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
  final dest = '${dir.path}/r_${DateTime.now().millisecondsSinceEpoch}.$ext';
  await File(picked.path).copy(dest);
  return dest;
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 收据缩略图：点开全屏查看；右上角 × 删除。
class ReceiptThumb extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  final double size;

  const ReceiptThumb({
    super.key,
    required this.path,
    required this.onRemove,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => showReceiptViewer(context, path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.broken_image_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(Icons.close, size: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// 全屏查看收据图（可双指缩放）。
void showReceiptViewer(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: Image.file(
                File(path),
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}
