import 'package:flutter/material.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import '../../core/widgets/heat_map.dart';
import 'habit_models.dart';

/// 某一天在热力图上的状态。
///
/// 四态 + 「不参与评价」：
/// - [met]           达标（绿）
/// - [partial]       有打卡但没达标（黄，对应「未完全完成」）
/// - [missed]        计划日却完全没记录（浅红，对应「漏打卡」）
/// - [markedUndone]  用户主动标记「未完成」（深红）
/// - [off]           非计划日 / 习惯创建之前 / 未来（灰，不参与评价）
enum HabitDayStatus { met, partial, missed, markedUndone, off }

/// 习惯进度与打卡状态的**纯逻辑**（不碰存储，便于单元测试）。
class HabitProgress {
  const HabitProgress._();

  // ── 计划日 ──────────────────────────────────────────────────────────────

  /// 该习惯在某天是否「计划内」（用于判断漏打卡）。
  ///
  /// - 每天：每天都是计划日；
  /// - 每周几天：只在选中的星期几；
  /// - 每 N 天：从**创建日**起每 N 天（含创建日）；
  /// - 每周 N 次：**没有固定计划日**，因此不判漏打卡（只按周算达成）。
  static bool isScheduledOn(Habit h, String date) {
    if (date.length < 10) return false;
    switch (h.frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekly:
        final wd = weekdayOf(date);
        return wd != null && h.weekdays.contains(wd);
      case HabitFrequency.interval:
        final start = AppTime.dateOnly(h.createdAt);
        final d0 = DateTime.tryParse(start);
        final d1 = DateTime.tryParse(date);
        if (d0 == null || d1 == null) return false;
        final n = h.intervalDays <= 0 ? 1 : h.intervalDays;
        final diff = DateTime(d1.year, d1.month, d1.day)
            .difference(DateTime(d0.year, d0.month, d0.day))
            .inDays;
        return diff >= 0 && diff % n == 0;
      case HabitFrequency.weeklyTimes:
        return false;
    }
  }

  /// 1=周一 … 7=周日；解析失败返回 null
  static int? weekdayOf(String date) => DateTime.tryParse(date)?.weekday;

  /// 某日期所在周的**周一**（yyyy-MM-dd）
  static String weekStartOf(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    final monday = DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
    return AppTime.dateOnly(monday);
  }

  // ── 某天的状态 ──────────────────────────────────────────────────────────

  /// 判定某天的状态。
  ///
  /// 顺序很关键：先排除「不参与评价」的日子，再依次看
  /// 主动标记未完成 → 达标 → 有记录未达标 → 计划日漏打卡 → 不参与评价。
  static HabitDayStatus dayStatus(
    Habit h,
    CheckinMap cm,
    String date, {
    required String today,
  }) {
    if (date.length < 10 || today.length < 10) return HabitDayStatus.off;
    if (date.compareTo(today) > 0) return HabitDayStatus.off; // 未来
    if (date.compareTo(AppTime.dateOnly(h.createdAt)) < 0) {
      return HabitDayStatus.off; // 习惯还没创建
    }
    if (cm.isFailed(date)) return HabitDayStatus.markedUndone;
    if (cm.dayMet(date, h.dailyTarget, h.dailyTargetValue)) {
      return HabitDayStatus.met;
    }
    if (cm.dayValue(date) > 0) return HabitDayStatus.partial;
    return isScheduledOn(h, date)
        ? HabitDayStatus.missed
        : HabitDayStatus.off;
  }

  /// 状态对应的颜色（热力图 / 图例共用）
  static Color colorOf(HabitDayStatus s) {
    switch (s) {
      case HabitDayStatus.met:
        return const Color(0xFF30A46C); // 绿
      case HabitDayStatus.partial:
        return const Color(0xFFF5A623); // 黄
      case HabitDayStatus.missed:
        return AppTheme.danger.withValues(alpha: 0.32); // 浅红：漏打卡
      case HabitDayStatus.markedUndone:
        return AppTheme.danger; // 深红：主动标记未完成
      case HabitDayStatus.off:
        return const Color(0xFFE3E5E8); // 灰：不参与评价
    }
  }

