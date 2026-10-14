import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/media/chat_attachment.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

Future<void> showChatAttachmentPreview(
        BuildContext context, ChatAttachment attachment) =>
    showBlurSheet<void>(context,
        blurBackground: false,
        child: ChatAttachmentPreview(attachment: attachment));

class ChatAttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const ChatAttachmentPreview({super.key, required this.attachment});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        key: const ValueKey('ai-chat-attachment-preview'),
        height: MediaQuery.sizeOf(context).height * 0.85,
        color: AppColors.sheetSurface(scheme),
        child: Column(children: [
          SheetHeader(
              title: attachment.name,
              onClose: () => Navigator.of(context).pop()),
          Expanded(
              child: attachment.isImage
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                          child: Image.file(File(attachment.path),
                              fit: BoxFit.contain,
                              cacheWidth: 1600,
                              errorBuilder: (_, __, ___) => Text('图片已缺失或无法读取',
                                  style: AppType.secondary(scheme)))))
                  : Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText(
                              '${attachment.name}\n${attachment.mimeType}\n'
                              '${(attachment.sizeBytes / 1024).ceil()} KB',
                              style: AppType.body(scheme),
                              textAlign: TextAlign.center)))),
        ]));
  }
}
