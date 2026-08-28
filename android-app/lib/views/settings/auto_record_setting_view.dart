import 'package:flutter/material.dart';

import '../../core/auto_record.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';

/// 自动记账设置：开启「通知使用权」+ 保活引导 + 状态显示。
class AutoRecordSettingView extends StatefulWidget {
  const AutoRecordSettingView({super.key});

  @override
  State<AutoRecordSettingView> createState() => _AutoRecordSettingViewState();
}

class _AutoRecordSettingViewState extends State<AutoRecordSettingView>
    with WidgetsBindingObserver {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final on = await AutoRecord.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = on;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('自动记账'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                leading: Icon(
                  _enabled
                      ? Icons.check_circle_outline
                      : Icons.notifications_none_rounded,
                  color: _enabled
                      ? scheme.primary
                      : AppTextColor.secondary(scheme),
                ),
                title: _loading ? '正在检查' : (_enabled ? '已开启' : '未开启'),
                trailing: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: scheme.primary,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 18),
            child: Text(
              '开启后，肥喵会识别微信和支付宝的收付款通知。再次打开应用时，确认后即可入账。',
              style: AppType.secondary(scheme),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: AppPillButton(
                label: _enabled ? '打开系统设置' : '开启通知使用权',
                onPressed: AutoRecord.openSettings,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Text(
              '在系统列表中找到「肥喵记账」并允许通知使用权。为减少漏记，也建议允许应用在后台运行。\n\n'
              '肥喵只读取收付款通知，每笔账都由你确认后保存，数据留在本机。',
              style: AppType.caption(scheme),
            ),
          ),
        ],
      ),
    );
  }
}
