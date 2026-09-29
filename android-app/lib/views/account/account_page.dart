import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cloud/cloud_account.dart';
import '../../core/cloud/cloud_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/settings_ui.dart';
import 'account_widgets.dart';

/// 注销、导出的文案先按「服务端只有账号、会员、用量数据，没有账本」来写
/// （后端 04 §A.4 v1.2）。以后加云备份再改。
const kAccountServerDataNote = '服务器上只保存账号、会员和 AI 用量记录，不保存你的账本。'
    '账本只在这台手机上，退出登录或注销账号都不会删除它。';

/// 账号子页：邮箱、密码、登录设备、导出个人信息、注销、退出登录。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  List<CloudDevice>? _devices;
  String? _devicesError;
  bool _busy = false;
  bool _closing = false;

  CloudAccount get _account => context.read<CloudAccount>();

  @override
  void initState() {
    super.initState();
    _account.loadMe().ignore();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final list = await _account.devices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _devicesError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _devicesError = accountErrorText(error));
    }
  }

  /// 跑一个账号操作：转圈、出错 toast。成功返回 true。
  Future<bool> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showAppToast(context, done);
      return true;
    } catch (error) {
      if (mounted) {
        showAppToast(context, accountErrorText(error),
            icon: CupertinoIcons.exclamationmark_circle);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(CloudDevice device) async {
    final ok = await showConfirmDialog(
      context,
      title: '让「${deviceTitle(device)}」下线？',
      message: '那台设备需要重新登录。它上面的账本不受影响。',
      confirmText: '下线',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await _run(() => _account.revokeDevice(device), done: '已下线')) {
      await _loadDevices();
    }
  }

  Future<void> _revokeOthers() async {
    final ok = await showConfirmDialog(
      context,
      title: '让其他设备全部下线？',
      message: '除了这台手机，其他设备都需要重新登录。',
      confirmText: '全部下线',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await _run(_account.revokeOtherDevices, done: '其他设备已下线')) {
      await _loadDevices();
    }
  }

  Future<void> _export() async {
    await _run(() async {
      final text = await _account.exportData();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'feimiao-account-${now.year}${two(now.month)}${two(now.day)}.json';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(text, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, name: name)],
        text: '肥喵账号个人信息导出（只含账号、会员和用量记录，不含账本）',
      );
    });
  }

  Future<void> _cancelDeletion() async {
    await _run(_account.cancelDeletion, done: '已撤销注销');
  }

  Future<void> _logout() async {
    final ok = await showConfirmDialog(
      context,
      title: '退出登录？',
      message: '账本还在这台手机上，不会被删除。',
      confirmText: '退出',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(_account.logout, done: '已退出登录');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = context.watch<CloudAccount>();
    if (!account.signedIn && !_closing) {
      // 退出、被下线、本机被移除：账号页没有意义了，回到设置页。
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    final me = account.me;
    final deletion = me?.deletion;
    final devices = _devices;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('账号'),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            const SettingsSectionLabel('账号信息'),
            SettingsGroup(children: [
              SettingsRow(
                leading: const Icon(CupertinoIcons.mail),
                title: '邮箱',
                trailing: Text(me?.email ?? '—',
                    style: AppType.trailingValue(scheme)),
              ),
              SettingsRow(
                key: const ValueKey('account-change-email'),
                leading: const Icon(CupertinoIcons.arrow_2_squarepath),
                title: '修改邮箱',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: me == null
                    ? null
                    : () => showAccountSheet<void>(
                          context,
                          _provide(ChangeEmailSheet(currentEmail: me.email)),
                        ),
              ),
              SettingsRow(
                key: const ValueKey('account-password'),
                leading: const Icon(CupertinoIcons.lock),
                title: (me?.hasPassword ?? false) ? '修改密码' : '设置密码',
                subtitle: (me?.hasPassword ?? false) ? null : '设置后可以用邮箱和密码登录',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: me == null
                    ? null
                    : () => showAccountSheet<void>(
                          context,
                          _provide(SetPasswordSheet(hasPassword: me.hasPassword)),
                        ),
              ),
            ]),
            const SettingsSectionLabel('登录设备'),
            if (devices != null && devices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DeviceListGroup(devices: devices, onRevoke: _revoke),
              )
            else
              SettingsGroup(children: [
                SettingsRow(
                  title: _devicesError ?? (devices == null ? '加载中…' : '暂无设备'),
                  onTap: _devicesError == null ? null : _loadDevices,
                ),
              ]),
            if (devices != null && devices.where((d) => !d.isCurrent).isNotEmpty)
              SettingsGroup(children: [
                SettingsRow(
                  key: const ValueKey('account-revoke-others'),
                  title: '让其他设备全部下线',
                  titleColor: AppColors.warning,
                  onTap: _revokeOthers,
                ),
              ]),
            const SettingsSectionLabel('个人信息'),
            SettingsGroup(children: [
              SettingsRow(
                key: const ValueKey('account-export'),
                leading: const Icon(CupertinoIcons.square_arrow_up),
                title: '导出个人信息',
                subtitle: '账号、会员和用量记录（不含账本）',
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: _export,
              ),
              if (deletion != null && deletion.pending)
                SettingsRow(
                  key: const ValueKey('account-cancel-deletion'),
                  leading: const Icon(CupertinoIcons.arrow_uturn_left),
                  title: '撤销注销',
                  subtitle: deletion.deleteAfter == null
                      ? '注销申请处理中'
                      : '账号将在 ${formatAccountDate(deletion.deleteAfter!)} 注销，之前可以撤销',
                  onTap: _cancelDeletion,
                )
              else
                SettingsRow(
                  key: const ValueKey('account-delete'),
                  leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark),
                  title: '注销账号',
                  titleColor: AppColors.warning,
                  onTap: me == null
                      ? null
                      : () => showAccountSheet<void>(
                            context,
                            _provide(const DeleteAccountSheet()),
                          ),
                ),
            ]),
            SettingsGroup(children: [
              SettingsRow(
                key: const ValueKey('account-logout'),
                title: '退出登录',
                titleColor: AppColors.warning,
                onTap: _logout,
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(kAccountServerDataNote, style: AppType.caption(scheme)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _provide(Widget child) => ChangeNotifierProvider<CloudAccount>.value(
        value: _account,
        child: child,
      );
}

/// 修改邮箱：第一步验证当前邮箱，第二步验证新邮箱。
class ChangeEmailSheet extends StatefulWidget {
  const ChangeEmailSheet({super.key, required this.currentEmail});

  final String currentEmail;

  @override
  State<ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<ChangeEmailSheet> {
  final _oldCode = TextEditingController();
  final _newEmail = TextEditingController();
  final _newCode = TextEditingController();
  EmailChangeTicket? _ticket;
  bool _busy = false;
  String? _error;

  CloudAccount get _account => context.read<CloudAccount>();

  @override
  void dispose() {
    _oldCode.dispose();
    _newEmail.dispose();
    _newCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ticket = _ticket;
    if (ticket == null && _oldCode.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    if (ticket != null) {
      if (!_newEmail.text.contains('@')) {
        setState(() => _error = '请填写新邮箱');
        return;
      }
      if (_newCode.text.trim().length != 6) {
        setState(() => _error = '请输入新邮箱收到的 6 位验证码');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (ticket == null) {
        final next = await _account.verifyOldEmail(_oldCode.text.trim());
        if (mounted) setState(() => _ticket = next);
      } else {
        await _account.confirmNewEmail(
            ticket, _newEmail.text.trim(), _newCode.text.trim());
        if (!mounted) return;
        showAppToast(context, '邮箱已修改');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = accountErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    void onError(Object e) => setState(() => _error = accountErrorText(e));
    return AccountFormSheet(
      title: '修改邮箱',
      actionLabel: ticket == null ? '下一步' : '完成',
      onAction: _submit,
      busy: _busy,
      error: _error,
      footnote: ticket == null
          ? '先验证当前邮箱 ${widget.currentEmail}'
          : '验证码会发到新邮箱。修改后用新邮箱登录。',
      children: ticket == null
          ? [
              AccountCodeField(
                key: const ValueKey('change-email-old-code'),
                controller: _oldCode,
                label: '当前邮箱验证码',
                onSend: () => _account.sendCode(OtpPurpose.changeEmailOld),
                onError: onError,
                onSubmitted: (_) => _submit(),
              ),
            ]
          : [
              AccountEmailField(
                controller: _newEmail,
                label: '新邮箱',
                autofocus: true,
              ),
              AccountCodeField(
                key: const ValueKey('change-email-new-code'),
                controller: _newCode,
                label: '新邮箱验证码',
                onSend: () {
                  if (!_newEmail.text.contains('@')) {
                    throw const AccountInputError('请先填写新邮箱');
                  }
                  return _account.sendCode(
                    OtpPurpose.changeEmailNew,
                    email: _newEmail.text.trim(),
                    changeTicket: ticket.ticket,
                  );
                },
                onError: onError,
                onSubmitted: (_) => _submit(),
              ),
            ],
    );
  }
}

/// 设置 / 修改密码：发到当前邮箱的验证码 + 新密码（至少 8 位）。
class SetPasswordSheet extends StatefulWidget {
  const SetPasswordSheet({super.key, required this.hasPassword});

  final bool hasPassword;

  @override
  State<SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<SetPasswordSheet> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = '密码至少 8 位');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<CloudAccount>()
          .setPassword(_code.text.trim(), _password.text);
      if (!mounted) return;
      showAppToast(context, widget.hasPassword ? '密码已修改' : '密码已设置');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = accountErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountFormSheet(
      title: widget.hasPassword ? '修改密码' : '设置密码',
      actionLabel: '保存',
      onAction: _submit,
      busy: _busy,
      error: _error,
      footnote: '保存后其他设备需要重新登录。',
      children: [
        AccountCodeField(
          controller: _code,
          label: '邮箱验证码',
          onSend: () => context.read<CloudAccount>().sendCode(OtpPurpose.setPassword),
          onError: (e) => setState(() => _error = accountErrorText(e)),
        ),
        AccountPasswordField(
          controller: _password,
          label: '新密码',
          hint: '至少 8 位',
          newPassword: true,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// 注销账号：验证码确认 → 进入冷静期，冷静期内可以撤销。
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({super.key});

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: '确定注销账号？',
      message: '会员、剩余时长和 AI 用量记录会在冷静期结束后删除，无法恢复。'
          '冷静期内可以在账号页撤销。',
      confirmText: '注销',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status =
          await context.read<CloudAccount>().requestDeletion(_code.text.trim());
      if (!mounted) return;
      final after = status.deleteAfter;
      showAppToast(
        context,
        after == null ? '已提交注销申请' : '已提交，${formatAccountDate(after)} 前可以撤销',
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = accountErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountFormSheet(
      title: '注销账号',
      actionLabel: '注销',
      onAction: _submit,
      busy: _busy,
      error: _error,
      footnote: kAccountServerDataNote,
      children: [
        AccountCodeField(
          controller: _code,
          label: '邮箱验证码',
          onSend: () =>
              context.read<CloudAccount>().sendCode(OtpPurpose.deleteAccount),
          onError: (e) => setState(() => _error = accountErrorText(e)),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
