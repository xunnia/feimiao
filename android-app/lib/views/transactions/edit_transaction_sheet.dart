import 'package:flutter/material.dart';

import '../../data/app_repository.dart';
import '../home/manual_add_sheet.dart';

/// 打开编辑大卡：全部走手动记账同一套界面（含转账编辑模式）。
/// 旧的独立编辑卡 `EditTransactionSheet` 已在 2026-09-29 删除。
Future<void> showEditTransactionSheet(
    BuildContext context, TransactionEntity transaction) {
  return showManualAddSheet(context, edit: transaction);
}