  /// 状态文案（图例 / 提示用）
  static String labelOf(HabitDayStatus s) {
    switch (s) {
      case HabitDayStatus.met:
        return '已完成';
      case HabitDayStatus.partial:
        return '未完全完成';
      case HabitDayStatus.missed:
        return '漏打卡';
      case HabitDayStatus.markedUndone:
        return '标记未完成';
      case HabitDayStatus.off:
        return '未安排';
    }
  }

  // ── 进度 ────────────────────────────────────────────────────────────────

  /// 当天目标进度：返回 0.0~1.0 与文案。
  ///
  /// 文案形如「今日 3/8 次」「今日 12/30 分钟」「今天已完成」「今日还没打卡」。
  static (double, String) dailyProgress(
    Habit h,
    CheckinMap cm,
    String today,
  ) {
    final met = cm.dayMet(today, h.dailyTarget, h.dailyTargetValue);
    switch (h.dailyTarget) {
      case HabitDailyTarget.once:
        return (met ? 1.0 : 0.0, met ? '今天已完成' : '今天还没打卡');
      case HabitDailyTarget.quantity:
      case HabitDailyTarget.minutes:
        final unit = h.dailyTarget == HabitDailyTarget.minutes ? '分钟' : '次';
        final target = h.dailyTargetValue <= 0 ? 1 : h.dailyTargetValue;
        final v = cm.dayValue(today);
        final p = (v / target).clamp(0.0, 1.0);
        if (met) return (1.0, '今日 $v/$target $unit·已完成');
        return (p, '今日 $v/$target $unit');
    }
  }

  /// 达标天数与累计打卡次数（坚持周期进度要用）
  ///
  /// - 达标天数：**当天目标满了**才算一天（多打卡习惯不会打过一次就算达标）；
  /// - 累计次数：`CheckinMap.totalCount`。
  static (int, int) doneCounts(Habit h, CheckinMap cm) {
    bool met(String d) => cm.dayMet(d, h.dailyTarget, h.dailyTargetValue);
    final days = cm.entries.keys.where(met).length;
    return (days, cm.totalCount);
  }

  /// 坚持周期进度（0.0~1.0）与文案。
  ///
  /// 四种周期：不限 / 累计天数 / 累计次数 / 循环轮次。
  /// 这里原本是 `habit_page` 的私有方法，搬到公共层是为了让
  /// **列表摘要与详情页进度条共用同一套算法**（不会两处算得不一样）。
  static (double, String) persistenceProgress(
    Habit h,
    int doneDays,
    int doneTotal,
  ) {
    final pv = h.persistenceValue;
    switch (h.persistence) {
      case HabitPersistence.unlimited:
        return (0, '不限');
      case HabitPersistence.days:
        final p = pv <= 0 ? 0.0 : (doneDays / pv).clamp(0.0, 1.0);
        return (p, '坚持 $doneDays/$pv 天');
      case HabitPersistence.times:
        final p = pv <= 0 ? 0.0 : (doneTotal / pv).clamp(0.0, 1.0);
        return (p, '累计 $doneTotal/$pv 次');
      case HabitPersistence.cycles:
        // 每轮 pv 天：已完成的完整轮数 + 本轮进度
        final p = pv <= 0 ? 0.0 : (doneDays % pv) / pv;
        final rounds = pv <= 0 ? 0 : doneDays ~/ pv;
        return (p, '第 ${rounds + 1} 轮 · 本轮 ${doneDays % pv}/$pv 天');
    }
  }

  /// 本周进度（仅 `frequency == weeklyTimes` 有意义）：
  /// 返回 (本周已有记录的天数, 目标次数)。
  static (int, int) weeklyProgress(Habit h, CheckinMap cm, String today) {
    final target = h.weeklyTimes <= 0 ? 1 : h.weeklyTimes;
    if (h.frequency != HabitFrequency.weeklyTimes) return (0, target);
    final start = DateTime.tryParse(weekStartOf(today));
    if (start == null) return (0, target);
    var count = 0;
    for (var i = 0; i < 7; i++) {
      final d = AppTime.dateOnly(start.add(Duration(days: i)));
      if (d.compareTo(today) > 0) break;
      if (cm.dayValue(d) > 0) count++;
    }
    return (count, target);
  }

