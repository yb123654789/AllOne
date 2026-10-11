import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/habit/habit_progress.dart';

/// 习惯进度 / 打卡状态的纯逻辑测试。
///
/// 需求来源：需要多次打卡的习惯「打一次就显示已完成」是错的 ——
/// 完成必须以**当天目标**为准；热力图要能分辨
/// 已完成 / 未完全完成 / 漏打卡 / 主动标记未完成 / 未安排 五种状态。
void main() {
  // 用一个确定的周一当锚点，避免依赖真实日期
  final monday = DateTime.parse('2026-10-12');
  String day(int offset) => AppTime.dateOnly(monday.add(Duration(days: offset)));
  final today = day(4); // 周五

  Habit habit({
    HabitFrequency frequency = HabitFrequency.daily,
    List<int> weekdays = const [],
    int intervalDays = 1,
    int weeklyTimes = 3,
    HabitDailyTarget target = HabitDailyTarget.once,
    int targetValue = 1,
    String created = '2020-01-01',
  }) => Habit(
    id: 'h',
    title: '测试习惯',
    frequency: frequency,
    weekdays: weekdays,
    intervalDays: intervalDays,
    weeklyTimes: weeklyTimes,
    dailyTarget: target,
    dailyTargetValue: targetValue,
    createdAt: DateTime.parse(created),
    updatedAt: DateTime.parse(created),
  );

  CheckinMap cm(Map<String, int> m) => CheckinMap(entries: m);

  /// 带坚持周期的习惯（列表摘要与详情页进度条共用同一套算法）
  Habit withPersistence(HabitPersistence p, int pv) => Habit(
    id: 'h',
    title: '测试习惯',
    persistence: p,
    persistenceValue: pv,
    createdAt: DateTime.parse('2020-01-01'),
    updatedAt: DateTime.parse('2020-01-01'),
  );

  group('习惯 - 坚持周期进度（列表与详情页共用）', () {
    test('不限周期：进度 0、文案「不限」', () {
      final (p, t) = HabitProgress.persistenceProgress(
        withPersistence(HabitPersistence.unlimited, 0),
        10,
        20,
      );
      expect(p, 0);
      expect(t, '不限');
    });

    test('累计天数：按达标天数算，超额封顶 1.0', () {
      final h = withPersistence(HabitPersistence.days, 30);
      final (p, t) = HabitProgress.persistenceProgress(h, 12, 99);
      expect(p, closeTo(0.4, 0.0001));
      expect(t, '坚持 12/30 天');
      final (p2, _) = HabitProgress.persistenceProgress(h, 45, 99);
      expect(p2, 1.0);
    });

    test('累计次数：按打卡次数算', () {
      final h = withPersistence(HabitPersistence.times, 100);
      final (p, t) = HabitProgress.persistenceProgress(h, 5, 25);
      expect(p, closeTo(0.25, 0.0001));
      expect(t, '累计 25/100 次');
    });

    test('循环轮次：每轮 pv 天，显示第几轮与本轮进度', () {
      final h = withPersistence(HabitPersistence.cycles, 30);
      final (p, t) = HabitProgress.persistenceProgress(h, 42, 42);
      expect(p, closeTo(12 / 30, 0.0001));
      expect(t, '第 2 轮 · 本轮 12/30 天');
    });

    test('周期值非法（0）：进度 0，不崩', () {
      final (p, _) = HabitProgress.persistenceProgress(
        withPersistence(HabitPersistence.days, 0),
        5,
        5,
      );
      expect(p, 0);
    });

    test('doneCounts：达标天数与累计次数（有记录但 0 次不算达标日）', () {
      final h = habit();
      final map = cm({'2026-10-01': 1, '2026-10-02': 1, '2026-10-03': 0});
      final (days, total) = HabitProgress.doneCounts(h, map);
      expect(days, 2, reason: '10-03 记录为 0 次，不算达标日');
      expect(total, 2);
    });
  });

  test('基准：2026-10-12 是周一', () {
    expect(monday.weekday, DateTime.monday);
  });

  group('习惯 - 四态判定', () {
    test('一次即完成：打卡即达标', () {
      final h = habit();
      expect(
        HabitProgress.dayStatus(h, cm({today: 1}), today, today: today),
        HabitDayStatus.met,
      );
    });

    test('计划日完全没记录 = 漏打卡（浅红）', () {
      final h = habit();
      expect(
        HabitProgress.dayStatus(h, cm({}), day(3), today: today),
        HabitDayStatus.missed,
      );
    });

    test('主动标记未完成 = 深红，且优先于其它判定', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      // 存的是 -1（标记未完成），即便此前那天打过卡也以「未完成」为准
      expect(
        HabitProgress.dayStatus(h, cm({day(3): -1}), day(3), today: today),
        HabitDayStatus.markedUndone,
      );
    });

    test('多次打卡：打了但没满 = 未完全完成（黄）', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      expect(
        HabitProgress.dayStatus(h, cm({today: 3}), today, today: today),
        HabitDayStatus.partial,
      );
      expect(
        HabitProgress.dayStatus(h, cm({today: 7}), today, today: today),
        HabitDayStatus.partial,
      );
    });

    test('多次打卡：满了（或超出）= 已完成（绿）', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      expect(
        HabitProgress.dayStatus(h, cm({today: 8}), today, today: today),
        HabitDayStatus.met,
      );
      expect(
        HabitProgress.dayStatus(h, cm({today: 12}), today, today: today),
        HabitDayStatus.met,
      );
    });

    test('分钟型同理', () {
      final h = habit(target: HabitDailyTarget.minutes, targetValue: 30);
      expect(
        HabitProgress.dayStatus(h, cm({today: 20}), today, today: today),
        HabitDayStatus.partial,
      );
      expect(
        HabitProgress.dayStatus(h, cm({today: 30}), today, today: today),
        HabitDayStatus.met,
      );
    });

    test('未来日期与习惯创建之前都不参与评价（灰）', () {
      final h = habit(created: day(-2));
      expect(
        HabitProgress.dayStatus(h, cm({}), day(6), today: today),
        HabitDayStatus.off, // 未来（周日）
      );
      expect(
        HabitProgress.dayStatus(h, cm({}), day(-3), today: today),
        HabitDayStatus.off, // 创建前
      );
    });
  });

  group('习惯 - 计划日推算', () {
    test('每天：每天都是计划日', () {
      expect(HabitProgress.isScheduledOn(habit(), day(0)), isTrue);
      expect(HabitProgress.isScheduledOn(habit(), day(5)), isTrue);
    });

    test('每周几天：只算选中的星期', () {
      final h = habit(frequency: HabitFrequency.weekly, weekdays: [1, 3, 5]);
      expect(HabitProgress.isScheduledOn(h, day(0)), isTrue); // 周一
      expect(HabitProgress.isScheduledOn(h, day(1)), isFalse); // 周二
      expect(HabitProgress.isScheduledOn(h, day(2)), isTrue); // 周三
      expect(HabitProgress.isScheduledOn(h, day(4)), isTrue); // 周五
    });

    test('每周几天：非计划日没记录不算漏打卡，计划日才算', () {
      final h = habit(frequency: HabitFrequency.weekly, weekdays: [1, 3, 5]);
      expect(
        HabitProgress.dayStatus(h, cm({}), day(1), today: today),
        HabitDayStatus.off, // 周二，本来就不用打卡
      );
      expect(
        HabitProgress.dayStatus(h, cm({}), day(0), today: today),
        HabitDayStatus.missed, // 周一，该打卡却漏了
      );
    });

    test('每 N 天：从创建日起每 N 天为一个计划日', () {
      final h = habit(
        frequency: HabitFrequency.interval,
        intervalDays: 3,
        created: day(-6),
      );
      expect(HabitProgress.isScheduledOn(h, day(-6)), isTrue);
      expect(HabitProgress.isScheduledOn(h, day(-5)), isFalse);
      expect(HabitProgress.isScheduledOn(h, day(-4)), isFalse);
      expect(HabitProgress.isScheduledOn(h, day(-3)), isTrue);
      expect(HabitProgress.isScheduledOn(h, day(0)), isTrue);
    });

    test('每 N 天：创建之前不判漏打卡', () {
      final h = habit(
        frequency: HabitFrequency.interval,
        intervalDays: 2,
        created: day(-3),
      );
      expect(
        HabitProgress.dayStatus(h, cm({}), day(-4), today: today),
        HabitDayStatus.off,
      );
      expect(
        HabitProgress.dayStatus(h, cm({}), day(-3), today: today),
        HabitDayStatus.missed,
      );
    });

    test('每周 N 次：没有固定计划日，因此不判漏打卡', () {
      final h = habit(frequency: HabitFrequency.weeklyTimes, weeklyTimes: 3);
      expect(HabitProgress.isScheduledOn(h, day(0)), isFalse);
      expect(
        HabitProgress.dayStatus(h, cm({}), day(0), today: today),
        HabitDayStatus.off,
      );
    });
  });

  group('习惯 - 当天进度（进度条与文案）', () {
    test('一次即完成', () {
      final h = habit();
      expect(HabitProgress.dailyProgress(h, cm({}), today).$1, 0.0);
      expect(HabitProgress.dailyProgress(h, cm({}), today).$2, '今天还没打卡');
      expect(HabitProgress.dailyProgress(h, cm({today: 1}), today).$1, 1.0);
      expect(HabitProgress.dailyProgress(h, cm({today: 1}), today).$2, '今天已完成');
    });

    test('按次数：3/8 = 0.375，文案「今日 3/8 次」', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      final (p, t) = HabitProgress.dailyProgress(h, cm({today: 3}), today);
      expect(p, closeTo(0.375, 1e-9));
      expect(t, '今日 3/8 次');
    });

    test('按次数：满目标时进度 1.0 且文案带已完成', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      final (p, t) = HabitProgress.dailyProgress(h, cm({today: 8}), today);
      expect(p, 1.0);
      expect(t, '今日 8/8 次·已完成');
    });

    test('按分钟：超出目标封顶 1.0', () {
      final h = habit(target: HabitDailyTarget.minutes, targetValue: 30);
      final (p, t) = HabitProgress.dailyProgress(h, cm({today: 45}), today);
      expect(p, 1.0);
      expect(t, '今日 45/30 分钟·已完成');
    });

    test('目标值异常（0 / 负数）时按 1 处理，不崩不除零', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 0);
      final (p, _) = HabitProgress.dailyProgress(h, cm({today: 1}), today);
      expect(p, 1.0);
    });
  });

  group('习惯 - 每周 N 次', () {
    test('本周计数 / 达成 / 周行头', () {
      final h = habit(frequency: HabitFrequency.weeklyTimes, weeklyTimes: 3);
      final w = HabitProgress.weekStartOf(today);
      expect(w, day(0)); // 本周一
      final two = cm({day(0): 1, day(2): 1});
      expect(HabitProgress.weekCount(h, two, w), 2);
      expect(HabitProgress.isWeekReached(h, two, w), isFalse);
      expect(HabitProgress.weeklyProgress(h, two, today), (2, 3));
      final three = cm({day(0): 1, day(2): 1, day(4): 1});
      expect(HabitProgress.weekCount(h, three, w), 3);
      expect(HabitProgress.isWeekReached(h, three, w), isTrue);
    });

    test('只统计本周（上周的记录不算进本周）', () {
      final h = habit(frequency: HabitFrequency.weeklyTimes, weeklyTimes: 3);
      final w = HabitProgress.weekStartOf(today);
      final lastWeek = cm({day(-7): 1, day(-6): 1, day(-5): 1});
      expect(HabitProgress.weekCount(h, lastWeek, w), 0);
      expect(HabitProgress.isWeekReached(h, lastWeek, w), isFalse);
    });

    test('非每周 N 次的习惯没有周进度', () {
      final h = habit();
      expect(HabitProgress.weeklyProgress(h, cm({today: 1}), today), (0, 3));
      expect(HabitProgress.isWeekReached(h, cm({today: 1}), day(0)), isFalse);
    });
  });

  group('习惯 - 热力图数据与统计', () {
    test('格子数 = 周数 × 7，首格是起点周一、末格是本周日', () {
      final cells = HabitProgress.heatCells(
        habit(),
        cm({today: 1}),
        today: today,
        weeks: 15,
      );
      expect(cells.length, 15 * 7);
      expect(cells.last.date, day(6)); // 本周日
      expect(cells.first.date, day(6 - 15 * 7 + 1));
      // 今天的格子颜色 = 达标色
      expect(
        cells.firstWhere((c) => c.date == today).color,
        HabitProgress.colorOf(HabitDayStatus.met),
      );
    });

    test('热力图提示文本带数值', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 8);
      final cells = HabitProgress.heatCells(
        h,
        cm({today: 3}),
        today: today,
        weeks: 2,
      );
      final cell = cells.firstWhere((c) => c.date == today);
      expect(cell.tooltip, contains('未完全完成'));
      expect(cell.tooltip, contains('（3）'));
    });

    test('统计：达标 / 部分 / 未完成 / 漏打 分别计数', () {
      final h = habit(target: HabitDailyTarget.quantity, targetValue: 2);
      final map = cm({
        day(0): 2, // 达标
        day(1): 1, // 未完全完成
        day(2): -1, // 主动标记未完成
        // day(3) 无记录 → 漏打卡
      });
      final s = HabitProgress.summarize(
        h,
        map,
        start: day(0),
        end: day(3),
        today: day(6),
      );
      expect(s.met, 1);
      expect(s.partial, 1);
      expect(s.markedUndone, 1);
      expect(s.missed, 1);
      expect(s.scheduled, 4);
      expect(s.metRate, closeTo(0.25, 1e-9));
    });

    test('统计：该打卡天数为 0 时达标率为 0（不除零）', () {
      final s = HabitProgress.summarize(
        habit(),
        cm({}),
        start: day(1),
        end: day(1),
        today: day(0),
      );
      expect(s.scheduled, 0);
      expect(s.metRate, 0);
    });

    test('五种状态的颜色互不相同（热力图能分辨）', () {
      final colors = HabitDayStatus.values
          .map(HabitProgress.colorOf)
          .toSet();
      expect(colors.length, HabitDayStatus.values.length);
      // 漏打卡（浅红）与主动未完成（深红）必须能分辨
      expect(
        HabitProgress.colorOf(HabitDayStatus.missed),
        isNot(HabitProgress.colorOf(HabitDayStatus.markedUndone)),
      );
    });
  });
}
