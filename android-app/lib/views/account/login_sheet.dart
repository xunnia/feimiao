import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cloud/cloud_account.dart';
import '../../core/cloud/cloud_errors.dart';
import '../../core/cloud/cloud_models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/sliding_segment.dart';
import 'account_widgets.dart';

/// 打开登录/注册弹层。返回 true 表示登录成功。
Future<bool> showLoginSheet(BuildContext context) async {
  final account = context.read<CloudAccount>();
  final ok = await showAccountSheet<bool>(
    context,
    ChangeNotifierProvider<CloudAccount>.value(
      value: account,
      child: const LoginSheet(),
    ),
  );
  return ok ?? false;
}

enum LoginMethod { code, password }

/// 登录/注册：验证码和密码两种方式直接并排（不藏密码登录）。
/// 邮箱第一次用验证码登录就是注册。设备数已满时同一个弹层切到「选设备下线」。
class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  LoginMethod _method = LoginMethod.code;
  bool _busy = false;
  String? _error;

  // 设备数已满时的第二步
  DeviceLimitInfo? _limit;
  final Set<String> _revoke = {};

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  CloudAccount get _account => context.read<CloudAccount>();

  String get _emailText => _email.text.trim();

  bool _emailLooksValid() {
    final e = _emailText;
    final at = e.indexOf('@');
    return at > 0 && at < e.length - 1 && !e.contains(' ');
  }

  Future<Duration> _sendCode() {
    if (!_emailLooksValid()) {
      throw const AccountInputError('请先填写正确的邮箱');
    }
    setState(() => _error = null);
    return _account.sendLoginCode(_emailText);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_emailLooksValid()) {
      setState(() => _error = '请先填写正确的邮箱');
      return;
    }
    if (_method == LoginMethod.code && _code.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    if (_method == LoginMethod.password && _password.text.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    await _run(() => _method == LoginMethod.code
        ? _account.loginWithCode(_emailText, _code.text.trim())
        : _account.loginWithPassword(_emailText, _password.text));
  }

  Future<void> _resolve() async {
    final limit = _limit;
    if (_busy || limit == null) return;
    if (_revoke.isEmpty) {
      setState(() => _error = '至少选一台设备下线');
      return;
    }
    await _run(() => _account.resolveDeviceLimit(limit, _revoke.toList()));
  }

  Future<void> _run(Future<LoginOutcome> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await call();
      if (!mounted) return;
      switch (outcome) {
        case LoginSucceeded(:final isNewUser):
          showAppToast(context, isNewUser ? '注册成功' : '登录成功');
          Navigator.pop(context, true);
        case LoginNeedsDeviceChoice(:final info):
          setState(() {
            _limit = info;
            _revoke.clear();
          });
      }
    } on CloudApiException catch (error) {
      if (!mounted) return;
      if (error.code == CloudErrorCode.loginTicketExpired) {
        // 选设备太久，票据过期：回到登录第一步重新来。
        setState(() {
          _limit = null;
          _revoke.clear();
          _code.clear();
          _error = '等待时间太久，请重新登录';
        });
      } else {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) setState(() => _error = accountErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limit = _limit;
    if (limit != null) return _buildDeviceChoice(limit);
    return AccountFormSheet(
      title: '登录 / 注册',
      actionLabel: '登录',
      onAction: _submit,
      busy: _busy,
      error: _error,
      footnote: '账本只存在这台手机上，登录不会上传账单。'
          '第一次用验证码登录会自动注册。',
      children: [
        SlidingSegment<LoginMethod>(
          key: const ValueKey('login-method'),
          items: const [
            (LoginMethod.code, '验证码'),
            (LoginMethod.password, '密码'),
          ],
          value: _method,
          onChanged: (m) => setState(() {
            _method = m;
            _error = null;
          }),
        ),
        AccountEmailField(controller: _email, autofocus: true),
        if (_method == LoginMethod.code)
          AccountCodeField(
            controller: _code,
            onSend: _sendCode,
            onError: (e) => setState(() => _error = accountErrorText(e)),
            onSubmitted: (_) => _submit(),
          )
        else
          AccountPasswordField(
            controller: _password,
            onSubmitted: (_) => _submit(),
          ),
      ],
    );
  }

  Widget _buildDeviceChoice(DeviceLimitInfo limit) {
    final scheme = Theme.of(context).colorScheme;
    return AccountFormSheet(
      title: '设备数已满',
      actionLabel: '继续',
      onAction: _resolve,
      busy: _busy,
      error: _error,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '这个账号最多同时登录 ${limit.maxDevices} 台设备。'
            '选一台让它下线，这台手机就能登录。',
            style: AppType.secondary(scheme),
          ),
        ),
        DeviceListGroup(
          devices: limit.devices,
          selectable: true,
          selected: _revoke,
          onToggle: (d) => setState(() {
            _error = null;
            if (!_revoke.remove(d.id)) _revoke.add(d.id);
          }),
        ),
      ],
    );
  }
}
