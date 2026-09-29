import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cloud/cloud_errors.dart';
import '../../core/cloud/cloud_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

/// 账号相关的错误统一成一句能给用户看的话。
String accountErrorText(Object error) {
  if (error is CloudApiException) return error.message;
  if (error is AccountInputError) return error.message;
  return '出了点问题，请稍后再试';
}

/// 本机就能判断的输入问题（没发请求），比如邮箱格式不对。
class AccountInputError implements Exception {
  const AccountInputError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 账号表单弹层的外壳：`SheetHeader`（✕ 左上、标题居中、操作右上）
/// + 内容 + 错误提示 + 底部脚注。规范 06 §4「表单弹层」。
class AccountFormSheet extends StatelessWidget {
  const AccountFormSheet({
    super.key,
    required this.title,
    required this.children,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.error,
    this.footnote,
  });

  final String title;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final String? error;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: title,
                  actionLabel: actionLabel,
                  onClose: () => Navigator.pop(context),
                  onAction: busy ? null : onAction,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        children[i],
                      ],
                    ],
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: Text(
                      error!,
                      key: const ValueKey('account-form-error'),
                      style: AppType.secondary(scheme)
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                if (footnote != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: Text(footnote!, style: AppType.caption(scheme)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 邮箱输入框。
class AccountEmailField extends StatelessWidget {
  const AccountEmailField({
    super.key,
    required this.controller,
    this.label = '邮箱',
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => AppLabeledField(
        label: label,
        child: TextField(
          key: const ValueKey('account-email'),
          controller: controller,
          autofocus: autofocus,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          maxLength: 254,
          textInputAction: TextInputAction.next,
          decoration: iosInputDecoration(context, hint: 'name@example.com'),
          onSubmitted: onSubmitted,
        ),
      );
}

/// 密码输入框（带显示/隐藏）。
class AccountPasswordField extends StatefulWidget {
  const AccountPasswordField({
    super.key,
    required this.controller,
    this.label = '密码',
    this.hint,
    this.helperText,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final bool newPassword;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AccountPasswordField> createState() => _AccountPasswordFieldState();
}

class _AccountPasswordFieldState extends State<AccountPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppLabeledField(
      label: widget.label,
      helperText: widget.helperText,
      child: TextField(
        key: const ValueKey('account-password'),
        controller: widget.controller,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 128,
        autofillHints: [
          widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
        ],
        textInputAction: TextInputAction.done,
        decoration: iosInputDecoration(context, hint: widget.hint).copyWith(
          suffixIcon: IconButton(
            tooltip: _obscure ? '显示密码' : '隐藏密码',
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: AppTextColor.secondary(scheme),
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

/// 6 位验证码输入框 + 右侧「获取验证码 / N 秒后重发」。
///
/// [onSend] 返回服务端给的重发间隔；抛异常时把错误交给 [onError]。
class AccountCodeField extends StatefulWidget {
  const AccountCodeField({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onError,
    this.label = '验证码',
    this.helperText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final Future<Duration> Function() onSend;
  final ValueChanged<Object> onError;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AccountCodeField> createState() => _AccountCodeFieldState();
}

class _AccountCodeFieldState extends State<AccountCodeField> {
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;
  bool _sentOnce = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _remaining > 0) return;
    setState(() => _sending = true);
    try {
      final wait = await widget.onSend();
      if (!mounted) return;
      _sentOnce = true;
      _startCountdown(wait.inSeconds > 0 ? wait.inSeconds : 60);
    } catch (error) {
      if (!mounted) return;
      if (error is CloudApiException && error.retryAfter != null) {
        _startCountdown(error.retryAfter!.inSeconds);
      }
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
      if (_remaining == 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _remaining > 0
        ? '$_remaining 秒后重发'
        : (_sentOnce ? '重新发送' : '获取验证码');
    return AppLabeledField(
      label: widget.label,
      helperText: widget.helperText,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('account-code'),
              controller: widget.controller,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textInputAction: TextInputAction.done,
              decoration: iosInputDecoration(context, hint: '6 位数字'),
              style: const TextStyle(fontFamily: 'Nunito', letterSpacing: 2),
              onSubmitted: widget.onSubmitted,
            ),
          ),
          const SizedBox(width: 10),
          AppPillButton(
            key: const ValueKey('account-send-code'),
            label: label,
            loading: _sending,
            height: 40,
            onPressed: _remaining > 0 || _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}

/// 登录设备列表：账号页「登录设备」和登录时「设备数已满」共用这一个组件
/// （docs/01 §4 决定只写一个）。
///
/// - [selectable] 为 true 时每行右侧是勾选框（设备数已满时选要下线的）；
/// - 否则每行右侧是「下线」（本机显示「本机」）。
class DeviceListGroup extends StatelessWidget {
  const DeviceListGroup({
    super.key,
    required this.devices,
    this.selectable = false,
    this.selected = const {},
    this.onToggle,
    this.onRevoke,
  });

  final List<CloudDevice> devices;
  final bool selectable;
  final Set<String> selected;
  final ValueChanged<CloudDevice>? onToggle;
  final ValueChanged<CloudDevice>? onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsGroup(
      margin: EdgeInsets.zero,
      children: [
        for (final device in devices)
          SettingsRow(
            key: ValueKey('device-${device.id}'),
            leading: Icon(
              device.platform == 'ios'
                  ? Icons.phone_iphone
                  : Icons.phone_android,
            ),
            title: deviceTitle(device),
            subtitle: deviceSubtitle(device),
            trailing: selectable
                ? AppCheckmark(
                    value: selected.contains(device.id),
                    onChanged: null,
                    interactive: false,
                    semanticLabel: '选择 ${deviceTitle(device)}',
                  )
                : device.isCurrent
                    ? Text('本机', style: AppType.trailingValue(scheme))
                    : TextButton(
                        onPressed: onRevoke == null
                            ? null
                            : () => onRevoke!(device),
                        child: Text(
                          '下线',
                          style: AppType.body(scheme)
                              .copyWith(color: AppColors.warning),
                        ),
                      ),
            onTap: selectable && onToggle != null ? () => onToggle!(device) : null,
          ),
      ],
    );
  }
}

String deviceTitle(CloudDevice device) {
  final model = device.model?.trim();
  if (model != null && model.isNotEmpty) return model;
  return device.platform == 'ios' ? 'iPhone' : '安卓手机';
}

String deviceSubtitle(CloudDevice device) {
  final parts = <String>[
    if (device.lastSeenAt != null) '最近使用 ${formatAccountDate(device.lastSeenAt!)}',
    if (device.lastLocation != null && device.lastLocation!.isNotEmpty)
      device.lastLocation!,
    if (device.appVersion != null && device.appVersion!.isNotEmpty)
      'v${device.appVersion}',
  ];
  return parts.join(' · ');
}

/// 账号页里的日期：今年不带年份。
String formatAccountDate(DateTime time, {DateTime? now}) {
  final t = time.toLocal();
  final today = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final md = '${t.month}月${t.day}日';
  final hm = '${two(t.hour)}:${two(t.minute)}';
  return t.year == today.year ? '$md $hm' : '${t.year}年$md';
}

/// 打开一个账号表单弹层。
Future<T?> showAccountSheet<T>(BuildContext context, Widget sheet) =>
    showBlurSheet<T>(context, radius: 30, child: sheet);
