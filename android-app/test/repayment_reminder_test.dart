import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/repayment_reminder.dart';

void main() {
  group('planRepaymentReminders', () {
    test('未来还款日：前一天20:00+当天10:00 两条都排', () {
      final now = DateTime(2026, 7, 1, 9);
      final items = planRepaymentReminders(
        dues: [
          (profileId: 1, accountLabel: '招商信用卡', dueDate: DateTime(2026, 7, 10)),
        ],
        now: now,
      );
      expect(items, hasLength(2));
      expect(items[0].scheduledAt, DateTime(2026, 7, 9, 20));
      expect(items[0].isDayBefore, isTrue);
      expect(items[1].scheduledAt, DateTime(2026, 7, 10, 10));
      expect(items[1].isDayBefore, isFalse);
    });

    test('前一天20:00已过、当天10:00未到：只排当天那条', () {
      final now = DateTime(2026, 7, 9, 21); // 前一天晚上9点，20点已过
      final items = planRepaymentReminders(
        dues: [
          (profileId: 1, accountLabel: '招商信用卡', dueDate: DateTime(2026, 7, 10)),
        ],
        now: now,
      );
      expect(items, hasLength(1));
      expect(items.single.isDayBefore, isFalse);
      expect(items.single.scheduledAt, DateTime(2026, 7, 10, 10));
    });

    test('两个时刻都已过（还款日当天上午10点后）：一条都不排', () {
      final now = DateTime(2026, 7, 10, 11); // 还款日当天上午11点，10点已过
      final items = planRepaymentReminders(
        dues: [
          (profileId: 1, accountLabel: '招商信用卡', dueDate: DateTime(2026, 7, 10)),
        ],
        now: now,
      );
      expect(items, isEmpty);
    });

    test('逾期很久的一次性借入到期日：不补发过去的提醒', () {
      final now = DateTime(2026, 7, 27);
      final items = planRepaymentReminders(
        dues: [
          (profileId: 5, accountLabel: '借入·老王', dueDate: DateTime(2026, 5, 1)),
        ],
        now: now,
      );
      expect(items, isEmpty);
    });

    test('多个档案各自独立排，profileId/accountLabel 不串号', () {
      final now = DateTime(2026, 7, 1);
      final items = planRepaymentReminders(
        dues: [
          (profileId: 1, accountLabel: '招商信用卡', dueDate: DateTime(2026, 7, 5)),
          (profileId: 2, accountLabel: '房贷账户', dueDate: DateTime(2026, 7, 20)),
        ],
        now: now,
      );
      expect(items, hasLength(4));
      final forProfile1 = items.where((i) => i.profileId == 1);
      final forProfile2 = items.where((i) => i.profileId == 2);
      expect(forProfile1, hasLength(2));
      expect(forProfile2, hasLength(2));
      expect(forProfile1.every((i) => i.accountLabel == '招商信用卡'), isTrue);
      expect(forProfile2.every((i) => i.accountLabel == '房贷账户'), isTrue);
    });

    test('恰好等于候选时刻不算"未来"，不排（边界含now本身不发）', () {
      final now = DateTime(2026, 7, 10, 10); // 恰好等于当天10点
      final items = planRepaymentReminders(
        dues: [
          (profileId: 1, accountLabel: '招商信用卡', dueDate: DateTime(2026, 7, 10)),
        ],
        now: now,
      );
      expect(items, isEmpty);
    });
  });

  group('RepaymentReminderItem', () {
    test('title/body 文案符合规格', () {
      final item = RepaymentReminderItem(
        profileId: 3,
        accountLabel: '招商信用卡',
        dueDate: DateTime(2026, 7, 10),
        scheduledAt: DateTime(2026, 7, 9, 20),
        isDayBefore: true,
      );
      expect(item.title, '肥喵提醒还款');
      expect(item.body, '招商信用卡 账户 07-10 要还款啦喵');
    });

    test('notificationId 同档案两个时段不同，不同档案不冲突', () {
      final dayBefore = RepaymentReminderItem(
        profileId: 7,
        accountLabel: 'x',
        dueDate: DateTime(2026, 7, 10),
        scheduledAt: DateTime(2026, 7, 9, 20),
        isDayBefore: true,
      );
      final dayOf = RepaymentReminderItem(
        profileId: 7,
        accountLabel: 'x',
        dueDate: DateTime(2026, 7, 10),
        scheduledAt: DateTime(2026, 7, 10, 10),
        isDayBefore: false,
      );
      final otherProfile = RepaymentReminderItem(
        profileId: 8,
        accountLabel: 'y',
        dueDate: DateTime(2026, 7, 10),
        scheduledAt: DateTime(2026, 7, 9, 20),
        isDayBefore: true,
      );
      expect(dayBefore.notificationId, isNot(dayOf.notificationId));
      expect(dayBefore.notificationId, isNot(otherProfile.notificationId));
    });
  });
}
