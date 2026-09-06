import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_version.dart';
import '../../core/assets/repayment_reminder.dart';
import '../../core/money_format.dart';
import '../../core/models/transaction_card_display.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import 'theme_settings_view.dart';
import '../../widgets/app_toast.dart';
import '../common/app_sheet.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import 'ai_setting_view.dart';
import 'app_update_flow.dart';
import 'backup_view.dart';
import 'transaction_display_settings.dart';
import '../../widgets/app_page_route.dart';

/// 设置：ChatGPT 式全屏弹窗（图二）——圆顶角卡从底部滑出，右上角 ✕，
/// 无标题文字，头像居中开场。别再从抽屉 push 全屏页。
Future<void> showSettingsSheet(BuildContext context) async {
  await showBlurSheet<void>(
    context,
    radius: 28,
    barrierOpacity: 0.3,
    child: const FractionallySizedBox(
      heightFactor: 0.96,
      child: SettingsView(),
    ),
  );
}

/// 设置页内容：iOS 风分组——灰底白卡 + 发丝分隔。作为弹窗内容渲染。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();

    Future<void> setRepaymentReminder(bool enabled) async {
      await repo.setRepaymentReminderEnabled(enabled);
      // 开关和整行点击必须走同一条副作用路径，避免只点文字时
      // 状态变了但系统通知没有重新排程。
      if (enabled) {
        await RepaymentReminderScheduler.reschedule(repo);
      } else {
        await RepaymentReminderScheduler.cancelAll();
      }
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        // 和主页同款暖渐变背景（用户点名：设置也要有背景色过渡）；
        // 深色模式保持纯色暖深底。
        decoration: BoxDecoration(
          color: scheme.brightness == Brightness.dark
              ? AppColors.appBg(scheme)
              : null,
          gradient: scheme.brightness == Brightness.dark
              ? null
              : AppColors.warmBackground,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: const EdgeInsets.only(top: 18, bottom: 32),
                children: [
                  _ProfileHeaderCard(
                    nickname: repo.profileNickname,
                    avatarPath: repo.profileAvatarPath,
                    onTap: () => showEditProfileSheet(context),
                  ),
                  const SettingsSectionLabel('管理'),
                  // 抽屉功能列表里已有的入口（预算/资产/分类等）这里不重复——
                  // 设置页只放抽屉没有的：AI 设置、备份恢复、显示、小组件、关于。
                  SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.sparkles),
                      title: 'AI 记账设置',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute<void>(
                            builder: (_) => const AiSettingView()),
                      ),
                    ),
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.cloud_upload),
                      title: '备份与恢复',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute<void>(builder: (_) => const BackupView()),
                      ),
                    ),
                  ]),
                  const SettingsSectionLabel('显示'),
                  SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.rectangle_3_offgrid),
                      title: '账单与聊天显示',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              repo.transactionCardDisplayMode.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.trailingValue(scheme),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.chevron_forward,
                            size: 18,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                      onTap: () => showTransactionDisplaySettings(context),
                    ),
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.paintbrush),
                      title: '主题外观',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute<void>(
                            builder: (_) => const ThemeSettingsView()),
                      ),
                    ),
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.money_yen_circle),
                      title: '金额显示',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              moneyDisplayLabel(repo),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.trailingValue(scheme),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(CupertinoIcons.chevron_forward,
                              size: 18, color: scheme.outline),
                        ],
                      ),
                      onTap: () => showMoneyDisplaySheet(context),
                    ),
                  ]),
                  const SettingsSectionLabel('提醒'),
                  SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.bell),
                      title: '还款提醒',
                      subtitle: '信用卡/贷款/借入还款日前一天和当天各提醒一次',
                      trailing: AppSwitch(
                        value: repo.repaymentReminderEnabled,
                        semanticLabel: '还款提醒',
                        onChanged: setRepaymentReminder,
                      ),
                      onTap: () =>
                          setRepaymentReminder(!repo.repaymentReminderEnabled),
                    ),
                  ]),
                  const SettingsSectionLabel('小组件'),
                  SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.eye_slash),
                      title: '隐藏金额',
                      subtitle: '桌面小组件不显示具体金额',
                      trailing: AppSwitch(
                        value: repo.widgetPrivacyMode,
                        semanticLabel: '隐藏金额',
                        onChanged: repo.setWidgetPrivacyMode,
                      ),
                      onTap: () => repo.setWidgetPrivacyMode(
                        !repo.widgetPrivacyMode,
                      ),
                    ),
                  ]),
                  const SettingsSectionLabel('关于'),
                  SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.arrow_down_circle),
                      title: '检查更新',
                      // 版本号只留这一处（关于行不再重复；关于弹层里另有完整版本）。
                      trailing: Text(
                        AppVersion.display,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: 'Nunito',
                            ),
                      ),
                      onTap: () async {
                        showAppToast(context, '正在检查更新…');
                        await checkAppUpdate(context);
                      },
                    ),
                    SettingsRow(
                      leading:
                          const Icon(CupertinoIcons.arrow_counterclockwise),
                      title: '历史版本',
                      subtitle: '安装经过校验的回退包，账本数据保留',
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 18,
                      ),
                      onTap: () => showRollbackCatalog(context),
                    ),
                    SettingsRow(
                      leading: const Icon(CupertinoIcons.info_circle),
                      title: '关于',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => _showAboutSheet(context),
                    ),
                  ]),
                ],
              ),
            ),
            // 右上角 ✕：走全局标准件 AppCircleButton（主页顶栏/返回键同款），
            // 别再手搓白圆按钮（用户点名）。
            Positioned(
              top: 14,
              right: 14,
              child: AppCircleButton(
                icon: CupertinoIcons.xmark,
                size: 40,
                iconSize: 18,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final String nickname;
  final String avatarPath;
  final VoidCallback onTap;

  const _ProfileHeaderCard({
    required this.nickname,
    required this.avatarPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _ProfileAvatar(
                    nickname: nickname,
                    avatarPath: avatarPath,
                    size: 78,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.card(scheme),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline(scheme)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 这里放「用户的名字」不是 App 名；版本号在「关于」里，不在资料区。
              Text(
                nickname.isEmpty ? '点击设置昵称' : nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: nickname.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String nickname;
  final String avatarPath;
  final double size;
  final Uint8List? previewBytes;

  const _ProfileAvatar({
    required this.nickname,
    required this.avatarPath,
    required this.size,
    this.previewBytes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = nickname.trim().isEmpty ? '👤' : nickname.trim()[0];
    Widget placeholder() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.card(scheme),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
          child: Text(
            initial,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurface,
                ),
          ),
        );

    Widget image;
    if (previewBytes != null) {
      image = Image.memory(
        previewBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (avatarPath.isNotEmpty && File(avatarPath).existsSync()) {
      image = Image.file(
        File(avatarPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder(),
      );
    } else {
      return placeholder();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.card(scheme),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

Future<void> showEditProfileSheet(BuildContext context) async {
  await showBlurSheet<void>(
    context,
    radius: 30,
    child: const _EditProfileSheet(),
  );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nicknameCtrl;
  Uint8List? _avatarBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameCtrl = TextEditingController(
        text: context.read<AppRepository>().profileNickname);
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (picked == null) return;
    await _loadAvatarBytes(picked.path);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    await _loadAvatarBytes(path);
  }

  Future<void> _loadAvatarBytes(String path) async {
    try {
      final bytes = await _normalizeAvatarBytes(await File(path).readAsBytes());
      if (!mounted) return;
      setState(() => _avatarBytes = bytes);
    } catch (_) {
      if (mounted) showAppToast(context, '这张图片暂时不能作为头像');
    }
  }

  Future<Uint8List> _normalizeAvatarBytes(Uint8List bytes) async {
    const maxBytes = 200 * 1024;
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final width = originalFrame.image.width;
    final height = originalFrame.image.height;
    originalFrame.image.dispose();
    final maxSide = width > height ? width : height;
    if (maxSide <= 512 && bytes.length <= maxBytes) return bytes;

    for (final side in const [512, 384, 256, 192, 128]) {
      final scale = side / maxSide;
      final targetWidth = (width * scale).round().clamp(1, side);
      final targetHeight = (height * scale).round().clamp(1, side);
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      final out = data?.buffer.asUint8List();
      if (out == null) continue;
      if (out.length <= maxBytes || side == 128) return out;
    }
    return bytes;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<AppRepository>();
    try {
      await repo.setProfileNickname(_nicknameCtrl.text);
      final bytes = _avatarBytes;
      if (bytes != null) {
        await repo.saveProfileAvatarBytes(bytes);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.appBg(scheme),
          borderRadius: BorderRadius.circular(30),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHeader(
                  title: '编辑资料',
                  actionLabel: '保存',
                  onClose: () => Navigator.pop(context),
                  onAction: _saving ? null : _save,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Builder(builder: (avatarCtx) {
                    return GestureDetector(
                      onTap: () => showIosMenu(
                        avatarCtx,
                        [
                          IosMenuItem(
                            label: '拍照',
                            icon: Icons.photo_camera_outlined,
                            onTap: () => _pickImage(ImageSource.camera),
                          ),
                          IosMenuItem(
                            label: '相册',
                            icon: Icons.photo_library_outlined,
                            onTap: () => _pickImage(ImageSource.gallery),
                          ),
                          IosMenuItem(
                            label: '选择文件',
                            icon: Icons.folder_open_outlined,
                            onTap: _pickFile,
                          ),
                        ],
                        width: 160,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _ProfileAvatar(
                            nickname: _nicknameCtrl.text,
                            avatarPath: repo.profileAvatarPath,
                            previewBytes: _avatarBytes,
                            size: 86,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.card(scheme),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.hairline(scheme),
                                ),
                              ),
                              child: Icon(
                                Icons.photo_camera_outlined,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nicknameCtrl,
                    maxLength: 12,
                    textInputAction: TextInputAction.done,
                    decoration: iosInputDecoration(context, hint: '昵称')
                        .copyWith(counterText: ''),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String moneyDisplayLabel(AppRepository repo) {
  final places = repo.moneyDecimalPlaces;
  if (places == 2) return '两位小数';
  if (places == 1) return '一位小数';
  return '整数 · ${_roundingModeLabel(repo.moneyIntegerRoundingMode)}';
}

String _roundingModeLabel(MoneyIntegerRoundingMode mode) {
  return switch (mode) {
    MoneyIntegerRoundingMode.round => '四舍五入',
    MoneyIntegerRoundingMode.ceil => '向上取整',
    MoneyIntegerRoundingMode.floor => '向下取整',
    MoneyIntegerRoundingMode.truncate => '直接取整',
  };
}

String _roundingModeSubtitle(MoneyIntegerRoundingMode mode) {
  return switch (mode) {
    MoneyIntegerRoundingMode.round => '12.50 显示为 13',
    MoneyIntegerRoundingMode.ceil => '只要有小数就进一位',
    MoneyIntegerRoundingMode.floor => '永远舍去到更小整数',
    MoneyIntegerRoundingMode.truncate => '直接去掉小数部分',
  };
}

Future<void> showMoneyDisplaySheet(BuildContext context) async {
  await showBlurSheet<void>(
    context,
    radius: 28,
    child: const _MoneyDisplaySheet(),
  );
}

Future<void> _showAboutSheet(BuildContext context) async {
  await showBlurSheet<void>(
    context,
    radius: 30,
    child: Builder(
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.appBg(scheme),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHeader(title: '关于', onClose: () => Navigator.pop(ctx)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                  child: SettingsGroup(children: [
                    SettingsRow(
                      leading: const Icon(Icons.article_outlined),
                      title: '使用条款',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => _showTextSheet(
                        ctx,
                        title: '使用条款',
                        body:
                            '肥喵记账用于个人记账、账单整理和消费分析。你需要自行确认录入、导入和 AI 识别结果是否准确。\n\nAI 记账和 AI 分析可能产生错误，涉及金额、分类、退款和统计结论时，请以你的真实账单和银行、支付平台记录为准。\n\n你应妥善保管自己的设备、备份文件和 API Key。因误删、误导入、第三方服务异常或设备故障造成的数据损失，建议优先通过备份恢复。',
                      ),
                    ),
                    SettingsRow(
                      leading: const Icon(Icons.lock_outline),
                      title: '隐私政策',
                      trailing:
                          const Icon(CupertinoIcons.chevron_forward, size: 18),
                      onTap: () => _showTextSheet(
                        ctx,
                        title: '隐私政策',
                        body:
                            '肥喵记账默认将账本数据保存在本机。完整备份会包含账本数据库和收据图片，但不会包含 AI API Key。\n\n当你使用 AI 解析或 AI 分析时，相关文本、账单摘要或你输入的问题可能会发送给你配置的 AI 服务提供方，用于生成结果。请避免提交身份证号、银行卡号、验证码等敏感信息。\n\n导入、导出和分享备份文件由你主动触发。请只把备份文件保存到你信任的位置。',
                      ),
                    ),
                    SettingsRow(
                      leading: const Icon(Icons.info_outline),
                      title: AppVersion.name,
                      trailing: Text(
                        AppVersion.fullDisplay,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: 'Nunito',
                            ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _showTextSheet(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  await showBlurSheet<void>(
    context,
    radius: 30,
    child: Builder(
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.appBg(scheme),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHeader(title: title, onClose: () => Navigator.pop(ctx)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                  child: Text(body, style: AppType.body(scheme)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _MoneyDisplaySheet extends StatefulWidget {
  const _MoneyDisplaySheet();

  @override
  State<_MoneyDisplaySheet> createState() => _MoneyDisplaySheetState();
}

class _MoneyDisplaySheetState extends State<_MoneyDisplaySheet> {
  late int _places;
  late MoneyIntegerRoundingMode _roundingMode;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _places = repo.moneyDecimalPlaces;
    _roundingMode = repo.moneyIntegerRoundingMode;
  }

  void _setPlaces(int value) {
    if (_places == value) return;
    setState(() => _places = value);
    context.read<AppRepository>().setMoneyDecimalPlaces(value);
  }

  void _setRoundingMode(MoneyIntegerRoundingMode mode) {
    if (_roundingMode == mode) return;
    setState(() => _roundingMode = mode);
    context.read<AppRepository>().setMoneyIntegerRoundingMode(mode);
  }

  String _previewText() {
    return switch (_places) {
      2 => '¥1,234.56',
      1 => '¥1,234.6',
      _ => switch (_roundingMode) {
          MoneyIntegerRoundingMode.round => '¥1,235',
          MoneyIntegerRoundingMode.ceil => '¥1,235',
          MoneyIntegerRoundingMode.floor => '¥1,234',
          MoneyIntegerRoundingMode.truncate => '¥1,234',
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 18),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHeader(
                  title: '金额显示',
                  subtitle: '只改变金额展示方式，不会修改账单真实金额和计算精度。',
                  onClose: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card(scheme),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '金额保留位数',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: Text(
                            '示例：${_previewText()}',
                            key: ValueKey('${_places}_${_roundingMode.name}'),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontFamily: 'Nunito',
                                      fontWeight: FontWeight.w400,
                                    ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SlidingSegment<int>(
                          items: const [
                            (2, '两位'),
                            (1, '一位'),
                            (0, '整数'),
                          ],
                          value: _places,
                          onChanged: _setPlaces,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _places == 0
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SettingsSectionLabel('整数取整方式'),
                            SettingsGroup(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              children: [
                                for (final mode
                                    in MoneyIntegerRoundingMode.values)
                                  SettingsRow(
                                    title: _roundingModeLabel(mode),
                                    subtitle: _roundingModeSubtitle(mode),
                                    onTap: () => _setRoundingMode(mode),
                                    trailing: _roundingMode == mode
                                        ? Icon(CupertinoIcons.check_mark,
                                            size: 18, color: scheme.primary)
                                        : null,
                                  ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox(height: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
