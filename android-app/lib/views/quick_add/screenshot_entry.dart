import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'ai_quick_entry_view.dart';

/// 支付截图识别入口：相册选一张支付/账单截图 → ML Kit 中文 OCR →
/// 把识别文字喂给 [AiQuickEntryView]（复用既有的金额/分类/收支解析）。
///
/// 用 ML Kit on-device 识别（中文脚本），无需联网；解析阶段才可能走 DeepSeek。
Future<void> recognizeScreenshotAndEntry(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  // 1. 选图
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('打不开相册：$e')));
    return;
  }
  if (file == null) return; // 用户取消

  // 2. 显示识别中遮罩
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _RecognizingDialog(),
  );

  // 3. OCR
  String text = '';
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final input = InputImage.fromFilePath(file.path);
    final result = await recognizer.processImage(input);
    text = result.text;
  } catch (e) {
    text = '';
  } finally {
    await recognizer.close();
  }

  // 4. 关遮罩
  if (navigator.canPop()) navigator.pop();

  final cleaned = text.trim();
  if (cleaned.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('没识别到文字，换张更清晰的截图试试')),
    );
    return;
  }

  // 5. 把识别文字交给 AI 快记页解析
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => AiQuickEntryView(initialText: cleaned),
    ),
  );
}

class _RecognizingDialog extends StatelessWidget {
  const _RecognizingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: 16),
          Text('正在识别截图…'),
        ],
      ),
    );
  }
}
