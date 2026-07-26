import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/assets/asset_media_store.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';
import 'asset_media_picker.dart';
import 'physical_asset_grid.dart';

Future<int?> showPhysicalAssetPurchaseSheet(
  BuildContext context, {
  required AppRepository repository,
  int? bookId,
  AssetPurchaseAllocationCandidate? initialCandidate,
}) {
  return showBlurSheet<int>(
    context,
    child: PhysicalAssetPurchaseSheet(
      repository: repository,
      bookId: bookId,
      initialCandidate: initialCandidate,
    ),
  );
}

class PhysicalAssetPurchaseSheet extends StatefulWidget {
  final AppRepository repository;
  final int? bookId;

  /// 预选的购买账单：从「添加」弹层的最近账单行进来时直达第 2 步表单，
  /// 跳过完整账单列表（「重选」仍可回到列表）。
  final AssetPurchaseAllocationCandidate? initialCandidate;

  const PhysicalAssetPurchaseSheet({
    super.key,
    required this.repository,
    this.bookId,
    this.initialCandidate,
  });

  @override
  State<PhysicalAssetPurchaseSheet> createState() =>
      _PhysicalAssetPurchaseSheetState();
}

class _PhysicalAssetPurchaseSheetState
    extends State<PhysicalAssetPurchaseSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _grossController = TextEditingController();
  final _refundController = TextEditingController();
  final _valueController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _locationController = TextEditingController();
  final _noteController = TextEditingController();

  AssetPurchaseAllocationCandidate? _candidate;
  AssetType _assetType = AssetType.other;
  PhysicalAssetStatus _status = PhysicalAssetStatus.active;
  DateTime? _warrantyUntil;
  bool _includeInNetWorth = false;
  bool _saving = false;
  bool _valueEdited = false;
  bool _saved = false;
  String? _formError;
  AssetMediaFiles? _media;
  AssetMediaStore? _mediaStore;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCandidate;
    if (initial != null) _applyCandidate(initial);
  }

  @override
  void dispose() {
    if (!_saved && _media != null && _mediaStore != null) {
      unawaited(_mediaStore!.deleteFiles(_media!));
    }
    for (final controller in [
      _searchController,
      _nameController,
      _grossController,
      _refundController,
      _valueController,
      _brandController,
      _modelController,
      _locationController,
      _noteController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<AssetPurchaseAllocationCandidate> get _candidates =>
      widget.repository.eligiblePhysicalAssetPurchaseTransactions(
        bookId: widget.bookId,
        query: _searchController.text,
      );

  int? _parseCents(String raw) {
    final value = Decimal.tryParse(raw.trim().replaceAll(',', ''));
    return value == null ? null : decimalToBudgetCents(value);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String? get _validationMessage {
    final candidate = _candidate;
    if (candidate == null) return '请先选择购买账单';
    if (_nameController.text.trim().isEmpty) return '请填写物品名称';
    final gross = _parseCents(_grossController.text);
    if (gross == null || gross <= 0) return '请填写有效的购买金额';
    if (gross > candidate.remainingGrossCents) return '购买金额超过账单可分配金额';
    final refund = _parseCents(_refundController.text);
    if (refund == null || refund < 0) return '请填写有效的退款金额';
    if (refund > candidate.remainingRefundCents) return '退款金额超过待分配退款';
    if (refund > gross) return '退款金额不能超过购买金额';
    final value = Decimal.tryParse(_valueController.text.trim());
    if (value == null || value < Decimal.zero) return '请填写有效的当前估值';
    final warrantyUntil = _warrantyUntil;
    if (warrantyUntil != null &&
        _dateOnly(warrantyUntil)
            .isBefore(_dateOnly(candidate.transaction.date))) {
      return '保修到期日不能早于购买日期';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: _candidate == null ? '从账单加入物品' : '填写物品信息',
            subtitle:
                _candidate == null ? '选择原购买账单，不会再记一笔支出' : '第 2 步 · 分配订单金额并补充资料',
            onClose: () => Navigator.pop(context),
            actionLabel: _candidate == null ? null : '保存',
            onAction: _saving ? null : _save,
            actionKey: const Key('asset-purchase-save'),
          ),
          Flexible(
            child: _candidate == null ? _buildTransactionStep() : _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionStep() {
    final candidates = _candidates;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            key: const Key('asset-purchase-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: iosInputDecoration(context, hint: '搜索商户、分类或金额')
                .copyWith(prefixIcon: const Icon(Icons.search, size: 19)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: candidates.isEmpty
              ? const AppEmptyState(
                  mood: MascotMood.empty,
                  title: '没有可分配的支出账单',
                  message: '记一笔支出后，再回来把它加入物品',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _candidateCard(candidates[index]),
                ),
        ),
      ],
    );
  }

  Widget _candidateCard(AssetPurchaseAllocationCandidate candidate) {
    final scheme = Theme.of(context).colorScheme;
    final transaction = candidate.transaction;
    final bookName = widget.repository.books
            .where((book) => book.id == transaction.bookId)
            .firstOrNull
            ?.name ??
        '总账本';
    final title = transaction.note.trim().isEmpty
        ? transaction.categoryNameZh.isEmpty
            ? '支出账单'
            : transaction.categoryNameZh
        : transaction.note.trim();
    final cardDecoration = appCardDecoration(scheme);
    return Material(
      color: cardDecoration.color,
      shape: cardDecoration.shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectCandidate(candidate),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.iconCircleFill(scheme),
                ),
                child: const Icon(Icons.receipt_long_outlined, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle(scheme)),
                    const SizedBox(height: 3),
                    Text(
                      '${_dateText(transaction.date)} · $bookName',
                      style: AppType.secondary(scheme),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '可分配 ${_money(candidate.remainingGrossCents)}'
                      '${candidate.remainingRefundCents > 0 ? ' · 待分配退款 ${_money(candidate.remainingRefundCents)}' : ''}',
                      style: AppType.secondary(scheme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                MoneyFormat.string(transaction.amount),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: AppTextColor.secondary(scheme)),
            ],
          ),
        ),
      ),
    );
  }

  void _applyCandidate(AssetPurchaseAllocationCandidate candidate) {
    final defaultRefund = candidate.remainingRefundCents
        .clamp(
          0,
          candidate.remainingGrossCents,
        )
        .toInt();
    _grossController.text = _decimalText(candidate.remainingGrossCents);
    _refundController.text = _decimalText(defaultRefund);
    _valueController.text =
        _decimalText(candidate.remainingGrossCents - defaultRefund);
    _candidate = candidate;
  }

  void _selectCandidate(AssetPurchaseAllocationCandidate candidate) {
    setState(() => _applyCandidate(candidate));
  }

  Widget _buildForm() {
    final scheme = Theme.of(context).colorScheme;
    final candidate = _candidate!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                leading: const Icon(Icons.receipt_long_outlined),
                title: candidate.transaction.note.trim().isEmpty
                    ? '原购买账单'
                    : candidate.transaction.note.trim(),
                subtitle:
                    '${_dateText(candidate.transaction.date)} · ${MoneyFormat.string(candidate.transaction.amount)}',
                trailing: AppPillButton(
                  label: '重选',
                  onPressed: () => setState(() => _candidate = null),
                ),
              ),
            ],
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(
              _formError!,
              key: const Key('asset-purchase-form-error'),
              style: AppType.caption(scheme).copyWith(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 14),
          AppLabeledField(
            label: '物品名称',
            child: TextField(
              key: const Key('asset-purchase-name'),
              controller: _nameController,
              autofocus: true,
              maxLength: 30,
              decoration: iosInputDecoration(context, hint: '例如 无线耳机'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          AppLabeledField(
            label: '物品分类',
            child: AppPickerField(
              text: _assetType.label,
              hint: '选择分类',
              leading: Icon(
                assetTypeIcon(_assetType),
                size: 18,
                color: AppTextColor.secondary(scheme),
              ),
              onTap: (menuCtx) => showPickerMenu(
                menuCtx,
                [
                  for (final type in AssetType.values)
                    IosMenuItem(
                      label: type.label,
                      icon: assetTypeIcon(type),
                      selected: type == _assetType,
                      onTap: () => setState(() => _assetType = type),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppLabeledField(
            label: '使用状态',
            child: SlidingSegment<PhysicalAssetStatus>(
              key: const Key('asset-purchase-usage-status'),
              items: const [
                (PhysicalAssetStatus.active, '在用'),
                (PhysicalAssetStatus.idle, '闲置'),
              ],
              value: _status,
              onChanged: (value) => setState(() => _status = value),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppLabeledField(
                  label: '分配购买金额',
                  helperText: '最多 ${_money(candidate.remainingGrossCents)}',
                  child: _moneyField(_grossController),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppLabeledField(
                  label: '分配退款金额',
                  helperText: '最多 ${_money(candidate.remainingRefundCents)}',
                  child: _moneyField(_refundController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppLabeledField(
            label: '当前估值',
            helperText: '默认等于这件物品的净购置成本',
            child: TextField(
              controller: _valueController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyInputFormatters(),
              decoration: iosInputDecoration(context, prefix: '¥ '),
              onChanged: (_) {
                _valueEdited = true;
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 14),
          AppLabeledField(
            label: '物品照片（可选）',
            child: _mediaField(),
          ),
          const SizedBox(height: 14),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
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
          const SizedBox(height: 14),
          AppLabeledField(
            label: '品牌（可选）',
            child: TextField(
              controller: _brandController,
              decoration: iosInputDecoration(context, hint: '例如 Apple'),
            ),
          ),
          const SizedBox(height: 12),
          AppLabeledField(
            label: '型号（可选）',
            child: TextField(
              controller: _modelController,
              decoration: iosInputDecoration(context, hint: '例如 AirPods Pro'),
            ),
          ),
          const SizedBox(height: 12),
          AppLabeledField(
            label: '存放位置（可选）',
            child: TextField(
              controller: _locationController,
              decoration: iosInputDecoration(context, hint: '例如 客厅'),
            ),
          ),
          const SizedBox(height: 12),
          AppLabeledField(
            label: '保修到期日（可选）',
            child: AppPickerField(
              text: _warrantyUntil == null ? null : _dateText(_warrantyUntil!),
              hint: '未设置',
              trailingIcon: Icons.event_outlined,
              onTap: (_) => _pickWarrantyDate(),
            ),
          ),
          const SizedBox(height: 12),
          AppLabeledField(
            label: '备注（可选）',
            child: TextField(
              controller: _noteController,
              maxLength: 80,
              maxLines: 2,
              style: AppType.body(scheme),
              decoration: iosInputDecoration(context, hint: '购买渠道、配置等'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyField(TextEditingController controller) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: moneyInputFormatters(),
        decoration: iosInputDecoration(context, prefix: '¥ '),
        onChanged: (_) {
          if (!_valueEdited) {
            final gross = _parseCents(_grossController.text) ?? 0;
            final refund = _parseCents(_refundController.text) ?? 0;
            _valueController.text =
                _decimalText((gross - refund).clamp(0, gross).toInt());
          }
          setState(() {});
        },
      );

  Widget _mediaField() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 112,
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
              child: _media == null
                  ? ColoredBox(
                      color: AppColors.iconCircleFill(scheme),
                      child: Icon(assetTypeIcon(_assetType),
                          color: AppTextColor.secondary(scheme)),
                    )
                  : Image.file(
                      File(_media!.thumbnailPath),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _media == null ? '添加一张封面照片' : '已保存原图和列表缩略图',
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
    final next = await pickAssetPhoto(
      context,
      source,
      previous: _media,
    );
    if (next == null) return;
    _mediaStore ??= await sharedAssetMediaStore();
    if (mounted) setState(() => _media = next);
  }

  Future<void> _pickWarrantyDate() async {
    final purchaseDay = _candidate == null
        ? _dateOnly(DateTime.now().subtract(const Duration(days: 3650)))
        : _dateOnly(_candidate!.transaction.date);
    final defaultLast =
        _dateOnly(DateTime.now().add(const Duration(days: 3650)));
    final last = purchaseDay.isAfter(defaultLast) ? purchaseDay : defaultLast;
    var initial = _warrantyUntil ?? purchaseDay.add(const Duration(days: 365));
    if (initial.isBefore(purchaseDay)) initial = purchaseDay;
    if (initial.isAfter(last)) initial = last;
    final selected = await showAppDatePicker(
      context,
      initial: initial,
      first: purchaseDay,
      last: last,
      title: '保修到期日',
    );
    if (selected != null && mounted) setState(() => _warrantyUntil = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final validationMessage = _validationMessage;
    if (validationMessage != null) {
      setState(() => _formError = validationMessage);
      showAppToast(context, validationMessage);
      return;
    }
    setState(() => _formError = null);
    setState(() => _saving = true);
    try {
      final id = await widget.repository.addPhysicalAssetFromTransaction(
        transactionId: _candidate!.transaction.id,
        name: _nameController.text.trim(),
        assetType: _assetType,
        status: _status,
        allocatedGrossCents: _parseCents(_grossController.text)!,
        allocatedRefundCents: _parseCents(_refundController.text)!,
        currentValue: Decimal.parse(_valueController.text.trim()),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        location: _locationController.text.trim(),
        warrantyUntil: _warrantyUntil,
        photoPath: _media?.originalPath ?? '',
        thumbnailPath: _media?.thumbnailPath ?? '',
        note: _noteController.text.trim(),
        includeInNetWorth: _includeInNetWorth,
      );
      _saved = true;
      if (!mounted) return;
      showAppToast(context, '已加入「${_nameController.text.trim()}」');
      Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        showAppToast(context, error.toString().replaceFirst('Bad state: ', ''));
        setState(() => _saving = false);
      }
    }
  }
}

String _decimalText(int cents) =>
    (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2);

String _money(int cents) => MoneyFormat.string(
      budgetDecimalFromCents(cents) ?? Decimal.zero,
    );

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
