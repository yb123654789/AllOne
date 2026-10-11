import '../../core/models/common.dart';
import '../quest/quest_models.dart';
import '../schedule/schedule_logic.dart';
import '../schedule/schedule_models.dart';
import '../todo/todo_models.dart';

/// 日程表里一条目的类型
enum DayKind { course, todo, quest, milestone }

extension DayKindX on DayKind {
  String get label {
    switch (this) {
      case DayKind.course:
        return '课程';
      case DayKind.todo:
        return '待办';
      case DayKind.quest:
        return '任务';
      case DayKind.milestone:
        return '里程碑';
    }
  }
}

/// 日程表里的一条（课程 / 待办 / 任务 / 里程碑）
class DayItem {
  final DayKind kind;

  /// 对应业务对象的 id（待办 id / 任务 id / 课程 id）
  final String refId;

  /// 里程碑条目时：所属任务 id 与该里程碑 id
  final String questId;
  final String milestoneId;

  final String title;

  /// 副信息：地点 / 教室 / 分类
  final String subtitle;

  /// 开始时间 HH:mm；**空 = 没有精确时分**（进「待安排」区）
  final String time;

  /// 结束时间 HH:mm（课程用）
  final String endTime;

  final bool done;

  const DayItem({
    required this.kind,
    required this.refId,
    this.questId = '',
    this.milestoneId = '',
    required this.title,
    this.subtitle = '',
    this.time = '',
    this.endTime = '',
    this.done = false,
  });

  bool get hasTime => time.isNotEmpty;

  /// 时间文案：`09:40-10:25` / `09:40`
  String get timeLabel {
    if (time.isEmpty) return '';
    if (endTime.isEmpty) return time;
    return '$time-$endTime';
  }
}

/// 一天的日程：有时间的（时间轴）+ 没有精确时分的（可再安排）
class DayPlan {
  final List<DayItem> timed;
  final List<DayItem> untimed;

  const DayPlan({this.timed = const [], this.untimed = const []});

  bool get isEmpty => timed.isEmpty && untimed.isEmpty;

  int get total => timed.length + untimed.length;
}

/// 把「课程 + 待办 + 任务 + 里程碑」拼成**当天日程表**。
///
/// 抽成纯函数是为了能直接单测（时间排序、无时分归类、完成/归档过滤）。
/// 界面只负责画时间轴与「待安排」区。
class DaySchedule {
  const DaySchedule._();

  static DayPlan build({
    required DateTime day,
    required List<TodoItem> todos,
    required List<Quest> quests,
    required List<Course> courses,
    required List<SectionTime> sections,
    Term? term,
  }) {
    final date = AppTime.dateOnly(day);
    final timed = <DayItem>[];
    final untimed = <DayItem>[];

    // ① 课程：按节次时间（作息表给出）
    for (final slot in ScheduleLogic.slotsOnDate(courses, sections, term, day)) {
      final a = _sectionTime(sections, slot.startSection);
      final b = _sectionTime(sections, slot.endSection);
      var start = a?.start ?? '';
      var end = b?.end ?? '';
      // 旧数据的自定义时间优先（否则会显示成作息表时间，与用户填的不符）
      if (slot.session.hasCustomTime) {
        start = slot.session.startTime.isNotEmpty
            ? slot.session.startTime
            : start;
        end = slot.session.endTime.isNotEmpty ? slot.session.endTime : end;
      }
      timed.add(
        DayItem(
          kind: DayKind.course,
          refId: slot.course.id,
          title: slot.course.name.isEmpty ? '（未命名课程）' : slot.course.name,
          subtitle: slot.session.classroom,
          time: start,
          endTime: end,
        ),
      );
    }

    // ② 待办：今天截止（未完成）
    for (final t in todos) {
      if (t.status == TodoStatus.done || t.status == TodoStatus.archived) {
        continue;
      }
      if (t.deadline.date != date) continue;
      final item = DayItem(
        kind: DayKind.todo,
        refId: t.id,
        title: t.title.isEmpty ? '（无标题待办）' : t.title,
        subtitle: t.location.text,
        time: t.deadline.time,
      );
      (item.hasTime ? timed : untimed).add(item);
    }

    // ③ 任务：目标日期是今天，且还在推进
    for (final q in quests) {
      if (!q.isLive || q.targetDate != date) continue;
      final item = DayItem(
        kind: DayKind.quest,
        refId: q.id,
        questId: q.id,
        title: q.title.isEmpty ? '未命名任务' : q.title,
        subtitle: q.category,
        time: q.time,
      );
      (item.hasTime ? timed : untimed).add(item);
    }

    // ④ 里程碑：计划日期是今天且未完成
    for (final q in quests) {
      if (q.archived) continue;
      for (final m in q.milestones) {
        if (m.done || m.dueDate != date) continue;
        final item = DayItem(
          kind: DayKind.milestone,
          refId: q.id,
          questId: q.id,
          milestoneId: m.id,
          title: m.title.isEmpty ? '未命名里程碑' : m.title,
          subtitle: q.title.isEmpty ? '未命名任务' : q.title,
          time: m.time,
        );
        (item.hasTime ? timed : untimed).add(item);
      }
    }

    timed.sort((a, b) {
      final c = a.time.compareTo(b.time);
      if (c != 0) return c;
      return a.kind.index.compareTo(b.kind.index);
    });
    untimed.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      return a.title.compareTo(b.title);
    });

    return DayPlan(timed: timed, untimed: untimed);
  }

  static SectionTime? _sectionTime(List<SectionTime> sections, int index) {
    for (final s in sections) {
      if (s.index == index) return s;
    }
    return null;
  }
}
