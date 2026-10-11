import 'package:flutter/material.dart';

import 'schedule_models.dart';

/// 网格里的一个课程块（某天、某个时段）
class CourseSlot {
  final Course course;
  final CourseSession session;
  final int startSection;
  final int endSection;

  const CourseSlot({
    required this.course,
    required this.session,
    required this.startSection,
    required this.endSection,
  });

  /// 占用的行数（连堂 = 多行）
  int get span => (endSection - startSection + 1).clamp(1, 99);
}

/// 课程表相关的**纯逻辑**：教学周次、节次匹配、当周课程块、课程配色。
///
/// 单独抽出来是因为这些都是"算出来"的东西，界面只负责画；
/// 有了它就能直接做单元测试（周次跨月、旧数据就近匹配节次等）。
class ScheduleLogic {
  const ScheduleLogic._();

  /// 周网格每列宽度：把可用宽度平分给 7 天（**铺满屏幕、不横滑**）。
  ///
  /// 极窄窗口下不低于 [minWidth]，避免算出 0 或负数导致布局崩。
  static double columnWidth(
    double available, {
    int columns = 7,
    double leading = 44,
    double gap = 2,
    double minWidth = 24,
  }) {
    final w = available - leading - gap * (columns - 1);
    final each = w / columns;
    return each < minWidth ? minWidth : each;
  }

  // ── 教学周次 ────────────────────────────────────────────────────────────

