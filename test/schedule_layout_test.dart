import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/schedule/schedule_logic.dart';
import 'package:allone/features/schedule/schedule_models.dart';

/// 课程表排版、教学周次、节次匹配与旧数据迁移的纯逻辑测试。
///
/// 背景（2026-10-11 重做）：引入「节次 + 作息表」后，网格改成
/// **左侧节次轴 + 7 列铺满**（不再横向滚动），课程只选节次；
/// 这些计算都在 [ScheduleLogic] 里，所以能直接测。
void main() {
  group('周网格列宽：铺满屏幕、不横滑', () {
    test('常见宽度：轴宽 + 7 列 + 列距 = 可用宽度', () {
      for (final w in [360.0, 390.0, 600.0, 800.0, 1024.0, 1920.0]) {
        final col = ScheduleLogic.columnWidth(w);
        expect(
          44 + col * 7 + 2 * 6,
          closeTo(w, 0.01),
          reason: '窗口宽 $w 时应正好铺满',
        );
      }
    });

    test('手机宽度也能铺满（不需要左右平移）', () {
      final col = ScheduleLogic.columnWidth(390);
      expect(col, greaterThan(24));
      expect(44 + col * 7 + 2 * 6, closeTo(390, 0.01));
    });

    test('极窄窗口：不低于最小列宽（不崩、不出负数）', () {
      expect(ScheduleLogic.columnWidth(10), 24);
      expect(ScheduleLogic.columnWidth(0), 24);
      expect(ScheduleLogic.columnWidth(-100), 24);
    });

    test('参数可调（列数 / 轴宽 / 间距）', () {
      final col = ScheduleLogic.columnWidth(
        500,
        columns: 5,
        leading: 0,
        gap: 10,
      );
      expect(col * 5 + 10 * 4, closeTo(500, 0.01));
    });
  });

  group('教学周次：按学期起始日自动算', () {
    Term term(String start, [String end = '']) =>
        Term(id: 't', name: '秋', start: start, end: end);

    test('第 1 周 = 开学日所在周（周一起算）', () {
      // 2026-09-02 是周三 → 第 1 周的周一是 2026-08-31
      final t = term('2026-09-02', '2027-01-10');
      expect(
        AppTime.dateOnly(ScheduleLogic.mondayOfWeek(t, 1)!),
        '2026-08-31',
      );
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-08-31')), 1);
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-09-06')), 1);
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-09-07')), 2);
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-09-14')), 3);
    });

    test('开学日之前 → 第 0 周（视为不在学期内）', () {
      final t = term('2026-09-02', '2027-01-10');
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-08-30')), 0);
    });

    test('总周数按起止日期算', () {
      final t = term('2026-09-02', '2026-12-22');
      expect(ScheduleLogic.totalWeeks(t), greaterThan(15));
      expect(ScheduleLogic.totalWeeks(t), lessThan(20));
    });

    test('没有起始日 / 非法日期 → 0，不崩', () {
      expect(ScheduleLogic.weekNoOf(term(''), DateTime.now()), 0);
      expect(ScheduleLogic.totalWeeks(term('')), 0);
      expect(ScheduleLogic.mondayOfWeek(term(''), 1), isNull);
    });

    test('当前学期：落在区间内的优先，都不在则取最近开始的', () {
      final list = [
        term('2027-02-20', '2027-07-01'), // 未来学期（列表按 start 倒序）
        term('2026-09-02', '2027-01-10'),
        term('2026-02-20', '2026-07-01'),
      ];
      final t = ScheduleLogic.currentTerm(list, DateTime.parse('2026-10-11'));
      expect(t?.start, '2026-09-02');
      final none = ScheduleLogic.currentTerm(
        [list[0], list[2]],
        DateTime.parse('2026-10-11'),
      );
      expect(none?.start, '2027-02-20', reason: '都不在区间内时取最近开始的');
    });

    test('学期日期是非零填充格式（2026-8-31）也要算对', () {
      // 用户手填的日期可能没有补零，字符串比较会出错，所以内部按日期解析
      final t = term('2026-8-31', '2027-1-17');
      expect(
        ScheduleLogic.currentTerm([t], DateTime.parse('2026-10-11'))?.id,
        't',
        reason: '10-11 落在学期区间内，必须命中而不是回退',
      );
      // 与用户课表截图一致：2026-8-31 开学 → 10-11 是第 6 周
      expect(ScheduleLogic.weekNoOf(t, DateTime.parse('2026-10-11')), 6);
    });
  });

  group('节次匹配与课程块', () {
    final secs = kDefaultSections;

    test('时间就近匹配到节次', () {
      expect(ScheduleLogic.nearestSection(secs, '08:50'), 1);
      expect(ScheduleLogic.nearestSection(secs, '08:55'), 1);
      expect(ScheduleLogic.nearestSection(secs, '10:40'), 3);
      expect(ScheduleLogic.nearestSection(secs, '23:30'), 11);
      expect(ScheduleLogic.nearestSection(secs, ''), 0);
      expect(ScheduleLogic.nearestSection(const [], '08:00'), 0);
    });

    test('显式节次优先于自定义时间', () {
      const s = CourseSession(
        startSection: 5,
        endSection: 5,
        startTime: '08:00',
      );
      expect(ScheduleLogic.sectionStartOf(s, secs), 5);
      expect(ScheduleLogic.sectionEndOf(s, secs), 5);
    });

    test('旧数据（只有时间）按时间落位，不丢在网格外', () {
      const s = CourseSession(startTime: '08:00', endTime: '09:40');
      expect(ScheduleLogic.sectionStartOf(s, secs), 1);
      // 09:40 正好是第 2 节的开始 → 这段课落在第 1-2 节（占两行）
      expect(ScheduleLogic.sectionEndOf(s, secs), 2);
    });

    test('连堂：占多行、文案是「第 3-4 节」', () {
      const s = CourseSession(startSection: 3, endSection: 4);
      expect(ScheduleLogic.sectionEndOf(s, secs), 4);
      expect(ScheduleLogic.sectionLabel(s, secs), '第 3-4 节');
      expect(ScheduleLogic.clockOf(s, secs), '10:40-12:15');
    });

    test('课程块 span = 占用的行数', () {
      final courses = [
        Course(
          id: 'c',
          name: '数据结构',
          sessions: const [
            CourseSession(weekday: 1, startSection: 3, endSection: 4),
          ],
        ),
      ];
      final slots = ScheduleLogic.slotsOf(
        courses,
        secs,
        weekday: 1,
        weekNo: 1,
      );
      expect(slots.length, 1);
      expect(slots.first.span, 2);
      expect(slots.first.startSection, 3);
    });

    test('周次不匹配的课不出现在那一周（逐周点选生效）', () {
      final courses = [
        Course(
          id: 'c',
          name: 'x',
          sessions: const [
            CourseSession(
              weekday: 1,
              startSection: 1,
              endSection: 1,
              weeks: [1, 3],
            ),
          ],
        ),
      ];
      expect(
        ScheduleLogic.slotsOf(courses, secs, weekday: 1, weekNo: 1).length,
        1,
      );
      expect(
        ScheduleLogic.slotsOf(courses, secs, weekday: 1, weekNo: 2).length,
        0,
      );
      expect(
        ScheduleLogic.slotsOf(courses, secs, weekday: 1, weekNo: 3).length,
        1,
      );
    });

    test('空 weeks = 每周都上', () {
      final courses = [
        Course(
          id: 'c',
          name: 'x',
          sessions: const [
            CourseSession(weekday: 2, startSection: 2, endSection: 2),
          ],
        ),
      ];
      expect(
        ScheduleLogic.slotsOf(courses, secs, weekday: 2, weekNo: 9).length,
        1,
      );
    });

    test('一门课多时段：不同天各成一块，且互不影响周次', () {
      final courses = [
        Course(
          id: 'c',
          name: '数据结构',
          sessions: const [
            CourseSession(weekday: 1, startSection: 3, endSection: 4, weeks: [1, 2]),
            CourseSession(weekday: 3, startSection: 3, endSection: 4, weeks: [3]),
          ],
        ),
      ];
      expect(ScheduleLogic.slotsOf(courses, secs, weekday: 1, weekNo: 1).length, 1);
      expect(ScheduleLogic.slotsOf(courses, secs, weekday: 3, weekNo: 1).length, 0);
      expect(ScheduleLogic.slotsOf(courses, secs, weekday: 3, weekNo: 3).length, 1);
    });

    test('slotsOnDate：按真实日期取当天课程', () {
      final term = Term(id: 't', name: '秋', start: '2026-09-02', end: '2027-01-10');
      final courses = [
        Course(
          id: 'c',
          name: 'x',
          sessions: const [
            CourseSession(weekday: 1, startSection: 1, endSection: 1),
          ],
        ),
      ];
      // 2026-09-07 是周一、第 2 周
      final slots = ScheduleLogic.slotsOnDate(
        courses,
        secs,
        term,
        DateTime.parse('2026-09-07'),
      );
      expect(slots.length, 1);
      // 周日没有课
      expect(
        ScheduleLogic.slotsOnDate(courses, secs, term, DateTime.parse('2026-09-13')).length,
        0,
      );
      // 没有学期 → 空
      expect(
        ScheduleLogic.slotsOnDate(courses, secs, null, DateTime.parse('2026-09-07')).length,
        0,
      );
    });
  });

  group('课程配色', () {
    test('同名课程颜色稳定；不同名通常不同', () {
      const a = Course(id: '1', name: '数据结构');
      const b = Course(id: '2', name: '数据结构');
      expect(ScheduleLogic.colorOf(a), ScheduleLogic.colorOf(b));
    });

    test('用户指定的颜色优先', () {
      const c = Course(id: '1', name: 'x', color: '#123456');
      expect(ScheduleLogic.colorOf(c).toARGB32(), 0xFF123456);
    });

    test('浅底文字能被压暗（保证可读）', () {
      const c = Course(id: '1', name: 'x');
      final bg = ScheduleLogic.colorOf(c);
      final fg = ScheduleLogic.textColorOf(bg);
      expect(
        HSLColor.fromColor(fg).lightness,
        lessThan(HSLColor.fromColor(bg).lightness),
      );
    });
  });

  group('旧课程数据迁移', () {
    test('只有 weekday/startTime/endTime/weeks 的旧 JSON → 迁移成一个时段', () {
      final c = Course.fromJson({
        'id': 'c1',
        'name': '高数',
        'teacher': '张老师',
        'classroom': 'A101',
        'weekday': 3,
        'startTime': '08:00',
        'endTime': '09:40',
        'weeks': [1, 2, 3],
      });
      expect(c.sessions.length, 1);
      expect(c.sessions.first.weekday, 3);
      expect(c.sessions.first.classroom, 'A101');
      expect(c.sessions.first.weeks, [1, 2, 3]);
      expect(c.sessions.first.startTime, '08:00');
      // 兼容 getter 仍然可用
      expect(c.classroom, 'A101');
      expect(c.weekday, 3);
      expect(c.weeks, [1, 2, 3]);
    });

    test('新结构往返：多时段不丢信息', () {
      const c = Course(
        id: 'c1',
        name: 'x',
        color: '#E8E3FA',
        sessions: [
          CourseSession(
            weekday: 2,
            startSection: 3,
            endSection: 4,
            weeks: [1, 2],
            classroom: 'B201',
          ),
          CourseSession(weekday: 4, startSection: 1, endSection: 1),
        ],
      );
      final back = Course.fromJson(c.toJson());
      expect(back.sessions.length, 2);
      expect(back.sessions.first.endSection, 4);
      expect(back.sessions.first.weeks, [1, 2]);
      expect(back.sessions.first.classroom, 'B201');
      expect(back.sessions[1].weekday, 4);
      expect(back.color, '#E8E3FA');
    });

    test('完全没有 sessions 字段也不崩（给一个空时段）', () {
      final c = Course.fromJson(const {'id': 'x', 'name': 'y'});
      expect(c.sessions.length, 1);
      expect(c.primarySession.classroom, '');
    });
  });

  group('作息表', () {
    test('默认作息表是 11 节且节次连续', () {
      expect(kDefaultSections.length, 11);
      for (var i = 0; i < kDefaultSections.length; i++) {
        expect(kDefaultSections[i].index, i + 1);
      }
    });

    test('第 1 节时间与用户课表一致', () {
      expect(kDefaultSections.first.start, '08:50');
      expect(kDefaultSections.first.end, '09:35');
    });

    test('JSON 往返', () {
      final back = SectionTime.fromJson(
        const SectionTime(index: 3, start: '10:40', end: '11:25').toJson(),
      );
      expect(back.index, 3);
      expect(back.label, '10:40-11:25');
    });
  });
}
