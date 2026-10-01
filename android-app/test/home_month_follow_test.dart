// 主页跨月：App 常驻后台从 9 月过到 10 月，回来要自动显示 10 月；
// 用户自己翻到的月份不被打断。
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/home/home_view.dart';

void main() {
  DateTime follow(DateTime shown, DateTime synced, DateTime now) =>
      homeMonthAfterClockChange(shown: shown, syncedNow: synced, now: now);

  test('停在当时的本月：9/30 打开、10/1 回来 → 显示 10 月', () {
    expect(
      follow(DateTime(2026, 9), DateTime(2026, 9, 30, 23, 50),
          DateTime(2026, 10, 1, 8)),
      DateTime(2026, 10),
    );
  });

  test('跨年：12/31 → 1/1 显示新一年 1 月', () {
    expect(
      follow(DateTime(2026, 12), DateTime(2026, 12, 31, 22),
          DateTime(2027, 1, 1, 0, 0, 1)),
      DateTime(2027, 1),
    );
  });

  test('隔了好几个月才回来，也直接到现在这个月', () {
    expect(
      follow(DateTime(2026, 9), DateTime(2026, 9, 10), DateTime(2027, 2, 3)),
      DateTime(2027, 2),
    );
  });

  test('用户自己翻到 7 月：跨月回来仍停在 7 月', () {
    expect(
      follow(DateTime(2026, 7), DateTime(2026, 9, 30), DateTime(2026, 10, 1)),
      DateTime(2026, 7),
    );
  });

  test('同一个月里回到前台：月份不变', () {
    expect(
      follow(DateTime(2026, 10), DateTime(2026, 10, 1, 9),
          DateTime(2026, 10, 1, 21)),
      DateTime(2026, 10),
    );
  });

  test('系统时间被往回调：不会停在未来的月份', () {
    expect(
      follow(DateTime(2026, 8), DateTime(2026, 10, 1), DateTime(2026, 9, 15)),
      DateTime(2026, 8),
    );
    expect(
      follow(DateTime(2026, 10), DateTime(2026, 9, 1), DateTime(2026, 9, 15)),
      DateTime(2026, 9),
    );
  });
}
