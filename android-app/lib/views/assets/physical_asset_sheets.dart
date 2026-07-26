// 物品资产弹层：终局处理/状态复核/估值/凭证/折旧/出售（从 accounts_view.dart 拆出）。
import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_media_store.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';
import 'asset_media_picker.dart';

Future<void> _deleteManagedInvoiceQuietly(String filePath) async {
  final root = await getApplicationDocumentsDirectory();
  final managedRoot =
      path.normalize(path.absolute(path.join(root.path, 'asset_media')));
  final candidate = path.normalize(path.absolute(filePath));
  if (!path.isWithin(managedRoot, candidate)) return;
  try {
    await File(candidate).delete();
  } on FileSystemException {
    // The referenced file may already be gone.
  }
}

String _usageStatusLabel(PhysicalAssetUsageStatus value) => switch (value) {
      PhysicalAssetUsageStatus.active => '在用',
      PhysicalAssetUsageStatus.idle => '闲置',
      PhysicalAssetUsageStatus.unknown => '暂不确定',
    };

IconData _usageStatusIcon(PhysicalAssetUsageStatus value) => switch (value) {
      PhysicalAssetUsageStatus.active => Icons.check_circle_outline,
      PhysicalAssetUsageStatus.idle => Icons.pause_circle_outline,
      PhysicalAssetUsageStatus.unknown => Icons.help_outline,
    };

class PhysicalAssetTerminalSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  final PhysicalAssetStatus status;
  final String actionLabel;

  const PhysicalAssetTerminalSheet({
    super.key,
    required this.asset,
    required this.status,
    required this.actionLabel,
  });

  @override
  State<PhysicalAssetTerminalSheet> createState() =>
      _PhysicalAssetTerminalSheetState();
}

