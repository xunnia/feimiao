import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ChatAttachmentKind { image, file }

/// A durable attachment owned by one chat message.
///
/// Pickers often return cache paths that Android may delete at any time. Every
/// attachment is copied into the app documents directory before it is shown in
/// the composer, so draft preview, retry and restored history all address the
/// same bytes.
class ChatAttachment {
  final ChatAttachmentKind kind;
  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  const ChatAttachment({
    required this.kind,
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  bool get isImage => kind == ChatAttachmentKind.image;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'path': path,
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };

  factory ChatAttachment.fromJson(Map<String, Object?> json) {
    final rawKind = json['kind']?.toString();
    return ChatAttachment(
      kind: rawKind == ChatAttachmentKind.image.name
          ? ChatAttachmentKind.image
          : ChatAttachmentKind.file,
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  static String encodeList(Iterable<ChatAttachment> attachments) =>
      jsonEncode(attachments.map((item) => item.toJson()).toList());

  static List<ChatAttachment> decodeList(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return List.unmodifiable(
        decoded
            .whereType<Map>()
            .map((item) => ChatAttachment.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .where((item) => item.path.trim().isNotEmpty),
      );
    } catch (_) {
      return const [];
    }
  }
}

abstract final class ChatAttachmentStore {
  static int _sequence = 0;

  static Future<ChatAttachment> persist(
    String sourcePath, {
    String? displayName,
    ChatAttachmentKind? kind,
  }) async {
    final source = File(sourcePath.trim());
    if (!await source.exists()) {
      throw const FileSystemException('附件文件不存在');
    }
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(docs.path, 'chat_attachments'));
    if (!await directory.exists()) await directory.create(recursive: true);

    final originalName = (displayName?.trim().isNotEmpty == true
            ? displayName!.trim()
            : p.basename(source.path))
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final extension = p.extension(originalName).toLowerCase();
    final resolvedMime = _mimeFor(extension);
    final resolvedKind = kind ??
        (resolvedMime.startsWith('image/')
            ? ChatAttachmentKind.image
            : ChatAttachmentKind.file);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    final destination = File(p.join(directory.path, '$id$extension'));
    await source.copy(destination.path);
    final size = await destination.length();
    return ChatAttachment(
      kind: resolvedKind,
      path: destination.path,
      name: originalName.isEmpty ? '附件$extension' : originalName,
      mimeType: resolvedMime,
      sizeBytes: size,
    );
  }

  /// 清理 `chat_attachments/` 与 `.ai_prepared_v1/` 里不再被任何聊天消息引用的孤儿文件。
  /// [referencedPaths] 应包含数据库里仍存活消息引用的路径，以及当前草稿里的路径；
  /// 只清理修改时间早于 [minAge] 的文件，避免误删刚刚选进草稿、还没来得及落库的附件。
  static Future<int> pruneOrphanFiles({
    required Set<String> referencedPaths,
    Directory? attachmentsDirectory,
    Duration minAge = const Duration(minutes: 5),
    DateTime? now,
  }) async {
    try {
      final dir = attachmentsDirectory ??
          Directory(
            p.join((await getApplicationDocumentsDirectory()).path,
                'chat_attachments'),
          );
      if (!await dir.exists()) return 0;
      final normalizedRefs = referencedPaths
          .map((path) => p.normalize(path.trim()))
          .where((path) => path.isNotEmpty)
          .toSet();
      final cutoff = (now ?? DateTime.now()).subtract(minAge);
      var deleted = 0;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final normalized = p.normalize(entity.path);
        if (normalizedRefs.contains(normalized)) continue;
        try {
          final modified = await entity.lastModified();
          if (modified.isAfter(cutoff)) continue;
          await entity.delete();
          deleted++;
        } catch (_) {}
      }

      // 同步清理已无引用的 .ai_prepared_v1 压缩缓存（当没有任何存活附件或缓存过期时清空）。
      final preparedDir = Directory(p.join(dir.path, '.ai_prepared_v1'));
      if (await preparedDir.exists()) {
        final hasLiveAttachment =
            await dir.list(followLinks: false).any((entity) => entity is File);
        final cacheCutoff =
            (now ?? DateTime.now()).subtract(const Duration(days: 7));
        await for (final entity in preparedDir.list(followLinks: false)) {
          if (entity is! File) continue;
          try {
            final modified = await entity.lastModified();
            if (!hasLiveAttachment || modified.isBefore(cacheCutoff)) {
              await entity.delete();
              deleted++;
            }
          } catch (_) {}
        }
      }
      return deleted;
    } catch (_) {
      return 0;
    }
  }

  /// 删除草稿中移出的单个持久化附件文件（仅限 chat_attachments 目录内，防止误删用户原图）。
  static Future<void> deletePersistedDraftFile(
    String rawPath, {
    Directory? attachmentsDirectory,
  }) async {
    final path = rawPath.trim();
    if (path.isEmpty) return;
    try {
      final dir = attachmentsDirectory ??
          Directory(
            p.join((await getApplicationDocumentsDirectory()).path,
                'chat_attachments'),
          );
      final normalizedDir = p.normalize(dir.path);
      final normalizedFile = p.normalize(path);
      if (!p.isWithin(normalizedDir, normalizedFile)) return;
      final file = File(normalizedFile);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _mimeFor(String extension) => switch (extension) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        '.heic' || '.heif' => 'image/heic',
        '.pdf' => 'application/pdf',
        '.txt' => 'text/plain',
        '.md' => 'text/markdown',
        '.csv' => 'text/csv',
        '.json' => 'application/json',
        '.doc' => 'application/msword',
        '.docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.xls' => 'application/vnd.ms-excel',
        '.xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        _ => 'application/octet-stream',
      };
}
