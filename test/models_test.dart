import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/diary/diary_models.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/calendar/lunar_calendar.dart';
import 'package:allone/features/calendar/holiday_data.dart';
import 'package:allone/features/ledger/ledger_models.dart';

void main() {
  group('通用模型', () {
    test('MediaAttachment JSON 往返', () {
      const m = MediaAttachment(
        type: MediaType.photo,
        file: 'a.jpg',
        size: 123,
      );
      final restored = MediaAttachment.fromJson(m.toJson());
      expect(restored.type, MediaType.photo);
      expect(restored.file, 'a.jpg');
      expect(restored.size, 123);
    });

    test('TimeStamp / LocationStamp JSON 往返', () {
      const ts = TimeStamp(enabled: true, nodeDate: '2027-02-20', pinTop: true);
      final ts2 = TimeStamp.fromJson(ts.toJson());
      expect(ts2.enabled, true);
      expect(ts2.nodeDate, '2027-02-20');
      expect(ts2.pinTop, true);

      const loc = LocationStamp(
        enabled: true,
        lat: 30.6,
        lng: 104.06,
        name: '家',
      );
      final loc2 = LocationStamp.fromJson(loc.toJson());
      expect(loc2.lat, 30.6);
      expect(loc2.name, '家');
    });

    test('AppTime.dateOnly 格式化', () {
      expect(AppTime.dateOnly(DateTime(2026, 8, 20)), '2026-08-20');
    });
  });

  group('日记模型', () {
    test('DiaryEntry JSON 往返', () {
      final e = DiaryEntry(
        id: 'id1',
        title: '标题',
        plainText: '正文',
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20, 1),
        timeStamp: const TimeStamp(enabled: true, nodeDate: '2027-02-20'),
        tags: const ['生活'],
        media: const [
          MediaAttachment(type: MediaType.audio, file: 'r.m4a', size: 10),
        ],
      );
      final restored = DiaryEntry.fromJson(e.toJson());
      expect(restored.id, 'id1');
      expect(restored.title, '标题');
      expect(restored.timeStamp.nodeDate, '2027-02-20');
      expect(restored.tags, ['生活']);
      expect(restored.media.length, 1);
      expect(restored.media.first.type, MediaType.audio);
      expect(restored.plainText, '正文');
    });
  });

  group('待办模型', () {
    test('TodoItem JSON 往返', () {
      final t = TodoItem(
        id: 't1',
        title: '任务',
        contentPlain: '任务内容',
        deadline: const DeadlineInfo(
          date: '2026-08-25',
          time: '18:00',
          color: '#E5484D',
          highlight: true,
        ),
        location: const LocationInfo(text: '图书馆', highlight: true),
        status: TodoStatus.pending,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      final restored = TodoItem.fromJson(t.toJson());
      expect(restored.deadline.date, '2026-08-25');
      expect(restored.deadline.highlight, true);
      expect(restored.location.text, '图书馆');
      expect(restored.status, TodoStatus.pending);
      expect(restored.contentPlain, '任务内容');
    });

    test('TodoItem 树形 JSON 往返（含子任务嵌套）', () {
      final t = TodoItem(
        id: 't1',
        title: '任务链',
        contentPlain: '顶层内容',
        status: TodoStatus.pending,
        children: [
          TodoItem(
            id: 't1-c1',
            title: '子任务 1',
            contentPlain: '子内容',
            deadline: const DeadlineInfo(date: '2026-08-26'),
            status: TodoStatus.pending,
            children: [
              TodoItem(
                id: 't1-c1-g1',
                title: '孙任务',
                status: TodoStatus.done,
                createdAt: DateTime(2026, 8, 20),
                updatedAt: DateTime(2026, 8, 20),
              ),
            ],
            createdAt: DateTime(2026, 8, 20),
            updatedAt: DateTime(2026, 8, 20),
          ),
          TodoItem(
            id: 't1-c2',
            title: '子任务 2（完成）',
            status: TodoStatus.done,
            createdAt: DateTime(2026, 8, 20),
            updatedAt: DateTime(2026, 8, 20),
          ),
        ],
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      final restored = TodoItem.fromJson(t.toJson());
      expect(restored.title, '任务链');
      expect(restored.hasChildren, true);
      expect(restored.children.length, 2);
      expect(restored.children[0].children.length, 1);
      expect(restored.children[0].children[0].title, '孙任务');
      expect(restored.children[0].children[0].status, TodoStatus.done);
      // 进度：直接子任务 2 个中完成 1 个
      expect(restored.progress, closeTo(1 / 2, 0.0001));
    });

    test('TodoItem 无子任务为普通待办', () {
      final t = TodoItem(
        id: 't2',
        title: '普通待办',
        contentPlain: '任务内容',
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      expect(t.hasChildren, false);
      expect(t.progress, 0);
      final restored = TodoItem.fromJson(t.toJson());
      expect(restored.hasChildren, false);
      expect(restored.contentPlain, '任务内容');
    });

    test('TodoTemplate JSON 往返', () {
      final t = TodoTemplate(
        id: 'tp1',
        name: '周报',
        title: '周报',
        contentPlain: '周报内容',
        deadline: const DeadlineInfo(
          date: '2026-08-28',
          time: '18:00',
          color: '#E5484D',
          highlight: true,
        ),
        location: const LocationInfo(text: '办公室'),
        tags: const ['工作'],
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      final restored = TodoTemplate.fromJson(t.toJson());
      expect(restored.name, '周报');
      expect(restored.deadline.date, '2026-08-28');
      expect(restored.deadline.highlight, true);
      expect(restored.location.text, '办公室');
      expect(restored.tags, ['工作']);
    });
  });

  group('习惯模型', () {
    test('Habit JSON 往返', () {
      final h = Habit(
        id: 'h1',
        title: '阅读',
        category: '学习',
        target: const HabitTarget(type: HabitType.duration, value: 30),
        description: '每天读 30 分钟',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final restored = Habit.fromJson(h.toJson());
      expect(restored.target.type, HabitType.duration);
      expect(restored.target.value, 30);
      expect(restored.description, '每天读 30 分钟');
    });

    test('CheckinMap 连续打卡统计', () {
      final cm = CheckinMap.fromJson({
        '2026-08-18': 1,
        '2026-08-19': 1,
        '2026-08-20': 1,
      });
      expect(cm.totalDays, 3);
      expect(cm.streakDays(DateTime(2026, 8, 20)), 3);
    });
  });

  group('农历与节假日', () {
    test('2026-02-17 为农历正月初一（春节）', () {
      final l = LunarCalendar.solarToLunar(DateTime(2026, 2, 17));
      expect(l.month, 1);
      expect(l.day, 1);
    });

    test('内置节假日包含春节 / 中秋 / 国庆等', () {
      final holidays = HolidayProvider.builtInHolidaysForYear(2026);
      final names = holidays.map((h) => h.name).toSet();
      expect(names.contains('春节'), isTrue);
      expect(names.contains('中秋节'), isTrue);
      expect(names.contains('国庆节'), isTrue);
      expect(names.contains('元旦'), isTrue);
      expect(names.contains('端午节'), isTrue);
      // 春节在 1–2 月
      final chunjie = holidays.where((h) => h.name == '春节').first;
      expect(chunjie.date.substring(5, 7), anyOf('01', '02'));
      // 全部为 holiday 类型
      expect(holidays.every((h) => h.type == 'holiday'), isTrue);
    });
  });

  group('记账设置', () {
    test('LedgerSettings JSON 往返', () {
      const s = LedgerSettings(monthlyBudget: 2000);
      final restored = LedgerSettings.fromJson(s.toJson());
      expect(restored.monthlyBudget, 2000);
    });

    test('LedgerSettings 空/默认容错', () {
      final restored = LedgerSettings.fromJson(null);
      expect(restored.monthlyBudget, 0);
    });
  });
}
