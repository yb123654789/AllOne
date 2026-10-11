import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/calendar/calendar_models.dart';

/// 特殊日子 / 倒数日的纯逻辑测试：
/// 「按时间排列、不怕忘」的核心就是这里的 occursOn / daysFrom / nextDate。
void main() {
  const today = '2026-10-07';

  SpecialDay day(
    String date, {
    String name = '测试',
    bool yearly = false,
    String color = '#E5484D',
  }) => SpecialDay(
    id: 'x',
    date: date,
    name: name,
    color: color,
    repeatYearly: yearly,
  );

  group('特殊日子 - 命中的日期', () {
    test('不重复：只有当天命中', () {
      final s = day('2026-10-07');
      expect(s.occursOn('2026-10-07'), isTrue);
      expect(s.occursOn('2026-10-08'), isFalse);
      expect(s.occursOn('2027-10-07'), isFalse);
    });

    test('每年重复：每年同月同日都命中', () {
      final s = day('1998-03-12', yearly: true);
      expect(s.occursOn('2026-03-12'), isTrue);
      expect(s.occursOn('2030-03-12'), isTrue);
      expect(s.occursOn('2026-03-13'), isFalse);
    });

    test('非法日期不崩', () {
      expect(day('').occursOn('2026-10-07'), isFalse);
      expect(day('2026-10-07').occursOn(''), isFalse);
    });

    test('月份归属（当年视图统计用）', () {
      expect(day('2026-05-01').inMonth('2026-05'), isTrue);
      expect(day('2026-05-01').inMonth('2027-05'), isFalse);
      expect(day('1998-03-12', yearly: true).inMonth('2031-03'), isTrue);
      expect(day('1998-03-12', yearly: true).inMonth('2031-04'), isFalse);
    });
  });

  group('特殊日子 - 倒数', () {
    test('今天 / 未来 / 过去 的天数', () {
      expect(day('2026-10-07').daysFrom(today), 0);
      expect(day('2026-10-10').daysFrom(today), 3);
      expect(day('2026-10-01').daysFrom(today), -6);
    });

    test('倒数文案', () {
      expect(day('2026-10-07').countdownLabel(today), '今天');
      expect(day('2026-10-10').countdownLabel(today), '还有 3 天');
      expect(day('2026-10-01').countdownLabel(today), '已过 6 天');
    });

    test('每年重复：今年的还没到就用今年，已经过了就用明年', () {
      final later = day('1998-12-25', yearly: true); // 12-25 尚未到
      expect(later.nextDate(today), '2026-12-25');
      expect(later.daysFrom(today), greaterThan(0));

      final passed = day('1998-03-12', yearly: true); // 03-12 已经过了
      expect(passed.nextDate(today), '2027-03-12');
      expect(passed.daysFrom(today), greaterThan(0)); // 永远不出现负数
    });

    test('每年重复：正好是今天的日子算 0 天', () {
      final s = day('2000-10-07', yearly: true);
      expect(s.daysFrom(today), 0);
      expect(s.countdownLabel(today), '今天');
    });

    test('周年数', () {
      expect(day('2000-10-10', yearly: true).anniversaryYears(today), 26);
      // 起始年份还没到（未来才建立的每年重复），不显示周年
      expect(day('2030-10-10', yearly: true).anniversaryYears(today), isNull);
      // 不重复的日子没有周年
      expect(day('2000-10-10').anniversaryYears(today), isNull);
    });
  });

  group('特殊日子 - JSON', () {
    test('往返（含每年重复）', () {
      const s = SpecialDay(
        id: '20261007120000-00001',
        date: '1998-03-12',
        name: '生日',
        type: 'custom',
        color: '#D6409F',
        repeatYearly: true,
      );
      final back = SpecialDay.fromJson(s.toJson());
      expect(back.id, s.id);
      expect(back.date, s.date);
      expect(back.name, s.name);
      expect(back.color, s.color);
      expect(back.repeatYearly, isTrue);
    });

    test('旧数据没有 repeatYearly 字段时按「不重复」处理', () {
      final back = SpecialDay.fromJson(const {
        'id': 'a',
        'date': '2026-01-01',
        'name': '元旦纪念',
        'type': 'custom',
        'color': '#E5484D',
      });
      expect(back.repeatYearly, isFalse);
      expect(back.occursOn('2026-01-01'), isTrue);
    });

    test('copyWith 保持不变字段', () {
      final s = day('1998-03-12', name: '生日', yearly: true);
      final e = s.copyWith(name: '老婆生日', color: '#1E88E5');
      expect(e.id, s.id);
      expect(e.date, s.date);
      expect(e.repeatYearly, isTrue);
      expect(e.name, '老婆生日');
      expect(e.color, '#1E88E5');
    });
  });

  group('特殊日子 - 生命周期字段', () {
    test('JSON 往返包含 originDate / archived / archivedAt', () {
      const s = SpecialDay(
        id: 'a',
        date: '2027-03-12',
        originDate: '1998-03-12',
        name: '生日',
        repeatYearly: true,
        archived: true,
        archivedAt: '2026-10-11',
      );
      final back = SpecialDay.fromJson(s.toJson());
      expect(back.originDate, '1998-03-12');
      expect(back.archived, isTrue);
      expect(back.archivedAt, '2026-10-11');
    });

    test('旧数据没有新字段时按「未归档、无原始日期」处理', () {
      final back = SpecialDay.fromJson(const {
        'id': 'a',
        'date': '2026-01-01',
        'name': '元旦纪念',
        'type': 'custom',
        'color': '#E5484D',
      });
      expect(back.archived, isFalse);
      expect(back.archivedAt, isNull);
      expect(back.originDate, isNull);
      expect(back.anniversaryBase, '2026-01-01');
      expect(back.isExpiredOn('2026-01-02'), isTrue); // 旧数据一样参与生命周期
    });

    test('归档日期只在归档时才有值，恢复后清掉', () {
      final s = day('2026-01-01');
      expect(s.archivedOn('2026-01-02').archivedAt, '2026-01-02');
      expect(s.archivedOn('2026-01-02').restored().archivedAt, isNull);
      expect(s.archivedOn('2026-01-02').restored().archived, isFalse);
      expect(s.toJson().containsKey('archivedAt'), isFalse);
    });

    test('copyWith 保留原始日期与归档状态（改名不能把倒数滚回去）', () {
      const s = SpecialDay(
        id: 'a',
        date: '2027-03-12',
        originDate: '1998-03-12',
        name: '生日',
        repeatYearly: true,
        archived: true,
        archivedAt: '2026-10-11',
      );
      final e = s.copyWith(name: '老婆生日');
      expect(e.date, '2027-03-12');
      expect(e.originDate, '1998-03-12');
      expect(e.archived, isTrue);
      expect(e.archivedAt, '2026-10-11');
      expect(e.name, '老婆生日');
    });

    test('周年数以原始日期为准（推进后仍然正确）', () {
      const s = SpecialDay(
        id: 'a',
        date: '2027-03-12', // 已经推进到下一次
        originDate: '1998-03-12', // 原始日期
        repeatYearly: true,
      );
      expect(s.anniversaryYears('2026-10-11'), 29);
      // 没有原始日期时回退用 date（旧数据行为不变）
      expect(
        const SpecialDay(id: 'b', date: '1998-03-12', repeatYearly: true)
            .anniversaryYears('2026-10-11'),
        29,
      );
    });
  });
}