  /// 容错解析日期：`2026-08-31` / `2026-8-31` / `2026/8/31` 都能吃。
  ///
  /// 为什么需要它：用户手填（或早期版本写入）的日期**常常不补零**，
  /// 而 `DateTime.parse('2026-8-31')` 会直接返回 null ——
  /// 那样整个学期就"算不出第几周"，课程表会显示成空。
  static DateTime? parseDate(String s) {
    final m = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(s.trim());
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final d = int.tryParse(m.group(3)!);
      if (y != null &&
          mo != null &&
          d != null &&
          mo >= 1 &&
          mo <= 12 &&
          d >= 1 &&
          d <= 31) {
        return DateTime(y, mo, d);
      }
    }
    return DateTime.tryParse(s.trim());
  }

  /// 学期第 1 周的周一（= 学期起始日所在周的周一）
  static DateTime? firstMonday(Term term) {
    final d = parseDate(term.start);
    if (d == null) return null;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: d.weekday - 1));
  }

  /// 某一天是学期的第几周（1 起）。学期没有起始日、或早于第 1 周 → 0。
  static int weekNoOf(Term term, DateTime date) {
    final first = firstMonday(term);
    if (first == null) return 0;
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(first).inDays;
    if (diff < 0) return 0;
    return diff ~/ 7 + 1;
  }

  /// 第 [weekNo] 周的周一
  static DateTime? mondayOfWeek(Term term, int weekNo) {
    final first = firstMonday(term);
    if (first == null || weekNo < 1) return null;
    return first.add(Duration(days: 7 * (weekNo - 1)));
  }

  /// 学期总周数（按起止日期算）
  static int totalWeeks(Term term) {
    final first = firstMonday(term);
    final end = parseDate(term.end);
    if (first == null || end == null) return 0;
    final diff = DateTime(
      end.year,
      end.month,
      end.day,
    ).difference(first).inDays;
    if (diff < 0) return 0;
    return diff ~/ 7 + 1;
  }

  /// 当前学期：今天落在其区间内的那个；都不在则取最近开始的（列表已按 start 倒序）。
  ///
  /// 注意用 **DateTime 比较**而不是字符串比较：用户手填的学期日期可能是
  /// `2026-8-31`（非零填充）这种格式，字符串比较会得到错误结果
  /// （`'2026-10-11' < '2026-8-31'` 居然成立）。
  static Term? currentTerm(List<Term> terms, DateTime today) {
    if (terms.isEmpty) return null;
    final key = DateTime(today.year, today.month, today.day);
    for (final t in terms) {
      final s = parseDate(t.start);
      final e = parseDate(t.end);
      if (s == null || e == null) continue;
      if (!key.isBefore(s) && !key.isAfter(e)) return t;
    }
    return terms.first;
  }

  // ── 节次与时间 ──────────────────────────────────────────────────────────

  /// `HH:mm` → 从 0 点起的分钟数（非法返回 -1）
  static int minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }

  /// 把 `HH:mm` 就近匹配到作息表里的节次（返回节次号；匹配不到返回 0）。
  ///
  /// 旧课程只有时间没有节次，靠这个把它们摆到网格的近似行上，
  /// 而不是让它们在网格里凭空消失。
  static int nearestSection(List<SectionTime> sections, String time) {
    if (sections.isEmpty || time.isEmpty) return 0;
    final t = minutesOf(time);
    if (t < 0) return 0;
    var best = 0;
    var bestDiff = 1 << 30;
    for (final s in sections) {
      final m = minutesOf(s.start);
      if (m < 0) continue;
      final d = (m - t).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = s.index;
      }
    }
    return best;
  }

  /// 时段占用的起始节次（显式指定优先，否则按自定义时间就近匹配）
  static int sectionStartOf(CourseSession s, List<SectionTime> sections) {
    if (s.startSection > 0) return s.startSection;
    if (s.startTime.isEmpty) return 0;
    return nearestSection(sections, s.startTime);
  }

  /// 时段占用的结束节次（不小于起始节次）
  static int sectionEndOf(CourseSession s, List<SectionTime> sections) {
    if (s.endSection > 0 && s.endSection >= s.startSection) return s.endSection;
    if (s.endTime.isNotEmpty) {
      final e = nearestSection(sections, s.endTime);
      if (e > 0) return e;
    }
    return sectionStartOf(s, sections);
  }

  static SectionTime? _sectionOf(List<SectionTime> sections, int index) {
    for (final s in sections) {
      if (s.index == index) return s;
    }
    return null;
  }

  /// 时段的上课时间文案：自定义时间优先，否则取作息表（连堂取首节开始~末节结束）
  static String clockOf(CourseSession s, List<SectionTime> sections) {
    if (s.hasCustomTime) {
      if (s.startTime.isEmpty) return s.endTime;
      return s.endTime.isEmpty ? s.startTime : '${s.startTime}-${s.endTime}';
    }
    final a = _sectionOf(sections, sectionStartOf(s, sections));
    final b = _sectionOf(sections, sectionEndOf(s, sections));
    if (a == null) return '';
    if (b == null || b.index == a.index) return a.label;
    return '${a.start}-${b.end}';
  }

  /// 节次文案：`第 3 节` / `第 3-4 节`
  static String sectionLabel(CourseSession s, List<SectionTime> sections) {
    final a = sectionStartOf(s, sections);
    final b = sectionEndOf(s, sections);
    if (a <= 0) return '未指定节次';
    if (b <= a) return '第 $a 节';
    return '第 $a-$b 节';
  }

  // ── 课程配色 ────────────────────────────────────────────────────────────

  /// 课程块用的浅色（照截图那种"浅底 + 深字"）
  static const List<String> palette = [
    '#E8E3FA', // 浅紫
    '#E3F0E3', // 浅绿
    '#FDEBD8', // 浅橙
    '#FBF3D5', // 浅黄
    '#E2EEF9', // 浅蓝
    '#FBE4EC', // 浅粉
    '#E6F3F1', // 浅青
    '#F0EAE1', // 浅棕
  ];

  /// 课程颜色：用户设了就用，否则按课程名取一个**稳定**的调色板颜色
  static Color colorOf(Course course) {
    if (course.color.isNotEmpty) {
      final hex = course.color.replaceFirst('#', '');
      final full = hex.length == 6 ? 'FF$hex' : hex;
      final v = int.tryParse(full, radix: 16);
      if (v != null) return Color(v);
    }
    return Color(_hexOf(palette[course.name.hashCode.abs() % palette.length]));
  }

  /// 与课程块配色相配的深色文字（保证浅底上可读）
  static Color textColorOf(Color bg) {
    final h = HSLColor.fromColor(bg);
    return h.withLightness((h.lightness - 0.42).clamp(0.0, 1.0)).toColor();
  }

  static int _hexOf(String hex) {
    final h = hex.replaceFirst('#', '');
    final full = h.length == 6 ? 'FF$h' : h;
    return int.tryParse(full, radix: 16) ?? 0xFFE8E3FA;
  }

  // ── 当周课程 ────────────────────────────────────────────────────────────

  /// 某天（[weekday] 1-7）在第 [weekNo] 周要上的课，按起始节次排序。
  ///
  /// 定位不到节次的时段会被跳过（它们仍能在「课程统计」里看到，
  /// 编辑时重新选一下节次就会回到网格）。
  static List<CourseSlot> slotsOf(
    List<Course> courses,
    List<SectionTime> sections, {
    required int weekday,
    required int weekNo,
  }) {
    final out = <CourseSlot>[];
    for (final c in courses) {
      for (final s in c.sessions) {
        if (s.weekday != weekday) continue;
        if (!s.occursInWeek(weekNo)) continue;
        final a = sectionStartOf(s, sections);
        if (a <= 0) continue;
        out.add(
          CourseSlot(
            course: c,
            session: s,
            startSection: a,
            endSection: sectionEndOf(s, sections),
          ),
        );
      }
    }
    out.sort((x, y) {
      final c = x.startSection.compareTo(y.startSection);
      if (c != 0) return c;
      return x.course.name.compareTo(y.course.name);
    });
    return out;
  }

  /// 某天（真实日期）要上的课 —— 日历当天日程表用。
  ///
  /// [term] 为空或该天不在学期内时返回空列表。
  static List<CourseSlot> slotsOnDate(
    List<Course> courses,
    List<SectionTime> sections,
    Term? term,
    DateTime date,
  ) {
    if (term == null) return const [];
    final weekNo = weekNoOf(term, date);
    if (weekNo <= 0) return const [];
    return slotsOf(
      courses,
      sections,
      weekday: date.weekday,
      weekNo: weekNo,
    );
  }
}