class _PhysicalAssetTerminalSheetState
    extends State<PhysicalAssetTerminalSheet> {
  final TextEditingController _noteController = TextEditingController();
  DateTime _endedAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '${widget.actionLabel}物品',
            subtitle: '结束持有后当前价值归零，但不会生成账户流水、普通收支或预算。',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认${widget.actionLabel}',
            onAction: _saving ? null : _save,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLabeledField(
                    label: '结束日期',
                    child: AppPickerField(
                      text: assetDateText(_endedAt),
                      hint: '选择日期',
                      onTap: (_) => _pickDate(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '说明（可选）',
                    child: TextField(
                      controller: _noteController,
                      maxLength: 80,
                      maxLines: 2,
                      style: AppType.body(scheme),
                      decoration: iosInputDecoration(
                        context,
                        hint: '例如损坏原因、赠送对象',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final purchaseDate = widget.asset.purchaseDate;
    final selected = await showAppDatePicker(
      context,
      initial: _endedAt,
      first: purchaseDate != null && !purchaseDate.isAfter(now)
          ? purchaseDate
          : null,
      last: now,
      title: '结束日期',
    );
    if (selected != null && mounted) setState(() => _endedAt = selected);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().setPhysicalAssetStatus(
            id: widget.asset.id,
            status: widget.status,
            occurredAt: _endedAt,
            note: _noteController.text.trim(),
          );
      if (!mounted) return;
      showAppToast(
        context,
        '已将「${widget.asset.name}」标记为${widget.actionLabel}',
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class PhysicalAssetReviewSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;

  const PhysicalAssetReviewSheet({super.key, required this.asset});

  @override
  State<PhysicalAssetReviewSheet> createState() =>
      _PhysicalAssetReviewSheetState();
}

class _PhysicalAssetReviewSheetState extends State<PhysicalAssetReviewSheet> {
  late PhysicalAssetUsageStatus _usageStatus;
  late bool _includeInNetWorth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usageStatus = widget.asset.usageStatus;
    _includeInNetWorth = widget.asset.includeInNetWorth;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '确认物品状态',
            subtitle: '归档仍只控制是否显示，不会改变这次确认的状态。',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: _saving ? null : _save,
          ),
          SettingsGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              SettingsRow(
                title: '使用状态',
                subtitle: '只描述当前是正在使用、闲置还是暂不确定',
                trailing: AssetMenuFilterButton<PhysicalAssetUsageStatus>(
                  value: _usageStatus,
                  values: PhysicalAssetUsageStatus.values,
                  labelOf: _usageStatusLabel,
                  iconOf: _usageStatusIcon,
                  onChanged: (value) => setState(() => _usageStatus = value),
                ),
              ),
              SettingsRow(
                title: '计入净资产',
                subtitle: '按当前估值进入人民币净资产合计',
                trailing: AppSwitch(
                  value: _includeInNetWorth,
                  onChanged: (value) =>
                      setState(() => _includeInNetWorth = value),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: Text(
              '确认只补全历史数据里缺失的信息，不会生成账单或改变当前估值。',
              style: AppType.caption(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().confirmPhysicalAssetState(
            widget.asset.id,
            usageStatus: _usageStatus,
            includeInNetWorth: _includeInNetWorth,
          );
      if (!mounted) return;
      showAppToast(context, '已确认「${widget.asset.name}」');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AssetValueSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const AssetValueSheet({super.key, required this.asset});

  @override
  State<AssetValueSheet> createState() => _AssetValueSheetState();
}

class _AssetValueSheetState extends State<AssetValueSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _valuedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.asset.currentValue.toString());
    _noteCtrl = TextEditingController();
    _valuedAt = assetToday();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = assetDecimalInputValid(_amountCtrl.text, required: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: '更新当前价值',
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          onAction: valid ? _save : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            children: [
              AppLabeledField(
                label: '当前估值',
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: moneyInputFormatters(),
                  decoration: iosInputDecoration(
                    context,
                    prefix: '¥ ',
                    hint: '例如 1800',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 14),
              AppLabeledField(
                label: '估值日期',
                helperText: '历史估值会进入时间线，不会覆盖更晚的有效估值。',
                child: AssetNullableDateField(
                  fieldKey: const Key('physical-asset-valuation-date'),
                  value: _valuedAt,
                  emptyText: '选择日期',
                  onTap: _pickValuationDate,
                ),
              ),
              const SizedBox(height: 14),
              AppLabeledField(
                label: '说明（可选）',
                child: TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '例如 二手平台参考价'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<AppRepository>().updatePhysicalAssetValue(
            widget.asset.id,
            parseAssetDecimalInput(_amountCtrl.text),
            valuedAt: _valuedAt,
            note: _noteCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickValuationDate() async {
    final selected = await showAppDatePicker(
      context,
      initial: _valuedAt,
      first: widget.asset.purchaseDate ?? DateTime(1970),
      last: assetToday(),
      title: '估值日期',
    );
    if (selected != null && mounted) setState(() => _valuedAt = selected);
  }
}

class AssetEvidenceSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const AssetEvidenceSheet({super.key, required this.asset});

  @override
  State<AssetEvidenceSheet> createState() => _AssetEvidenceSheetState();
}

class _AssetEvidenceSheetState extends State<AssetEvidenceSheet> {
  late final TextEditingController _noteCtrl;
  AssetMediaStore? _mediaStore;
  AssetMediaFiles? _pendingMedia;
  bool _removePhoto = false;
  String? _pendingInvoicePath;
  bool _removeInvoice = false;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    if (!_saved && _pendingMedia != null && _mediaStore != null) {
      unawaited(_mediaStore!.deleteFiles(_pendingMedia!));
    }
    if (!_saved && _pendingInvoicePath != null) {
      unawaited(_deleteManagedInvoiceQuietly(_pendingInvoicePath!));
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewPath = _removePhoto
        ? ''
        : _pendingMedia?.thumbnailPath ??
            (widget.asset.thumbnailPath.isNotEmpty
                ? widget.asset.thumbnailPath
                : widget.asset.photoPath);
    final invoicePath =
        _removeInvoice ? '' : _pendingInvoicePath ?? widget.asset.invoicePath;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: '资产凭证',
          subtitle: '照片会保存到 App 受管目录，并生成列表缩略图',
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          onAction: _saving ? null : _save,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            children: [
              AppLabeledField(
                label: '物品照片',
                child: Container(
                  height: 156,
                  decoration: BoxDecoration(
                    color: AppColors.inputFill(scheme),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child:
                      previewPath.isNotEmpty && File(previewPath).existsSync()
                          ? Image.file(File(previewPath), fit: BoxFit.cover)
                          : Center(
                              child: Icon(
                                Icons.image_outlined,
                                size: 36,
                                color: AppTextColor.secondary(scheme),
                              ),
                            ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: '拍照',
                    child: AppCircleButton(
                      icon: Icons.photo_camera_outlined,
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '从相册选择',
                    child: AppCircleButton(
                      icon: Icons.photo_library_outlined,
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                  if (previewPath.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '移除照片',
                      child: AppCircleButton(
                        icon: Icons.close,
                        onPressed: _clearPhoto,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AppLabeledField(
                label: '发票 / 保修单（可选）',
                child: SettingsGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    SettingsRow(
                      title: invoicePath.isEmpty
                          ? '还没有添加凭证'
                          : path.basename(invoicePath),
                      subtitle: '文件会复制到 App 受管目录',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: '选择文件',
                            child: AppCircleButton(
                              icon: Icons.attach_file,
                              size: 36,
                              iconSize: 18,
                              onPressed: _pickInvoice,
                            ),
                          ),
                          if (invoicePath.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: '移除凭证',
                              child: AppCircleButton(
                                icon: Icons.close,
                                size: 36,
                                iconSize: 18,
                                onPressed: _clearInvoice,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppLabeledField(
                label: '说明（可选）',
                child: TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '例如保修范围'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().updatePhysicalAssetEvidence(
            widget.asset.id,
            photoPath: _removePhoto
                ? ''
                : _pendingMedia?.originalPath ?? widget.asset.photoPath,
            thumbnailPath: _removePhoto
                ? ''
                : _pendingMedia?.thumbnailPath ?? widget.asset.thumbnailPath,
            invoicePath: _removeInvoice
                ? ''
                : _pendingInvoicePath ?? widget.asset.invoicePath,
            note: _noteCtrl.text,
          );
      _saved = true;
      if ((_pendingMedia != null || _removePhoto) &&
          (widget.asset.photoPath.isNotEmpty ||
              widget.asset.thumbnailPath.isNotEmpty)) {
        try {
          final store = _mediaStore ??= AssetMediaStore(
            applicationRoot: await getApplicationDocumentsDirectory(),
          );
          await store.deleteFiles(AssetMediaFiles(
              originalPath: widget.asset.photoPath,
              thumbnailPath: widget.asset.thumbnailPath));
        } on FileSystemException {
          // The new paths are already committed; orphan cleanup can retry later.
        }
      }
      if ((_removeInvoice || _pendingInvoicePath != null) &&
          widget.asset.invoicePath.isNotEmpty) {
        try {
          await _deleteManagedInvoiceQuietly(widget.asset.invoicePath);
        } on FileSystemException {
          // The database already points at the new state.
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final imported = await pickAssetPhoto(
      context,
      source,
      previous: _pendingMedia,
    );
    if (imported == null) return;
    _mediaStore ??= await sharedAssetMediaStore();
    if (mounted) {
      setState(() {
        _pendingMedia = imported;
        _removePhoto = false;
      });
    }
  }

  Future<void> _clearPhoto() async {
    if (_pendingMedia != null && _mediaStore != null) {
      await _mediaStore!.deleteFiles(_pendingMedia!);
    }
    if (mounted) {
      setState(() {
        _pendingMedia = null;
        _removePhoto = true;
      });
    }
  }

  Future<void> _pickInvoice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(root.path, 'asset_media'));
    await directory.create(recursive: true);
    final extension = path.extension(sourcePath).toLowerCase();
    final destination = path.join(
      directory.path,
      'asset_invoice_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(sourcePath).copy(destination);
    if (_pendingInvoicePath != null) {
      await _deleteManagedInvoiceQuietly(_pendingInvoicePath!);
    }
    if (mounted) {
      setState(() {
        _pendingInvoicePath = destination;
        _removeInvoice = false;
      });
    }
  }

  Future<void> _clearInvoice() async {
    if (_pendingInvoicePath != null) {
      await _deleteManagedInvoiceQuietly(_pendingInvoicePath!);
    }
    if (mounted) {
      setState(() {
        _pendingInvoicePath = null;
        _removeInvoice = true;
      });
    }
  }
}

class AssetDepreciationSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const AssetDepreciationSheet({super.key, required this.asset});

  @override
  State<AssetDepreciationSheet> createState() => _AssetDepreciationSheetState();
}

class _AssetDepreciationSheetState extends State<AssetDepreciationSheet> {
  late bool _enabled;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _salvageCtrl;
  late final TextEditingController _monthsCtrl;
  late final TextEditingController _noteCtrl;
  DateTime? _startAt;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _enabled = asset.hasLinearDepreciation;
    final defaultBase = asset.depreciationBase > Decimal.zero
        ? asset.depreciationBase
        : asset.purchasePrice > Decimal.zero
            ? asset.purchasePrice
            : asset.currentValue;
    _baseCtrl = TextEditingController(text: defaultBase.toString());
    _salvageCtrl = TextEditingController(text: asset.salvageValue.toString());
    _monthsCtrl = TextEditingController(
      text: asset.usefulLifeMonths > 0 ? asset.usefulLifeMonths.toString() : '',
    );
    _noteCtrl = TextEditingController();
    _startAt = asset.depreciationStartDate ?? asset.purchaseDate;
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _salvageCtrl.dispose();
    _monthsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _valid {
    if (!_enabled) return true;
    if (!assetDecimalInputValid(_baseCtrl.text, required: true)) return false;
    if (!assetDecimalInputValid(_salvageCtrl.text, required: true)) {
      return false;
    }
    final base = parseAssetDecimalInput(_baseCtrl.text);
    final salvage = parseAssetDecimalInput(_salvageCtrl.text);
    final months = int.tryParse(_monthsCtrl.text.trim()) ?? 0;
    return base > Decimal.zero &&
        salvage >= Decimal.zero &&
        salvage <= base &&
        months > 0 &&
        _startAt != null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: '折旧设置',
          subtitle: '手动更新当前价值会暂停自动折旧，重新保存折旧设置后恢复。',
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          onAction: _valid ? _save : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            children: [
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    title: '线性折旧',
                    subtitle: '按完整月份把价值降到残值，不写入普通收支',
                    trailing: AppSwitch(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  ),
                ],
              ),
              if (_enabled) ...[
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '折旧基准金额',
                  child: TextField(
                    controller: _baseCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(context, prefix: '¥ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '预计残值',
                  child: TextField(
                    controller: _salvageCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters(),
                    decoration: iosInputDecoration(context, prefix: '¥ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '使用寿命（月）',
                  child: TextField(
                    controller: _monthsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: iosInputDecoration(context, hint: '例如 36'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledField(
                  label: '折旧开始日期',
                  helperText: _startAt == null ? '购买日期未知，请明确选择折旧从哪一天开始。' : null,
                  child: AssetNullableDateField(
                    fieldKey:
                        const Key('physical-asset-depreciation-start-date'),
                    value: _startAt,
                    emptyText: '请选择开始日期',
                    onTap: _pickStartDate,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppLabeledField(
                label: '说明（可选）',
                child: TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '例如 按三年折旧'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await context.read<AppRepository>().configurePhysicalAssetDepreciation(
          id: widget.asset.id,
          enabled: _enabled,
          depreciationBase: parseAssetDecimalInput(_baseCtrl.text),
          salvageValue: parseAssetDecimalInput(_salvageCtrl.text),
          usefulLifeMonths: int.tryParse(_monthsCtrl.text.trim()) ?? 0,
          startAt: _startAt,
          note: _noteCtrl.text.trim(),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickStartDate() async {
    final first = widget.asset.purchaseDate ?? DateTime(1970);
    var initial = _startAt ?? widget.asset.purchaseDate ?? assetToday();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(assetToday())) initial = assetToday();
    final selected = await showAppDatePicker(
      context,
      initial: initial,
      first: first,
      last: assetToday(),
      title: '折旧开始日期',
    );
    if (selected != null && mounted) setState(() => _startAt = selected);
  }
}

class AssetSellSheet extends StatefulWidget {
  final PhysicalAssetEntity asset;
  const AssetSellSheet({super.key, required this.asset});

  @override
  State<AssetSellSheet> createState() => _AssetSellSheetState();
}

class _AssetSellSheetState extends State<AssetSellSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _noteCtrl;
  int? _accountId;
  DateTime _soldAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _feeCtrl = TextEditingController(text: '0');
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    _accountId ??= repo.accounts.firstOrNull?.id;
    final amount = parseAssetDecimalInput(_amountCtrl.text);
    final fee = parseAssetDecimalInput(_feeCtrl.text);
    final valid = assetDecimalInputValid(_amountCtrl.text, required: true) &&
        assetDecimalInputValid(_feeCtrl.text, required: true) &&
        amount >= Decimal.zero &&
        fee >= Decimal.zero &&
        fee <= amount;
    final net = amount - fee;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: '出售资产',
          subtitle: '出售入账只影响账户余额，不进入普通收入统计。',
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          onAction: valid ? _save : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            children: [
              AppLabeledField(
                label: '成交价',
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: moneyInputFormatters(),
                  decoration:
                      iosInputDecoration(context, prefix: '¥ ', hint: '实际成交金额'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              AppLabeledField(
                label: '出售费用',
                helperText: '平台手续费、运费等；不会另记普通支出',
                child: TextField(
                  controller: _feeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: moneyInputFormatters(),
                  decoration: iosInputDecoration(context, prefix: '¥ '),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              AssetDetailSection(
                title: '结算',
                children: [
                  AssetDetailRow(
                    label: '净到账',
                    value: MoneyFormat.string(net),
                  ),
                  AssetDetailRow(
                    label: '成交日期',
                    value: assetDateText(_soldAt),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AssetActionButton(
                label: '选择成交日期',
                icon: Icons.event_outlined,
                onTap: _pickSoldAt,
              ),
              const SizedBox(height: 12),
              AppLabeledField(
                label: '收款账户',
                child: AssetAccountDropdown(
                  value: _accountId,
                  accounts: repo.accounts,
                  hint: '选择收款账户',
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              ),
              const SizedBox(height: 12),
              AppLabeledField(
                label: '备注（可选）',
                child: TextField(
                  controller: _noteCtrl,
                  decoration: iosInputDecoration(context, hint: '例如 闲鱼出售'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<AppRepository>().sellPhysicalAsset(
            id: widget.asset.id,
            saleAmount: parseAssetDecimalInput(_amountCtrl.text),
            saleFee: parseAssetDecimalInput(_feeCtrl.text),
            accountId: _accountId,
            soldAt: _soldAt,
            note: _noteCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickSoldAt() async {
    final selected = await showAppDatePicker(
      context,
      initial: _soldAt,
      first: widget.asset.purchaseDate,
      last: DateTime.now(),
      title: '成交日期',
    );
    if (selected != null && mounted) setState(() => _soldAt = selected);
  }
}
