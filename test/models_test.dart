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
    test('Habit JSON 往返（含三维度）', () {
      final h = Habit(
        id: 'h1',
        title: '阅读',
        category: '学习',
        frequency: HabitFrequency.weekly,
        weekdays: [1, 3, 5],
        dailyTarget: HabitDailyTarget.minutes,
        dailyTargetValue: 30,
        persistence: HabitPersistence.days,
        persistenceValue: 21,
        description: '每天读 30 分钟',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final restored = Habit.fromJson(h.toJson());
      expect(restored.frequency, HabitFrequency.weekly);
      expect(restored.weekdays, [1, 3, 5]);
      expect(restored.dailyTarget, HabitDailyTarget.minutes);
      expect(restored.dailyTargetValue, 30);
      expect(restored.persistence, HabitPersistence.days);
      expect(restored.persistenceValue, 21);
      expect(restored.description, '每天读 30 分钟');
    });

    test('旧数据兼容：target(天数) 迁移为坚持 days', () {
      final h = Habit.fromJson({
        'id': 'old1',
        'title': '旧习惯',
        'category': '通用',
        'target': {'type': 'duration', 'value': 30},
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(h.persistence, HabitPersistence.days);
      expect(h.persistenceValue, 30);
      // 未写新字段时使用默认值
      expect(h.frequency, HabitFrequency.daily);
      expect(h.dailyTarget, HabitDailyTarget.once);
    });

    test('旧数据兼容：target(次数) 迁移为坚持 times', () {
      final h = Habit.fromJson({
        'id': 'old2',
        'title': '旧习惯',
        'category': '通用',
        'target': {'type': 'count', 'value': 100},
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(h.persistence, HabitPersistence.times);
      expect(h.persistenceValue, 100);
    });

    test('Habit archived 字段 JSON 往返与默认值', () {
      // 默认未归档
      final def = Habit(
        id: 'h1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(def.archived, isFalse);
      // 往返保留
      final archived = def.copyWith(archived: true);
      final restored = Habit.fromJson(archived.toJson());
      expect(restored.archived, isTrue);
      // 旧数据无 archived 字段时默认 false（不失效）
      final legacy = Habit.fromJson({
        'id': 'old3',
        'title': '旧习惯',
        'category': '通用',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(legacy.archived, isFalse);
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

    test('CheckinMap dayMet 按当天目标判定', () {
      // 定量：每天需累计 8
      final q = CheckinMap.fromJson({'2026-08-18': 5, '2026-08-19': 8});
      expect(q.dayMet('2026-08-18', HabitDailyTarget.quantity, 8), isFalse);
      expect(q.dayMet('2026-08-19', HabitDailyTarget.quantity, 8), isTrue);
      // 时长：每天需累计 30 分钟
      final m = CheckinMap.fromJson({'2026-08-18': 30});
      expect(m.dayMet('2026-08-18', HabitDailyTarget.minutes, 30), isTrue);
      expect(m.dayMet('2026-08-18', HabitDailyTarget.minutes, 60), isFalse);
      // 一次即完成
      final o = CheckinMap.fromJson({'2026-08-18': 1});
      expect(o.dayMet('2026-08-18', HabitDailyTarget.once, 1), isTrue);
    });

    test('CheckinMap 失败打卡不计入完成与连续', () {
      final cm = CheckinMap.fromJson({
        '2026-08-18': 1,
        '2026-08-19': -1, // 失败
        '2026-08-20': 1,
      });
      expect(cm.totalCount, 2); // 排除失败
      expect(cm.totalDays, 2); // 排除失败
      expect(cm.failedDays, 1);
      expect(cm.isDone('2026-08-18'), isTrue);
      expect(cm.isFailed('2026-08-19'), isTrue);
      expect(cm.hasRecord('2026-08-19'), isTrue);
      // 19 号失败会中断连续，从 20 号往前只有 20 号本身算 1 天
      expect(cm.streakDays(DateTime(2026, 8, 20)), 1);
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
