// 物品资产新建/编辑表单弹层（从 accounts_view.dart 拆出）。
import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_allocation.dart';
import '../../core/assets/asset_media_store.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import 'asset_form_kit.dart';
import 'asset_media_picker.dart';
import 'physical_asset_grid.dart';

class PhysicalAssetFormSheet extends StatefulWidget {
  final PhysicalAssetEntity? asset;
  final PhysicalAssetSourceType sourceType;

  const PhysicalAssetFormSheet({
    super.key,
    this.asset,
    this.sourceType = PhysicalAssetSourceType.historicalExisting,
  });

  @override
  State<PhysicalAssetFormSheet> createState() => _PhysicalAssetFormSheetState();
}

class _PhysicalAssetFormSheetState extends State<PhysicalAssetFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _currentCtrl;
  late final TextEditingController _purchaseCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _noteCtrl;
  late AssetType _assetType;
  late PhysicalAssetSourceType _sourceType;
  late PhysicalAssetStatus _status;
  late bool _includeInNetWorth;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;
  int? _paymentAccountId;
  int? _purchaseCategoryId;
  AssetMediaStore? _mediaStore;
  AssetMediaFiles? _pendingMedia;
  bool _mediaCommitted = false;
  bool _saving = false;
  bool _resolvedLinkedPurchasePrice = false;

  static const _manualSources = [
    PhysicalAssetSourceType.historicalExisting,
    PhysicalAssetSourceType.giftReceived,
    PhysicalAssetSourceType.inheritance,
    PhysicalAssetSourceType.manualOther,
  ];

  bool get _editing => widget.asset != null;
  bool get _newPurchase =>
      !_editing &&
      _sourceType == PhysicalAssetSourceType.newPurchaseWithAccount;
  bool get _purchasePriceLocked =>
      _editing &&
      widget.asset!.acquisitionCostSource ==
          AssetAcquisitionCostSource.transactionAllocations;
  bool get _purchaseDateLocked => _purchasePriceLocked;
  bool get _purchasePriceKnown =>
      _purchasePriceLocked ||
      _purchaseCtrl.text.trim().isNotEmpty ||
      _sourceType == PhysicalAssetSourceType.giftReceived ||
      _sourceType == PhysicalAssetSourceType.inheritance;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _nameCtrl = TextEditingController(text: asset?.name ?? '');
    _currentCtrl =
        TextEditingController(text: asset?.currentValue.toString() ?? '');
    _purchaseCtrl =
        TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    _brandCtrl = TextEditingController(text: asset?.brand ?? '');
    _modelCtrl = TextEditingController(text: asset?.model ?? '');
    _locationCtrl = TextEditingController(text: asset?.location ?? '');
    _noteCtrl = TextEditingController(text: asset?.note ?? '');
    _assetType = asset?.assetType ?? AssetType.digital;
    _sourceType = asset?.sourceType ?? widget.sourceType;
    _status = asset?.status ?? PhysicalAssetStatus.active;
    _includeInNetWorth = asset?.includeInNetWorth ?? false;
    _purchaseDate = asset?.purchaseDate ??
        (_sourceType == PhysicalAssetSourceType.newPurchaseWithAccount
            ? assetToday()
            : null);
    _warrantyUntil = asset?.warrantyUntil;
    if (asset != null &&
        asset.acquisitionCostSource ==
            AssetAcquisitionCostSource.manualUnknown) {
      _purchaseCtrl.clear();
    }
  }

  @override
  void dispose() {
    if (!_mediaCommitted && _pendingMedia != null && _mediaStore != null) {
      unawaited(_mediaStore!.deleteFiles(_pendingMedia!));
    }
    _nameCtrl.dispose();
    _currentCtrl.dispose();
    _purchaseCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedLinkedPurchasePrice || !_purchasePriceLocked) return;
    final repo = context.read<AppRepository>();
    final cost = repo.physicalAssetAcquisitionCost(widget.asset!.id);
    if (cost.amount != null) {
      _purchaseCtrl.text = cost.amount!.toString();
    }
    final purchaseLink = repo
        .transactionLinksForAsset(widget.asset!.id)
        .where((link) =>
            link.linkType == AssetTransactionLinkType.sourceTransaction ||
            link.linkType == AssetTransactionLinkType.purchaseTransaction)
        .firstOrNull;
    if (purchaseLink != null) {
      final transaction = repo.transactionById(purchaseLink.transactionId);
      if (transaction != null) _purchaseDate = transaction.date;
    }
    _resolvedLinkedPurchasePrice = true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final expenseCategories =
        repo.categoriesForKindRanked(TransactionKind.expense);
    _paymentAccountId ??= repo.accounts.firstOrNull?.id;
    _purchaseCategoryId ??= expenseCategories.firstOrNull?.id;

    final valid = _nameCtrl.text.trim().isNotEmpty &&
        assetDecimalInputValid(_currentCtrl.text, required: true) &&
        assetDecimalInputValid(_purchaseCtrl.text, required: _newPurchase) &&
        (!_newPurchase ||
            (_paymentAccountId != null && _purchaseDate != null)) &&
        (_warrantyUntil == null ||
            _purchaseDate == null ||
            !assetCalendarDay(_warrantyUntil!)
                .isBefore(assetCalendarDay(_purchaseDate!)));
    final screenH = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: _editing
                ? '编辑物品'
                : _newPurchase
                    ? '记录新购买'
                    : '手工补录物品',
            onClose: () => Navigator.pop(context),
            actionLabel: '保存',
            onAction: valid ? _save : null,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLabeledField(
                    label: '物品名称',
                    child: TextField(
                      key: const Key('physical-asset-name'),
                      controller: _nameCtrl,
                      autofocus: true,
                      maxLength: 30,
                      decoration: iosInputDecoration(context, hint: '例如 无线耳机'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '物品分类',
                    child: AssetEnumDropdown<AssetType>(
                      value: _assetType,
                      values: AssetType.values,
                      labelOf: (value) => value.label,
                      hint: '选择分类',
                      onChanged: (value) => setState(() => _assetType = value),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '物品照片（可选）',
                    helperText: '照片会复制到 App 受管目录，并生成列表缩略图。',
                    child: _buildPhotoField(),
                  ),
                  const SizedBox(height: 14),
                  if (!_editing) ...[
                    AppLabeledField(
                      label: '物品来源',
                      helperText: _newPurchase
                          ? '保存后会同步生成购买支出，不会重复入账。'
                          : '历史物品不会减少账户余额，也不会补造旧支出。',
                      child: _newPurchase
                          ? AppReadOnlyField(
                              text: _sourceType.label,
                              icon: Icons.shopping_bag_outlined,
                            )
                          : AssetEnumDropdown<PhysicalAssetSourceType>(
                              value: _sourceType,
                              values: _manualSources,
                              labelOf: (value) => value.label,
                              hint: '选择来源',
                              onChanged: (value) =>
                                  setState(() => _sourceType = value),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (_newPurchase) ...[
                      AppLabeledField(
                        label: '付款账户',
                        child: AssetAccountDropdown(
                          value: _paymentAccountId,
                          accounts: repo.accounts,
                          hint: '选择付款账户',
                          onChanged: (value) =>
                              setState(() => _paymentAccountId = value),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppLabeledField(
                        label: '支出分类',
                        child: AssetCategoryDropdown(
                          value: _purchaseCategoryId,
                          categories: expenseCategories,
                          hint: '选择支出分类',
                          onChanged: (value) =>
                              setState(() => _purchaseCategoryId = value),
                        ),
                      ),
                    ],
                  ],
                  AppLabeledField(
                    label: '当前估值',
                    helperText: '填写今天大约能卖多少钱，不是原购买价。',
                    child: TextField(
                      key: const Key('physical-asset-current-value'),
                      controller: _currentCtrl,
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
                    label: _purchasePriceLocked ? '净购置成本' : '购买价',
                    helperText: _purchasePriceLocked
                        ? '成本来自原购买账单，不能在这里重复修改。'
                        : _sourceType == PhysicalAssetSourceType.giftReceived ||
                                _sourceType ==
                                    PhysicalAssetSourceType.inheritance
                            ? '没有实际支出可留空，将按 ¥0 记录。'
                            : _newPurchase
                                ? '新购买必须填写，金额会同步写入支出。'
                                : '不知道可以留空，日均花费和保值率会显示待补充。',
                    child: TextField(
                      key: const Key('physical-asset-purchase-price'),
                      controller: _purchaseCtrl,
                      readOnly: _purchasePriceLocked,
                      enableInteractiveSelection: !_purchasePriceLocked,
                      showCursor: !_purchasePriceLocked,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: moneyInputFormatters(),
                      decoration: iosInputDecoration(
                        context,
                        prefix: '¥ ',
                        hint: _newPurchase ? '必填' : '可留空',
                      ).copyWith(
                        suffixIcon: _purchasePriceLocked
                            ? Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: AppTextColor.secondary(scheme),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: _newPurchase || _purchaseDateLocked
                        ? '购买日期'
                        : '购买日期（可选）',
                    helperText: _purchaseDateLocked
                        ? '购买日期继承原账单，避免物品指标与账单日期冲突。'
                        : _purchaseDate == null
                            ? '未填写时持有天数和日均花费不会计算。'
                            : '持有天数会从这一天开始计算。',
                    child: _purchaseDateLocked
                        ? AppReadOnlyField(
                            text: assetDateText(_purchaseDate),
                            icon: Icons.event_outlined,
                          )
                        : AssetNullableDateField(
                            fieldKey: const Key('physical-asset-purchase-date'),
                            value: _purchaseDate,
                            emptyText: _newPurchase ? '请选择购买日期' : '暂不清楚',
                            onTap: _pickPurchaseDate,
                            onClear: _newPurchase
                                ? null
                                : () => setState(() => _purchaseDate = null),
                          ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '使用状态',
                    child: SlidingSegment<PhysicalAssetStatus>(
                      key: const Key('physical-asset-usage-status'),
                      items: const [
                        (PhysicalAssetStatus.active, '在用'),
                        (PhysicalAssetStatus.idle, '闲置'),
                      ],
                      value: _status == PhysicalAssetStatus.idle
                          ? PhysicalAssetStatus.idle
                          : PhysicalAssetStatus.active,
                      onChanged: (value) => setState(() => _status = value),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_editing) ...[
                    const AssetHintBox(
                      text: '出售、报废、丢失、赠送和归档请从资产详情执行。',
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppLabeledField(
                          label: '品牌（可选）',
                          child: TextField(
                            controller: _brandCtrl,
                            decoration:
                                iosInputDecoration(context, hint: '例如 Apple'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppLabeledField(
                          label: '型号（可选）',
                          child: TextField(
                            controller: _modelCtrl,
                            decoration: iosInputDecoration(context,
                                hint: '例如 AirPods Pro'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '保修到期日（可选）',
                    helperText: _warrantyUntil != null &&
                            _purchaseDate != null &&
                            _warrantyUntil!.isBefore(_purchaseDate!)
                        ? '保修到期日不能早于购买日期。'
                        : null,
                    child: AssetNullableDateField(
                      fieldKey: const Key('physical-asset-warranty-date'),
                      value: _warrantyUntil,
                      emptyText: '未设置',
                      onTap: _pickWarrantyDate,
                      onClear: _warrantyUntil == null
                          ? null
                          : () => setState(() => _warrantyUntil = null),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '存放位置（可选）',
                    child: TextField(
                      controller: _locationCtrl,
                      decoration: iosInputDecoration(context, hint: '例如 客厅书桌'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppLabeledField(
                    label: '备注（可选）',
                    child: TextField(
                      controller: _noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 80,
                      decoration: iosInputDecoration(context, hint: '购买渠道、配置等'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      SettingsRow(
                        title: '计入净资产',
                        subtitle: _includeInNetWorth
                            ? '按当前估值进入人民币净资产合计'
                            : '只记录物品，不影响顶部净资产',
                        trailing: AppSwitch(
                          key: const Key('physical-asset-net-worth-switch'),
                          value: _includeInNetWorth,
                          onChanged: (value) =>
                              setState(() => _includeInNetWorth = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final repo = context.read<AppRepository>();
      final currentValue = parseAssetDecimalInput(_currentCtrl.text);
      final resolvedPurchasePrice = _purchasePriceLocked
          ? repo.physicalAssetAcquisitionCost(widget.asset!.id).amount
          : null;
      final purchasePrice = resolvedPurchasePrice ??
          (_purchaseCtrl.text.trim().isEmpty
              ? Decimal.zero
              : parseAssetDecimalInput(_purchaseCtrl.text));
      if (!_editing && _sourceType == PhysicalAssetSourceType.manualOther) {
        final needsConfirm = currentValue >= Decimal.fromInt(500) ||
            purchasePrice > Decimal.zero;
        if (needsConfirm) {
          final confirmed = await showConfirmDialog(
            context,
            title: '确认其他来源',
            message: '这不会减少账户余额，也不会生成支出记录。若是最近购买，建议改选“新购买记账”。',
            confirmText: '仍然保存',
          );
          if (!confirmed) return;
        }
      }
      if (_editing) {
        await repo.updatePhysicalAsset(
          id: widget.asset!.id,
          name: _nameCtrl.text.trim(),
          assetType: _assetType,
          purchasePrice: purchasePrice,
          currentValue: currentValue,
          currencyCode: widget.asset!.currencyCode,
          status: _status,
          purchaseDate: _purchaseDate,
          clearPurchaseDate: !_purchaseDateLocked && _purchaseDate == null,
          purchasePriceKnown: _purchasePriceLocked ? null : _purchasePriceKnown,
          brand: _brandCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          warrantyUntil: _warrantyUntil,
          clearWarrantyUntil: _warrantyUntil == null,
          note: _noteCtrl.text.trim(),
          includeInNetWorth: _includeInNetWorth,
        );
        await _commitPendingMedia(repo, widget.asset!.id);
      } else {
        final assetId = await repo.addPhysicalAsset(
          name: _nameCtrl.text.trim(),
          assetType: _assetType,
          currentValue: currentValue,
          purchasePrice: purchasePrice,
          purchasePriceKnown: _purchasePriceKnown,
          sourceType: _sourceType,
          status: _status,
          paymentAccountId: _paymentAccountId,
          purchaseCategoryId: _purchaseCategoryId,
          brand: _brandCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          warrantyUntil: _warrantyUntil,
          note: _noteCtrl.text.trim(),
          includeInNetWorth: _includeInNetWorth,
          purchaseDate: _purchaseDate,
        );
        await _commitPendingMedia(repo, assetId);
      }
      _mediaCommitted = true;
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  Future<void> _pickPurchaseDate() async {
    final selected = await showAppDatePicker(
      context,
      initial: _purchaseDate ?? assetToday(),
      first: DateTime(1970),
      last: assetToday(),
      title: '购买日期',
    );
    if (selected != null && mounted) {
      setState(() => _purchaseDate = selected);
    }
  }

  Future<void> _pickWarrantyDate() async {
    final first = _purchaseDate ?? DateTime(1970);
    final last = DateTime(assetToday().year + 30, 12, 31);
    var initial = _warrantyUntil ?? first.add(const Duration(days: 365));
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final selected = await showAppDatePicker(
      context,
      initial: initial,
      first: first,
      last: last,
      title: '保修到期日',
    );
    if (selected != null && mounted) {
      setState(() => _warrantyUntil = selected);
    }
  }

  Widget _buildPhotoField() {
    final scheme = Theme.of(context).colorScheme;
    final existingPath = widget.asset == null
        ? ''
        : widget.asset!.thumbnailPath.isNotEmpty
            ? widget.asset!.thumbnailPath
            : widget.asset!.photoPath;
    final previewPath = _pendingMedia?.thumbnailPath ?? existingPath;
    return Container(
      height: 126,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inputFill(scheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: previewPath.isNotEmpty && File(previewPath).existsSync()
                  ? Image.file(File(previewPath), fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppColors.iconCircleFill(scheme),
                      child: Icon(
                        assetTypeIcon(_assetType),
                        color: AppTextColor.secondary(scheme),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              previewPath.isEmpty ? '添加封面照片' : '已选择封面照片',
              style: AppType.secondary(scheme),
            ),
          ),
          Tooltip(
            message: '拍照',
            child: AppCircleButton(
              icon: Icons.photo_camera_outlined,
              onPressed: () => _pickMedia(ImageSource.camera),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '从相册选择',
            child: AppCircleButton(
              icon: Icons.photo_library_outlined,
              onPressed: () => _pickMedia(ImageSource.gallery),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source) async {
    final imported = await pickAssetPhoto(
      context,
      source,
      previous: _pendingMedia,
    );
    if (imported == null) return;
    _mediaStore ??= await sharedAssetMediaStore();
    if (mounted) setState(() => _pendingMedia = imported);
  }

  Future<void> _commitPendingMedia(AppRepository repo, int assetId) async {
    final media = _pendingMedia;
    if (media == null) return;
    await repo.updatePhysicalAssetEvidence(
      assetId,
      photoPath: media.originalPath,
      thumbnailPath: media.thumbnailPath,
      invoicePath: widget.asset?.invoicePath ?? '',
      note: '更新物品照片',
    );
    final existing = widget.asset;
    if (existing != null && _mediaStore != null) {
      try {
        await _mediaStore!.deleteFiles(AssetMediaFiles(
          originalPath: existing.photoPath,
          thumbnailPath: existing.thumbnailPath,
        ));
      } on FileSystemException {
        // New media is already committed; orphan cleanup can retry later.
      }
    }
  }
}
