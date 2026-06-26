import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/ai/screenshot_layout.dart';
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

  // 3. OCR（同时保留每行坐标，供订单列表分块用）
  String text = '';
  final ocrLines = <OcrLine>[];
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final input = InputImage.fromFilePath(file.path);
    final result = await recognizer.processImage(input);
    text = result.text;
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final r = line.boundingBox;
        ocrLines.add(OcrLine(
          text: line.text,
          top: r.top.toDouble(),
          bottom: r.bottom.toDouble(),
          left: r.left.toDouble(),
        ));
      }
    }
  } catch (e) {
    text = '';
  } finally {
    await recognizer.close();
  }

  // 4. 关遮罩
  if (navigator.canPop()) navigator.pop();

  // 判定是否「订单列表」：出现 ≥2 个付款锚点（每单一个），或 ≥3 个不同的正金额。
  final anchorRe = RegExp(r'自动确认收货并付款|确认收货|待收货|待评价|实付款|付款金额');
  final anchorCount = ocrLines.where((l) => anchorRe.hasMatch(l.text)).length;
  final amounts = <String>{};
  final amtRe = RegExp(r'[¥￥]\s*(\d+(?:\.\d+)?)');
  for (final l in ocrLines) {
    for (final m in amtRe.allMatches(l.text)) {
      final v = double.tryParse(m.group(1) ?? '') ?? 0;
      if (v > 0) amounts.add(m.group(1)!);
    }
  }
  final isOrderList = anchorCount >= 2 || amounts.length >= 3;

  // 订单列表：用坐标把文字聚成订单块，块间用分隔线隔开（每块各自清噪），
  // 让大模型逐块各记一笔、金额只跟同块商品配对，从根上消除「整体偏移一位」。
  // 其它（单笔支付页）：沿用已验证的 flat 清噪路径，不受影响。
  String cleaned;
  if (isOrderList && ocrLines.isNotEmpty) {
    final blocks = ScreenshotLayout.clusterBlocks(ocrLines);
    final rendered = ScreenshotLayout.renderBlocks(
      blocks,
      cleaner: (s) => PaymentScreenshotParser.cleanOcr(s),
    ).trim();
    cleaned = rendered.isNotEmpty
        ? rendered
        : PaymentScreenshotParser.cleanOcr(text).trim();
  } else {
    cleaned = PaymentScreenshotParser.cleanOcr(text).trim();
  }
  if (cleaned.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('没识别到文字，换张更清晰的截图试试')),
    );
    return;
  }

  // 5. 把识别文字交给 AI 快记页解析
  navigator.push(
    CupertinoPageRoute<void>(
      builder: (_) => AiQuickEntryView(
        initialText: cleaned,
        fromScreenshot: true,
      ),
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
