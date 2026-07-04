import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../theme/app_colors.dart';
import '../views/common/app_sheet.dart';
import 'pressable_scale.dart';
import 'settings_ui.dart';

/// 全局日历选择器（对齐 iOS/咔皮体验，替代难用的系统 showDatePicker）。
///
/// - 月网格视图：左上「2026年7月 ⌄」点开切换到年月滚轮快速跳转；右侧 ‹ › 翻月；
///   顶部「回今天」一键回到今天；底部「确认」返回所选日期。
/// - 同类功能同一种设计：所有需要选单个日期/日期区间的地方都走这里。
///
/// 用法：
/// ```dart
/// final d = await showAppDatePicker(context, initial: DateTime.now(), title: '开始时间');
/// ```
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  String title = '选择日期',
}) {
  final firstDate = _dayOnly(first ?? DateTime(2000));
  final lastDate = _dayOnly(last ?? DateTime(2100, 12, 31));
  var init = _dayOnly(initial);
  if (init.isBefore(firstDate)) init = firstDate;
  if (init.isAfter(lastDate)) init = lastDate;
  return showBlurSheet<DateTime>(
    context,
    child: _AppDatePickerSheet(
      initial: init,
      first: firstDate,
      last: lastDate,
      title: title,
    ),
  );
}

