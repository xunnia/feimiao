import 'package:flutter/material.dart';

import '../../core/auto_record.dart';
import '../../theme/app_colors.dart';

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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final on = await AutoRecord.isEnabled();
    if (mounted) setState(() {
      _enabled = on;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.appBg(scheme),
      appBar: AppBar(
        title: const Text('自动记账'),
        backgroundColor: AppColors.appBg(scheme),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card(scheme),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _enabled ? Icons.check_circle : Icons.notifications_active,
                  color: _enabled ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _loading
                        ? '检查中…'
                        : (_enabled ? '已开启：付完款喵会自动盯着' : '未开启'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '开启后，微信 / 支付宝有支付通知时，喵会悄悄记下来；'
            '你下次打开肥喵，一键就能把它们记进账本（不会乱记，都要你确认）。',
            style: TextStyle(
                fontSize: 13, height: 1.6, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: AutoRecord.openSettings,
              child: Text(_enabled ? '去系统设置查看' : '去开启「通知使用权」'),
            ),
          ),
          const SizedBox(height: 24),
          _tip(scheme, '①', '在弹出的系统列表里找到「肥喵记账」，打开开关。'),
          _tip(scheme, '②', '把肥喵加入「电池白名单 / 允许自启动」，否则后台可能被系统杀掉、漏记。'),
          _tip(scheme, '③', '只读取支付/收付款通知用于记账，数据全在你手机本地，不上传。'),
        ],
      ),
    );
  }

  Widget _tip(ColorScheme scheme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
