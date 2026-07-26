import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../data/app_repository.dart';
import '../../widgets/ios_dialogs.dart';

/// AI 隐私确认：走全局确认弹窗（2026-07-09 视觉升级批统一，
/// 用户点名旧的 Material AlertDialog 丑）。
Future<bool> ensureAiPrivacyConsent(BuildContext context) async {
  final repo = context.read<AppRepository>();
  if (repo.aiPrivacyAccepted) return true;
  // 同意一次对所有路由生效，所以文案要列出所有已配置路由（记账/喵助手/报告）
  // 的服务商，不能只写记账那一路。
  final providerNames = <String>[];
  for (final task in AiTaskType.values) {
    final label = repo.aiProviderConfigFor(task).providerLabel;
    if (!providerNames.contains(label)) providerNames.add(label);
  }
  final providerName = providerNames.join('、');
  final ok = await showConfirmDialog(
    context,
    title: '使用 AI 前请确认',
    message: '使用 $providerName AI 时，肥喵会把你输入的记账文本、截图 OCR 文本、'
        '商户/商品样本，或查账问题所需的账本上下文发送给 $providerName 处理。\n\n'
        'API Key 仅用于本机发起请求；你可以随时清除 API Key 或清空对话记录。',
    confirmText: '同意并继续',
    cancelText: '暂不使用',
  );
  if (ok) {
    await repo.setAiPrivacyAccepted(true);
    return true;
  }
  return false;
}
