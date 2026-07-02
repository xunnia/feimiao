import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/ai/order_list_parser.dart';
import '../../core/ai/screenshot_layout.dart';
import '../../widgets/app_toast.dart';
import 'ai_quick_entry_view.dart';

/// 支付截图识别入口：相册选一张支付/账单截图 → ML Kit 中文 OCR →
/// 把识别文字喂给 [AiQuickEntryView]（复用既有的金额/分类/收支解析）。
///
/// 用 ML Kit on-device 识别（中文脚本），无需联网；解析阶段才可能走 DeepSeek。
Future<void> recognizeScreenshotAndEntry(BuildContext context) async {
  // 1. 选图
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
  } catch (e) {
    if (context.mounted) {
      showAppToast(context, '打不开相册：$e', icon: Icons.error_outline);
    }
    return;
  }
  if (file == null) return; // 用户取消
  if (!context.mounted) return;
  await recognizeImagePathAndEntry(context, file.path);
}

/// 给定图片路径直接识别记账：相册选图与「分享到肥喵」共用这条管线。
Future<void> recognizeImagePathAndEntry(
    BuildContext context, String imagePath) async {
  final navigator = Navigator.of(context);

  // 2. 显示识别中遮罩
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _RecognizingDialog(),
  );

  // 3. OCR（同时保留每行坐标，供订单列表分块用）
  String text = '';
  String? ocrError; // 记下真实报错，便于诊断（之前被静默吞掉）
  final ocrLines = <OcrLine>[];
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final input = InputImage.fromFilePath(imagePath);
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
    ocrError = '$e';
  } finally {
    await recognizer.close();
  }

  // 4. 关遮罩
  if (navigator.canPop()) navigator.pop();

  // 判定是否「订单列表」：≥2 个订单锚点，或 ≥3 个不同金额。
  // 注意：部分截图 OCR 抓不到 ¥ 符号（金额是裸的 17.70），所以锚点要带「共N件」、
  // 金额也按"两位小数"识别，不能只认 ¥。
  final anchorRe = RegExp(
      r'自动确认收货并付款|确认收货|待收货|待评价|实付款|付款金额|共\s*\d+\s*件|再次购买|已完成');
  final anchorCount = ocrLines.where((l) => anchorRe.hasMatch(l.text)).length;
  final amounts = <String>{};
  final amtRe = RegExp(r'(?:[¥￥]\s*)?(\d{1,6}\.\d{2})');
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
    // 按「共N件」确定性切单(并丢弃已取消/退款单);无锚点时回退纵向聚类。
    final blocks = OrderListParser.segment(ocrLines);
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
    if (context.mounted) {
      showAppToast(
        context,
        ocrError != null ? '识别失败：$ocrError' : '没识别到文字，换张更清晰的截图试试',
        icon: Icons.error_outline,
      );
    }
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
