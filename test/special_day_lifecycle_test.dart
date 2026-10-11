import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/calendar/calendar_models.dart';
import 'package:allone/features/calendar/special_day_lifecycle.dart';

/// 倒数日生命周期测试：
/// ①单次项「当天不算、次日才过期」；②每年重复项推进到下一次且保住「第 N 周年」；
/// ③归档 / 恢复 / 彻底删除 / 回收站排序；④平年 2 月 29 日不再退化成「今天」。
void main() {
  const today = '2026-10-11';

  SpecialDay day(
    String date, {
    String id = 'x',
    String name = '测试',
    bool yearly = false,
    bool archived = false,
    String? originDate,
    String? archivedAt,
  }) => SpecialDay(
    id: id,
    date: date,
    name: name,
    originDate: originDate,
    repeatYearly: yearly,
    archived: archived,
    archivedAt: archivedAt,
  );

  group('倒数日 - 过期判定（单次项）', () {
    test('昨天已过期、今天不算、明天没过', () {
      expect(day('2026-10-10').isExpiredOn(today), isTrue);
      expect(day('2026-10-11').isExpiredOn(today), isFalse); // 当天仍是「今天」
      expect(day('2026-10-12').isExpiredOn(today), isFalse);
    });

    test('每年重复项永远不会「过期」', () {
      expect(day('2000-03-12', yearly: true).isExpiredOn(today), isFalse);
    });

    test('已归档的不再重复计入待归档', () {
      final s = day('2026-10-10', archived: true, archivedAt: today);
      expect(s.isExpiredOn(today), isFalse);
      expect(SpecialDayLifecycle.expiredOneOffs([s], today), isEmpty);
    });

    test('待归档清单：只含过期的单次项，按日期升序', () {
      final list = [
        day('2026-10-09', id: 'b', name: 'B'),
        day('2026-10-01', id: 'a', name: 'A'),
        day('2026-10-12', id: 'c', name: 'C'),
        day('2026-10-11', id: 'd', name: 'D'),
        day('2000-03-12', id: 'e', yearly: true),
      ];
      final expired = SpecialDayLifecycle.expiredOneOffs(list, today);
      expect(expired.map((e) => e.id).toList(), ['a', 'b']);
    });
  });

  group('倒数日 - 重复项自动推进到下一次', () {
    test('已经过了 → 日期改到明年，原始日期被保留，周年数不变', () {
      final s = day('2000-03-12', name: '生日', yearly: true);
      final moved = s.advancedTo(today);
      expect(moved.date, '2027-03-12');
      expect(moved.originDate, '2000-03-12');
      expect(moved.anniversaryYears(today), 27);
      // 未推进前算出来的周年数必须一致（推进不能改变年纪念日语义）
      expect(s.anniversaryYears(today), 27);
    });

    test('存的是旧年份、但今年那次还没到 → 对齐到今年那一次', () {
      final moved = day('2000-12-25', yearly: true).advancedTo(today);
      expect(moved.date, '2026-12-25');
      expect(moved.originDate, '2000-12-25');
      expect(moved.daysFrom(today), greaterThan(0));
    });

    test('已经是下一次（今年还没到）→ 不动，也不写原始日期', () {
      final moved = day('2026-12-25', yearly: true).advancedTo(today);
      expect(moved.date, '2026-12-25');
      expect(moved.originDate, isNull);
    });

    test('正好是今天 → 对齐到今天，倒数显示「今天」', () {
      final s = day('2000-10-11', yearly: true);
      final moved = s.advancedTo(today);
      expect(moved.date, '2026-10-11');
      expect(moved.originDate, '2000-10-11');
      expect(moved.daysFrom(today), 0);
      expect(moved.countdownLabel(today), '今天');
      expect(moved.anniversaryYears(today), 26);
    });

    test('推进是幂等的（多次启动不会反复改数据）', () {
      final once = day('2000-03-12', yearly: true).advancedTo(today);
      final twice = once.advancedTo(today);
      expect(twice.date, once.date);
      expect(twice.originDate, '2000-03-12');
      expect(SpecialDayLifecycle.changed([once], [twice]), isFalse);
    });

    test('单次项不会被推进（它该走归档那条路）', () {
      expect(day('2026-10-01').advancedTo(today).date, '2026-10-01');
    });

    test('列表级推进：只动重复项，且能判断「有没有变化」', () {
      final list = [
        day('2026-10-01', id: 'one'),
        day('2000-03-12', id: 'passed', yearly: true),
        day('2026-12-25', id: 'future', yearly: true),
      ];
      final next = SpecialDayLifecycle.advanceRecurring(list, today);
      expect(next[0].date, '2026-10-01');
      expect(next[1].date, '2027-03-12');
      expect(next[2].date, '2026-12-25');
      expect(SpecialDayLifecycle.changed(list, next), isTrue);
      // 再跑一次应该「无变化」→ 不写盘
      final again = SpecialDayLifecycle.advanceRecurring(next, today);
      expect(SpecialDayLifecycle.changed(next, again), isFalse);
    });
  });

  group('倒数日 - 回收站', () {
    test('归档：写入归档标记与归档日期，不碰其它条目', () {
      final list = [day('2026-10-01', id: 'a'), day('2026-10-02', id: 'b')];
      final out = SpecialDayLifecycle.archive(list, ['a'], today);
      final a = out.firstWhere((e) => e.id == 'a');
      final b = out.firstWhere((e) => e.id == 'b');
      expect(a.archived, isTrue);
      expect(a.archivedAt, today);
      expect(b.archived, isFalse);
    });

    test('归档不会动重复项，也不认识的 id 不影响任何条目', () {
      final list = [day('2000-03-12', id: 'r', yearly: true)];
      final out = SpecialDayLifecycle.archive(list, ['r', 'nope'], today);
      expect(out.single.archived, isFalse);
    });

    test('恢复：清掉归档标记与归档日期', () {
      final list = [
        day('2026-10-01', id: 'a', archived: true, archivedAt: '2026-10-05'),
      ];
      final out = SpecialDayLifecycle.restore(list, 'a');
      expect(out.single.archived, isFalse);
      expect(out.single.archivedAt, isNull);
      expect(out.single.date, '2026-10-01'); // 日期不变
    });

    test('回收站排序：最近归档的在前，活动项不在其中', () {
      final list = [
        day('2026-09-01', id: 'old', archived: true, archivedAt: '2026-09-02'),
        day('2026-10-01', id: 'new', archived: true, archivedAt: '2026-10-09'),
        day('2026-10-10', id: 'live'),
      ];
      expect(SpecialDayLifecycle.trashed(list).map((e) => e.id).toList(), [
        'new',
        'old',
      ]);
    });

    test('彻底删除 / 清空回收站', () {
      final list = [day('2026-10-01', id: 'a'), day('2026-10-02', id: 'b')];
      expect(SpecialDayLifecycle.remove(list, 'a').map((e) => e.id), ['b']);
      expect(SpecialDayLifecycle.removeAll(list, ['a', 'b']), isEmpty);
    });
  });

  group('倒数日 - 平年 2 月 29 日', () {
    test('平年顺延到 2/28，不会退化成「今天」', () {
      final s = day('2000-02-29', yearly: true);
      expect(s.nextDate('2027-01-01'), '2027-02-28');
      expect(s.daysFrom('2027-01-01'), 58);
      expect(s.countdownLabel('2027-01-01'), '还有 58 天');
    });

    test('闰年仍是 2/29', () {
      final s = day('2000-02-29', yearly: true);
      expect(s.nextDate('2028-01-01'), '2028-02-29');
    });

    test('2/29 当天算今天，次日滚到下一次（下一年是平年就落 2/28）', () {
      final s = day('2000-02-29', yearly: true);
      expect(s.daysFrom('2028-02-29'), 0);
      expect(s.countdownLabel('2028-02-29'), '今天');
      expect(s.nextDate('2028-03-01'), '2029-02-28');
    });

    test('旧数据的 2/29 也一样能推进', () {
      final moved = day('2000-02-29', yearly: true).advancedTo('2027-03-01');
      expect(moved.date, '2028-02-29');
      expect(moved.originDate, '2000-02-29');
    });
  });
}
