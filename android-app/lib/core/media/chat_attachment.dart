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
