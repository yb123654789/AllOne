import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/calendar/holiday_data.dart';
import 'package:allone/features/calendar/lunar_calendar.dart';

/// 内置节假日生成的回归测试。
///
/// 重点验证两件事：
/// 1. **农历节日不会因为在闰月重复出现而算重**
///    （生成逻辑逐日扫描全年，闰月的月/日与正月光/日相同，
///    若不排除闰月，像「闰六月初六」就会再报一次端午节）。
/// 2. 关键节日的公历日期与本年度实际日期一致（用已知年份锁死）。
void main() {
  /// 取某年某节日名的全部日期
  List<String> datesOf(int year, String name) =>
      HolidayProvider.builtInHolidaysForYear(year)
          .where((h) => h.name == name)
          .map((h) => h.date)
          .toList();

  group('内置节假日 - 日期正确性', () {
    test('2026 年关键节日', () {
      expect(datesOf(2026, '元旦'), ['2026-01-01']);
      expect(datesOf(2026, '春节'), ['2026-02-17']);
      expect(datesOf(2026, '清明节'), ['2026-04-05']);
      expect(datesOf(2026, '劳动节'), ['2026-05-01']);
      expect(datesOf(2026, '国庆节'), ['2026-10-01']);
    });

    test('2025 年关键节日（含闰六月）', () {
      expect(datesOf(2025, '春节'), ['2025-01-29']);
      expect(datesOf(2025, '清明节'), ['2025-04-04']);
      expect(datesOf(2025, '端午节'), ['2025-05-31']);
      expect(datesOf(2025, '中秋节'), ['2025-10-06']);
    });

    test('2027 年春节', () {
      expect(datesOf(2027, '春节'), ['2027-02-06']);
    });

    test('国庆节与元旦固定在公历日期', () {
      for (final y in [2024, 2025, 2026, 2027, 2028]) {
        expect(datesOf(y, '国庆节'), ['$y-10-01']);
        expect(datesOf(y, '元旦'), ['$y-01-01']);
      }
    });
  });

  group('内置节假日 - 不重复', () {
    test('同一年内「节日 + 日期」不重复', () {
      for (final y in [2024, 2025, 2026, 2027, 2028]) {
        final holidays = HolidayProvider.builtInHolidaysForYear(y);
        final keys = holidays.map((h) => '${h.name}|${h.date}').toList();
        expect(keys.toSet().length, keys.length, reason: '$y 年存在重复的「节日 + 日期」');
      }
    });

    test('除除夕外，每个节日在一年内只出现一次', () {
      // 除夕是特例：一个公历年内**可以有两个除夕**，这是正确的。
      // 例：2024-02-09 是兔年除夕，2024-12-31 是龙年除夕。
      // 所以这里只对非除夕节日要求唯一。
      for (final y in [2024, 2025, 2026, 2027, 2028]) {
        final byName = <String, List<String>>{};
        for (final h in HolidayProvider.builtInHolidaysForYear(y)) {
          if (h.name == '除夕') continue;
          byName.putIfAbsent(h.name, () => []).add(h.date);
        }
        byName.forEach((name, dates) {
          expect(
            dates.length,
            1,
            reason: '$y 年的「$name」出现了 ${dates.length} 次：$dates（闰月节日未排除？）',
          );
        });
      }
    });

    test('除夕就是腊月最后一天，不会把公历年末误判成除夕', () {
      // 回归：修复前，只要「公历 12 月 31 日仍落在农历腊月」就会被当成除夕，
      // 于是 2027-12-31（实为腊月初四）被错误标成除夕。
      // 正确结果只应是各年真正的除夕。
      expect(datesOf(2024, '除夕'), ['2024-02-09']);
      expect(datesOf(2025, '除夕'), ['2025-01-28']);
      expect(datesOf(2026, '除夕'), ['2026-02-16']);
      expect(datesOf(2027, '除夕'), ['2027-02-05']);
      expect(datesOf(2028, '除夕'), ['2028-01-25']);

      // 明确否定曾经的误判
      for (final y in [2024, 2025, 2026, 2027, 2028]) {
        expect(
          datesOf(y, '除夕'),
          isNot(contains('$y-12-31')),
          reason: '$y-12-31 不是除夕（腊月尚未结束）',
        );
      }
    });

    test('2025 年闰六月不会让节日算重', () {
      // 2025 年有闰六月；闰月初六不是端午节
      expect(datesOf(2025, '端午节'), hasLength(1));
      expect(datesOf(2025, '中秋节'), hasLength(1));
    });

    test('合并相邻两年的列表后，不出现同一「节日 + 日期」', () {
      for (final y in [2024, 2025, 2026, 2027]) {
        final keys = <String>[];
        for (final yy in [y, y + 1]) {
          for (final h in HolidayProvider.builtInHolidaysForYear(yy)) {
            keys.add('${h.name}|${h.date}');
          }
        }
        expect(
          keys.toSet().length,
          keys.length,
          reason: '合并 $y 与 ${y + 1} 的列表后出现重复的「节日 + 日期」',
        );
      }
    });

    test('id 唯一', () {
      final holidays = HolidayProvider.builtInHolidaysForYear(2026);
      final ids = holidays.map((h) => h.id).toList();
      expect(ids.toSet().length, ids.length, reason: '节日 id 出现重复');
    });

    test('都属于 holiday 类型且日期格式为 yyyy-MM-dd', () {
      final holidays = HolidayProvider.builtInHolidaysForYear(2026);
      expect(holidays, isNotEmpty);
      for (final h in holidays) {
        expect(h.type, 'holiday');
        expect(
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(h.date),
          isTrue,
          reason: '${h.name} 的日期格式不对：${h.date}',
        );
        expect(
          h.date.startsWith('2026-'),
          isTrue,
          reason: '${h.name} 的日期不属于 2026 年：${h.date}',
        );
      }
    });
  });

  group('农历换算 - 基本对照', () {
    test('已知春节日期的农历为 1 月 1 日', () {
      final springFestivals = {
        2025: DateTime(2025, 1, 29),
        2026: DateTime(2026, 2, 17),
        2027: DateTime(2027, 2, 6),
      };
      springFestivals.forEach((year, solar) {
        final l = LunarCalendar.solarToLunar(
          DateTime.utc(solar.year, solar.month, solar.day),
        );
        expect(l.month, 1, reason: '$year 春节应为农历一月');
        expect(l.day, 1, reason: '$year 春节应为农历初一');
        expect(l.isLeap, isFalse);
      });
    });
  });
}
