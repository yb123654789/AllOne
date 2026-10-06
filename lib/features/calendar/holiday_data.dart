import 'calendar_models.dart';
import 'lunar_calendar.dart';

/// 内置法定节假日 / 传统节日生成器。
///
/// 生成的节日 `type` 固定为 `holiday`，id 以 `holiday-` 开头，
/// 由代码动态生成，不写入 `special_days.json`（与用户自定义的特殊日子区分）。
class HolidayProvider {
  HolidayProvider._();

  /// 内置节日的默认颜色
  static const _holidayColor = '#E5484D';
  static const _festivalColor = '#F5A623';

  /// 按年份缓存生成结果。
  ///
  /// 生成过程需要逐日扫描全年（365 次农历换算），
  /// 而该 provider 会在日历切换月份/年份时被反复读取；
  /// 缓存可避免每次重建都重算一遍。
  /// 返回值视为只读，调用方不要就地修改（需要改动请先复制）。
  static final Map<int, List<SpecialDay>> _cache = {};

  /// 生成某一年内置的公历节日 / 农历传统节日。
  static List<SpecialDay> builtInHolidaysForYear(int year) {
    final cached = _cache[year];
    if (cached != null) return cached;
    final built = _buildHolidaysForYear(year);
    _cache[year] = built;
    return built;
  }

  static List<SpecialDay> _buildHolidaysForYear(int year) {
    final result = <SpecialDay>[];

    void add(int month, int day, String name, {String color = _holidayColor}) {
      final date =
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      result.add(
        SpecialDay(
          id: 'holiday-$year-$month-$day-$name',
          date: date,
          name: name,
          type: 'holiday',
          color: color,
        ),
      );
    }

    // —— 公历固定节日 ——
    add(1, 1, '元旦');
    add(2, 14, '情人节', color: _festivalColor);
    add(3, 8, '妇女节');
    add(3, 12, '植树节', color: _festivalColor);
    add(4, _qingmingDay(year), '清明节');
    add(5, 1, '劳动节');
    add(5, 4, '青年节', color: _festivalColor);
    add(6, 1, '儿童节', color: _festivalColor);
    add(7, 1, '建党节');
    add(8, 1, '建军节');
    add(9, 10, '教师节');
    add(10, 1, '国庆节');
    add(12, 25, '圣诞节', color: _festivalColor);

    // —— 农历传统节日（逐日扫描该年每一天） ——
    LunarDate? prev;
    DateTime? prevDate;
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31);
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final l = LunarCalendar.solarToLunar(
        DateTime.utc(d.year, d.month, d.day),
      );
      // 闰月不算节日：如「闰七月初七」不是七夕。
      // 农历闰月很常见（如 2025 年闰六月），漏掉这个判断会把节日算重。
      if (!l.isLeap) {
        switch ('${l.month}-${l.day}') {
          case '1-1':
            add(d.month, d.day, '春节', color: _holidayColor);
          case '1-15':
            add(d.month, d.day, '元宵节', color: _festivalColor);
          case '5-5':
            add(d.month, d.day, '端午节', color: _festivalColor);
          case '7-7':
            add(d.month, d.day, '七夕', color: _festivalColor);
          case '8-15':
            add(d.month, d.day, '中秋节', color: _festivalColor);
          case '9-9':
            add(d.month, d.day, '重阳节', color: _festivalColor);
        }
      }
      // 除夕：农历腊月的最后一天。
      //
      // 注意这里的两个关键点：
      // 1. **必须确认是腊月末尾**。扫描范围是「公历 1 月 1 日 – 12 月 31 日」，
      //    而农历腊月常常跨到次年 1 月才结束。若只看「最后一天是否还在腊月」，
      //    就会把公历年末那天（可能只是腊月初四）误判成除夕。
      // 2. 因此这里只在**离开腊月时**才认定除夕，且要求当天是腊月廿九/三十
      //    （不能到达腊月末尾就说明这个农历年还没过完，交给下一年的扫描处理）。
      if (prev != null &&
          prevDate != null &&
          prev.month == 12 &&
          l.month != 12 &&
          (prev.day == 29 || prev.day == 30)) {
        add(prevDate.month, prevDate.day, '除夕', color: _holidayColor);
      }
      prev = l;
      prevDate = d;
    }

    // 公历年末仍停在腊月，且正好是腊月最后一天 → 除夕
    if (prev != null &&
        prevDate != null &&
        prev.month == 12 &&
        (prev.day == 29 || prev.day == 30)) {
      add(prevDate.month, prevDate.day, '除夕', color: _holidayColor);
    }

    return result;
  }

  /// 清明节近似日期（公历节气，约 4 月 4–6 日）
  static int _qingmingDay(int year) {
    final y = year - 2000;
    final d = (0.2422 * y + 4.81) - (y ~/ 4);
    return d.floor();
  }
}
