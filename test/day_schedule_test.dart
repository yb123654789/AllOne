import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/calendar/day_schedule.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/schedule/schedule_models.dart';
import 'package:allone/features/todo/todo_models.dart';

/// 当天日程表的构建逻辑测试。
///
/// 规则：有精确时分的进**时间轴**（按时间排序），没有的进**待安排**区
/// （界面上可以给它安排时间）；已完成 / 已归档 / 已放弃的不出现。
void main() {
  final day = DateTime.parse('2026-10-12'); // 周一
  const sections = kDefaultSections;
  // 2026-09-02 开学 → 2026-10-12 是第 7 周
  const term = Term(id: 't', name: '秋', start: '2026-09-02', end: '2027-01-10');

  TodoItem todo(
    String id, {
    String time = '',
    String date = '2026-10-12',
    TodoStatus status = TodoStatus.pending,
  }) => TodoItem(
    id: id,
    title: '待办$id',
    status: status,
    deadline: DeadlineInfo(date: date, time: time),
    createdAt: DateTime.parse('2026-10-01T00:00:00'),
    updatedAt: DateTime.parse('2026-10-01T00:00:00'),
  );

  Quest quest(
    String id, {
    String time = '',
    String target = '2026-10-12',
    List<Milestone> milestones = const [],
    QuestStatus status = QuestStatus.active,
  }) => Quest(
    id: id,
    title: '任务$id',
    status: status,
    targetDate: target,
    time: time,
    milestones: milestones,
    createdAt: DateTime.parse('2026-09-01T00:00:00'),
    updatedAt: DateTime.parse('2026-09-01T00:00:00'),
  );

  Course course(String id, {int weekday = 1, int start = 3, int end = 4}) =>
      Course(
        id: id,
        name: '课程$id',
        sessions: [
          CourseSession(
            weekday: weekday,
            startSection: start,
            endSection: end,
            classroom: 'A101',
          ),
        ],
      );

  DayPlan build({
    List<TodoItem> todos = const [],
    List<Quest> quests = const [],
    List<Course> courses = const [],
    Term? term = term,
  }) => DaySchedule.build(
    day: day,
    todos: todos,
    quests: quests,
    courses: courses,
    sections: sections,
    term: term,
  );

  test('课程按作息表时间进时间轴（连堂取首末节时间）', () {
    final plan = build(courses: [course('c1')]);
    expect(plan.timed.length, 1);
    final item = plan.timed.first;
    expect(item.kind, DayKind.course);
    expect(item.title, '课程c1');
    expect(item.time, '10:40'); // 第 3 节开始
    expect(item.endTime, '12:15'); // 第 4 节结束
    expect(item.subtitle, 'A101');
  });

  test('没有学期时不排课程（weekNo 算不出来）', () {
    expect(build(courses: [course('c1')], term: null).timed, isEmpty);
  });

  test('待办：有时间的进时间轴，没时间的进「待安排」', () {
    final plan = build(todos: [todo('a', time: '09:00'), todo('b')]);
    expect(plan.timed.map((e) => e.refId), ['a']);
    expect(plan.untimed.map((e) => e.refId), ['b']);
  });

  test('待办：已完成 / 已归档 / 不是今天的都不出现', () {
    final plan = build(
      todos: [
        todo('done', time: '09:00', status: TodoStatus.done),
        todo('arch', time: '09:00', status: TodoStatus.archived),
        todo('otherDay', time: '09:00', date: '2026-10-13'),
        todo('today', time: '09:00'),
      ],
    );
    expect(plan.timed.map((e) => e.refId), ['today']);
    expect(plan.total, 1);
  });

  test('任务：目标日期是今天才出现；有时间的进时间轴', () {
    final plan = build(
      quests: [
        quest('q1', time: '20:00'),
        quest('q2'),
        quest('q3', target: '2026-10-20', time: '08:00'),
      ],
    );
    expect(plan.timed.map((e) => e.refId), ['q1']);
    expect(plan.untimed.map((e) => e.refId), ['q2']);
  });

  test('已放弃 / 已完成 / 回收站里的任务不出现', () {
    final plan = build(
      quests: [
        quest('done', time: '09:00', status: QuestStatus.done),
        quest('dropped', time: '09:00', status: QuestStatus.dropped),
        quest('live', time: '09:00'),
      ],
    );
    expect(plan.timed.map((e) => e.refId), ['live']);
  });

  test('里程碑：计划日期是今天且未完成', () {
    final plan = build(
      quests: [
        quest(
          'q1',
          milestones: const [
            Milestone(id: 'm1', title: '写完初稿', dueDate: '2026-10-12', time: '14:00'),
            Milestone(id: 'm2', title: '待安排里程碑', dueDate: '2026-10-12'),
            Milestone(id: 'm3', title: '已完成', dueDate: '2026-10-12', done: true),
            Milestone(id: 'm4', title: '别的日子', dueDate: '2026-11-01', time: '10:00'),
          ],
        ),
      ],
    );
    expect(plan.timed.map((e) => e.milestoneId), ['m1']);
    // 待安排区：任务本身（无时间）+ 里程碑 m2
    expect(
      plan.untimed.where((e) => e.kind == DayKind.milestone).map((e) => e.milestoneId),
      ['m2'],
    );
    expect(plan.untimed.where((e) => e.kind == DayKind.quest).length, 1);
    expect(plan.timed.first.questId, 'q1');
    expect(plan.timed.first.subtitle, '任务q1');
  });

  test('时间轴按时间升序（课程 / 待办 / 任务 / 里程碑混排）', () {
    final plan = build(
      todos: [todo('t1', time: '09:00'), todo('t2', time: '07:30')],
      quests: [quest('q1', time: '06:00')],
      courses: [course('c1')], // 10:40
    );
    expect(plan.timed.map((e) => e.time), [
      '06:00',
      '07:30',
      '09:00',
      '10:40',
    ]);
  });

  test('时间相同的排序稳定（按类型：课程 → 待办 → 任务 → 里程碑）', () {
    final plan = build(
      todos: [todo('t1', time: '09:00')],
      quests: [quest('q1', time: '09:00')],
      courses: [
        Course(
          id: 'c1',
          name: '同时段课',
          sessions: const [
            CourseSession(weekday: 1, startSection: 1, endSection: 1),
          ],
        ),
      ], // 第 1 节 08:50 → 不是 9:00
    );
    final nine = plan.timed.where((e) => e.time == '09:00').toList();
    expect(nine.map((e) => e.kind), [DayKind.todo, DayKind.quest]);
  });

  test('待安排区按类型 + 标题排序', () {
    final plan = build(
      todos: [todo('b'), todo('a')],
      quests: [quest('q1')],
    );
    expect(plan.untimed.map((e) => e.kind), [
      DayKind.todo,
      DayKind.todo,
      DayKind.quest,
    ]);
    expect(plan.untimed.first.title, '待办a');
  });

  test('旧课程的自定义时间优先（不漏掉用户填的时间）', () {
    final legacy = Course.fromJson(const {
      'id': 'old',
      'name': '旧课',
      'weekday': 1,
      'startTime': '08:00',
      'endTime': '09:40',
    });
    final plan = build(courses: [legacy]);
    expect(plan.timed.first.time, '08:00');
    expect(plan.timed.first.endTime, '09:40');
  });

  test('空日程不报错', () {
    final plan = build();
    expect(plan.isEmpty, isTrue);
    expect(plan.total, 0);
  });
}