  /// 某一周是否达成（仅 weeklyTimes）：本周有记录的天数 ≥ 目标次数
  static bool isWeekReached(Habit h, CheckinMap cm, String weekStart) {
    if (h.frequency != HabitFrequency.weeklyTimes) return false;
    final start = DateTime.tryParse(weekStart);
    if (start == null) return false;
    final target = h.weeklyTimes <= 0 ? 1 : h.weeklyTimes;
    var count = 0;
    for (var i = 0; i < 7; i++) {
      final d = AppTime.dateOnly(start.add(Duration(days: i)));
      if (cm.dayValue(d) > 0) count++;
    }
    return count >= target;
  }

  /// 某一周「有记录的天数」（周行头显示 2/3 用）
  static int weekCount(Habit h, CheckinMap cm, String weekStart) {
    final start = DateTime.tryParse(weekStart);
    if (start == null) return 0;
    var count = 0;
    for (var i = 0; i < 7; i++) {
      final d = AppTime.dateOnly(start.add(Duration(days: i)));
      if (cm.dayValue(d) > 0) count++;
    }
    return count;
  }

  /// 生成热力图数据（卡片内嵌小图与详情页大图共用）。
  ///
  /// [weeks] 列数（含本周），从「本周的周一」往前推。
  static List<HeatCell> heatCells(
    Habit h,
    CheckinMap cm, {
    required String today,
    required int weeks,
  }) {
    final anchor = DateTime.tryParse(today) ?? DateTime.now();
    final lastMonday = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: anchor.weekday - 1));
    final first = lastMonday.subtract(Duration(days: 7 * (weeks - 1)));
    final out = <HeatCell>[];
    for (var i = 0; i < weeks * 7; i++) {
      final key = AppTime.dateOnly(first.add(Duration(days: i)));
      final status = dayStatus(h, cm, key, today: today);
      final v = cm.dayValue(key);
      out.add(
        HeatCell(
          date: key,
          color: colorOf(status),
          tooltip: '$key ${labelOf(status)}${v > 0 ? '（$v）' : ''}',
        ),
      );
    }
    return out;
  }

  /// 统计窗口内的达标 / 漏打等汇总（详情页统计用）。
  /// [start] / [end] 均为 yyyy-MM-dd（含端点）。
  static HabitStats summarize(
    Habit h,
    CheckinMap cm, {
    required String start,
    required String end,
    required String today,
  }) {
    var met = 0, partial = 0, missed = 0, markedUndone = 0, scheduled = 0;
    final d0 = DateTime.tryParse(start);
    final d1 = DateTime.tryParse(end);
    if (d0 == null || d1 == null) {
      return const HabitStats(
        met: 0,
        partial: 0,
        missed: 0,
        markedUndone: 0,
        scheduled: 0,
      );
    }
    var d = DateTime(d0.year, d0.month, d0.day);
    final last = DateTime(d1.year, d1.month, d1.day);
    while (!d.isAfter(last)) {
      final key = AppTime.dateOnly(d);
      final s = dayStatus(h, cm, key, today: today);
      switch (s) {
        case HabitDayStatus.met:
          met++;
          scheduled++;
        case HabitDayStatus.partial:
          partial++;
          scheduled++;
        case HabitDayStatus.missed:
          missed++;
          scheduled++;
        case HabitDayStatus.markedUndone:
          markedUndone++;
          scheduled++;
        case HabitDayStatus.off:
          break;
      }
      d = d.add(const Duration(days: 1));
    }
    return HabitStats(
      met: met,
      partial: partial,
      missed: missed,
      markedUndone: markedUndone,
      scheduled: scheduled,
    );
  }
}

/// 一段时间内的汇总
class HabitStats {
  final int met; // 达标天数
  final int partial; // 有记录未达标
  final int missed; // 漏打卡
  final int markedUndone; // 主动标记未完成
  final int scheduled; // 该打卡的总天数（上面四项之和）

  const HabitStats({
    required this.met,
    required this.partial,
    required this.missed,
    required this.markedUndone,
    required this.scheduled,
  });

  /// 达标率（0.0~1.0）；没有该打卡的日子时返回 0
  double get metRate => scheduled <= 0 ? 0 : met / scheduled;
}