/// 日期区间选择：先选开始（标题「开始时间」），再选结束（标题「结束时间」，
/// 不早于开始）。任一步取消则整体返回 null。search / 预算等区间选择走它。
Future<DateTimeRange?> showAppDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  DateTime? first,
  DateTime? last,
}) async {
  final now = DateTime.now();
  final start = await showAppDatePicker(
    context,
    initial: initial?.start ?? now.subtract(const Duration(days: 29)),
    first: first,
    last: last,
    title: '开始时间',
  );
  if (start == null || !context.mounted) return null;
  final end = await showAppDatePicker(
    context,
    initial: initial?.end != null && !initial!.end.isBefore(start)
        ? initial.end
        : start,
    first: start,
    last: last,
    title: '结束时间',
  );
  if (end == null) return null;
  return DateTimeRange(start: start, end: end);
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime first;
  final DateTime last;
  final String title;

  const _AppDatePickerSheet({
    required this.initial,
    required this.first,
    required this.last,
    required this.title,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late DateTime _selected = widget.initial;
  late DateTime _visibleMonth =
      DateTime(widget.initial.year, widget.initial.month);
  bool _wheel = false;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _disabled(DateTime d) =>
      d.isBefore(widget.first) || d.isAfter(widget.last);

  bool _canShift(int delta) {
    final m = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    // 目标月只要和 [first,last] 有交集就允许翻。
    final monthEnd = DateTime(m.year, m.month + 1, 0);
    return !monthEnd.isBefore(widget.first) &&
        !m.isAfter(DateTime(widget.last.year, widget.last.month));
  }

  void _shift(int delta) {
    if (!_canShift(delta)) return;
    Haptics.selection();
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  void _goToday() {
    final now = _dayOnly(DateTime.now());
    if (_disabled(now)) return;
    setState(() {
      _selected = now;
      _visibleMonth = DateTime(now.year, now.month);
      _wheel = false;
    });
  }

  void _pickDay(DateTime d) {
    if (_disabled(d)) return;
    setState(() => _selected = d);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 抓手
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline(scheme, strength: 1.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题行：开始时间 / 结束时间 ... 回今天
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Row(
              children: [
                Text(widget.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const Spacer(),
                PressableScale(
                  onPressed: _goToday,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('回今天',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: scheme.primary)),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          // 月份标题行：2026年7月 ⌄ ... ‹ ›
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
            child: Row(
              children: [
                PressableScale(
                  onPressed: () => setState(() => _wheel = !_wheel),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_visibleMonth.year}年${_visibleMonth.month}月',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _wheel ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(CupertinoIcons.chevron_down,
                            size: 15, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!_wheel) ...[
                  _NavArrow(
                    icon: CupertinoIcons.chevron_left,
                    enabled: _canShift(-1),
                    onTap: () => _shift(-1),
                  ),
                  const SizedBox(width: 4),
                  _NavArrow(
                    icon: CupertinoIcons.chevron_right,
                    enabled: _canShift(1),
                    onTap: () => _shift(1),
                  ),
                ],
              ],
            ),
          ),
          // 主体：月网格 or 年月滚轮
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _wheel ? _buildWheel(scheme) : _buildGrid(scheme),
          ),
          // 确认
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: PressableScale(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('确认',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 月网格（图一）──────────────────────────────────────────────────────
  Widget _buildGrid(ColorScheme scheme) {
    final y = _visibleMonth.year;
    final m = _visibleMonth.month;
    final firstWeekday = DateTime(y, m).weekday % 7; // 周日=0 起（对齐 iOS）
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final today = _dayOnly(DateTime.now());

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final d = DateTime(y, m, day);
      final selected = _sameDay(d, _selected);
      final isToday = _sameDay(d, today);
      final disabled = _disabled(d);
      cells.add(_DayCell(
        day: day,
        selected: selected,
        isToday: isToday,
        disabled: disabled,
        onTap: () => _pickDay(d),
      ));
    }

    return Padding(
      key: const ValueKey('grid'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text('周$w',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.05,
            children: cells,
          ),
        ],
      ),
    );
  }

  // ── 年月滚轮（图二）─────────────────────────────────────────────────────
  Widget _buildWheel(ColorScheme scheme) {
    final years = [
      for (int yy = widget.first.year; yy <= widget.last.year; yy++) yy
    ];
    return SizedBox(
      key: const ValueKey('wheel'),
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                  initialItem: years.indexOf(_visibleMonth.year)),
              itemExtent: 40,
              onSelectedItemChanged: (i) => _onWheel(years[i], null),
              children: [
                for (final yy in years)
                  Center(
                      child: Text('$yy年',
                          style: TextStyle(color: scheme.onSurface))),
              ],
            ),
          ),
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                  initialItem: _visibleMonth.month - 1),
              itemExtent: 40,
              onSelectedItemChanged: (i) => _onWheel(null, i + 1),
              children: [
                for (int mm = 1; mm <= 12; mm++)
                  Center(
                      child: Text('$mm月',
                          style: TextStyle(color: scheme.onSurface))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onWheel(int? year, int? month) {
    final y = year ?? _visibleMonth.year;
    final m = month ?? _visibleMonth.month;
    setState(() {
      _visibleMonth = DateTime(y, m);
      // 选中日跟随到该月（超出该月天数则取月末），并夹到 [first,last]。
      final dim = DateTime(y, m + 1, 0).day;
      var d = DateTime(y, m, _selected.day > dim ? dim : _selected.day);
      if (d.isBefore(widget.first)) d = widget.first;
      if (d.isAfter(widget.last)) d = widget.last;
      _selected = d;
    });
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavArrow(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        child: Icon(icon,
            size: 20,
            color: enabled ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool selected;
  final bool isToday;
  final bool disabled;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color textColor;
    if (disabled) {
      textColor = scheme.onSurfaceVariant.withValues(alpha: 0.35);
    } else if (selected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = scheme.primary;
    } else {
      textColor = scheme.onSurface;
    }
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text('$day',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      selected || isToday ? FontWeight.w600 : FontWeight.w400,
                  color: textColor)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 年 / 月 / 周 滚轮选择（统计页 周/月/年 维度切换用；对齐日期轮动样式标准）
// ─────────────────────────────────────────────────────────────────────────────

DateTime _mondayOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 某年的各周（周一为起点，起始日落在该年内的周）。
List<DateTime> _weeksOfYear(int y) {
  var m = _mondayOfWeek(DateTime(y, 1, 1));
  final end = DateTime(y, 12, 31);
  final res = <DateTime>[];
  while (!m.isAfter(end)) {
    res.add(m);
    m = m.add(const Duration(days: 7));
  }
  return res;
}

/// 月份滚轮：年 + 月，返回 DateTime(年, 月, 1)。
Future<DateTime?> showAppMonthPicker(BuildContext context,
    {required DateTime initial, DateTime? last}) {
  return showBlurSheet<DateTime>(context,
      child: _MonthPickerSheet(
          initial: DateTime(initial.year, initial.month),
          last: last ?? DateTime(2100, 12)));
}

/// 年份滚轮，返回年份。
Future<int?> showAppYearPicker(BuildContext context,
    {required int initial, int? lastYear}) {
  return showBlurSheet<int>(context,
      child: _YearPickerSheet(initial: initial, lastYear: lastYear ?? 2100));
}

/// 周滚轮：先选年、再选第几周（含起始日期），返回该周周一。
Future<DateTime?> showAppWeekPicker(BuildContext context,
    {required DateTime initialWeekStart, DateTime? last}) {
  return showBlurSheet<DateTime>(context,
      child: _WeekPickerSheet(
          initial: _mondayOfWeek(initialWeekStart),
          last: last ?? DateTime(2100, 12, 31)));
}

Widget _wheel({
  required int count,
  required int initialItem,
  required ValueChanged<int> onChanged,
  required IndexedWidgetBuilder itemBuilder,
  Key? key,
}) {
  return CupertinoPicker.builder(
    key: key,
    scrollController: FixedExtentScrollController(initialItem: initialItem),
    itemExtent: 40,
    onSelectedItemChanged: onChanged,
    childCount: count,
    itemBuilder: itemBuilder,
  );
}

class _MonthPickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime last;
  const _MonthPickerSheet({required this.initial, required this.last});
  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  static const _firstYear = 2015;
  late int _y = widget.initial.year.clamp(_firstYear, widget.last.year);
  late int _m = widget.initial.month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = [for (int y = _firstYear; y <= widget.last.year; y++) y];
    TextStyle st() => TextStyle(color: scheme.onSurface);
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '选择月份',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: () {
              var y = _y, m = _m;
              if (DateTime(y, m)
                  .isAfter(DateTime(widget.last.year, widget.last.month))) {
                y = widget.last.year;
                m = widget.last.month;
              }
              Navigator.pop(context, DateTime(y, m));
            },
          ),
          SizedBox(
            height: 200,
            child: Row(children: [
              Expanded(
                child: _wheel(
                  count: years.length,
                  initialItem: years.indexOf(_y),
                  onChanged: (i) => _y = years[i],
                  itemBuilder: (_, i) =>
                      Center(child: Text('${years[i]}年', style: st())),
                ),
              ),
              Expanded(
                child: _wheel(
                  count: 12,
                  initialItem: _m - 1,
                  onChanged: (i) => _m = i + 1,
                  itemBuilder: (_, i) =>
                      Center(child: Text('${i + 1}月', style: st())),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _YearPickerSheet extends StatefulWidget {
  final int initial;
  final int lastYear;
  const _YearPickerSheet({required this.initial, required this.lastYear});
  @override
  State<_YearPickerSheet> createState() => _YearPickerSheetState();
}

class _YearPickerSheetState extends State<_YearPickerSheet> {
  static const _firstYear = 2015;
  late int _y = widget.initial.clamp(_firstYear, widget.lastYear);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = [for (int y = _firstYear; y <= widget.lastYear; y++) y];
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '选择年份',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: () => Navigator.pop(context, _y),
          ),
          SizedBox(
            height: 200,
            child: _wheel(
              count: years.length,
              initialItem: years.indexOf(_y),
              onChanged: (i) => _y = years[i],
              itemBuilder: (_, i) => Center(
                  child: Text('${years[i]}年',
                      style: TextStyle(color: scheme.onSurface))),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _WeekPickerSheet extends StatefulWidget {
  final DateTime initial; // 该周周一
  final DateTime last;
  const _WeekPickerSheet({required this.initial, required this.last});
  @override
  State<_WeekPickerSheet> createState() => _WeekPickerSheetState();
}

class _WeekPickerSheetState extends State<_WeekPickerSheet> {
  static const _firstYear = 2015;
  late int _y = widget.initial.year.clamp(_firstYear, widget.last.year);
  late List<DateTime> _weeks = _weeksOfYear(_y);
  late int _wIdx = _weeks
      .indexWhere((w) => !w.isBefore(widget.initial))
      .clamp(0, _weeks.length - 1);

  String _label(int i) {
    final w = _weeks[i];
    return '第${i + 1}周（${w.month}/${w.day}起）';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = [for (int y = _firstYear; y <= widget.last.year; y++) y];
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '选择周',
            onClose: () => Navigator.pop(context),
            actionLabel: '确认',
            onAction: () {
              var d = _weeks[_wIdx.clamp(0, _weeks.length - 1)];
              if (d.isAfter(widget.last)) d = _mondayOfWeek(widget.last);
              Navigator.pop(context, d);
            },
          ),
          SizedBox(
            height: 200,
            child: Row(children: [
              SizedBox(
                width: 96,
                child: _wheel(
                  count: years.length,
                  initialItem: years.indexOf(_y),
                  onChanged: (i) => setState(() {
                    _y = years[i];
                    _weeks = _weeksOfYear(_y);
                    if (_wIdx >= _weeks.length) _wIdx = _weeks.length - 1;
                  }),
                  itemBuilder: (_, i) => Center(
                      child: Text('${years[i]}年',
                          style: TextStyle(color: scheme.onSurface))),
                ),
              ),
              Expanded(
                child: _wheel(
                  key: ValueKey(_y),
                  count: _weeks.length,
                  initialItem: _wIdx.clamp(0, _weeks.length - 1),
                  onChanged: (i) => _wIdx = i,
                  itemBuilder: (_, i) => Center(
                      child: Text(_label(i),
                          style: TextStyle(color: scheme.onSurface))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
