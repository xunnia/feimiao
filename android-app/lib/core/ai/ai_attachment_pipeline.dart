import 'dart:io';

import '../media/chat_attachment.dart';

class AiAttachmentCheck {
  final ChatAttachment attachment;
  final bool accepted;
  final String error;

  const AiAttachmentCheck({
    required this.attachment,
    required this.accepted,
    this.error = '',
  });
}

class AiAttachmentBatch {
  final List<ChatAttachment> accepted;
  final List<AiAttachmentCheck> checks;

  const AiAttachmentBatch({required this.accepted, required this.checks});

  List<AiAttachmentCheck> get rejected =>
      checks.where((check) => !check.accepted).toList(growable: false);
  bool get isValid => rejected.isEmpty;
}

/// Shared preflight for chat, record and retry flows.  It prevents an Android
/// cache URI or an oversized file from reaching the network layer and gives
/// the UI a deterministic reason that can be retried.
class AiAttachmentPipeline {
  AiAttachmentPipeline._();

  static const maxImages = 3;
  static const maxFiles = 10;
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxFileBytes = 50 * 1024 * 1024;

  static Future<AiAttachmentBatch> validate(
    Iterable<ChatAttachment> attachments,
  ) async {
    final list = attachments.toList(growable: false);
    var imageCount = 0;
    var fileCount = 0;
    final checks = <AiAttachmentCheck>[];
    final accepted = <ChatAttachment>[];
    for (final attachment in list) {
      final path = attachment.path.trim();
      String? error;
      if (path.isEmpty || !await File(path).exists()) {
        error = '文件已不存在，请重新选择';
      } else {
        final size = await File(path).length();
        final max = attachment.isImage ? maxImageBytes : maxFileBytes;
        if (size <= 0) {
          error = '文件为空';
        } else if (size > max) {
          error = attachment.isImage ? '图片不能超过 20 MB' : '文件不能超过 50 MB';
        } else if (attachment.isImage && imageCount >= maxImages) {
          error = '一次最多发送 3 张图片';
        } else if (!attachment.isImage && fileCount >= maxFiles) {
          error = '一次最多发送 10 个文件';
        }
      }
      final check = AiAttachmentCheck(
        attachment: attachment,
        accepted: error == null,
        error: error ?? '',
      );
      checks.add(check);
      if (check.accepted) {
        accepted.add(attachment);
        if (attachment.isImage) {
          imageCount++;
        } else {
          fileCount++;
        }
      }
    }
    return AiAttachmentBatch(
      accepted: List.unmodifiable(accepted),
      checks: List.unmodifiable(checks),
    );
  }
}
