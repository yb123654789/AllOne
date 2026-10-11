import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../quest/quest_detail_page.dart';
import '../quest/quest_models.dart';
import '../quest/quest_repository.dart';
import '../schedule/course_edit_page.dart';
import '../schedule/schedule_models.dart';
import '../schedule/schedule_repository.dart';
import '../todo/todo_edit_page.dart';
import '../todo/todo_models.dart';
import '../todo/todo_repository.dart';
import 'day_schedule.dart';

/// 日历「当天」里的**日程表**：课程 + 待办 + 任务 + 里程碑。
///
/// - 有精确时分的排成**时间轴**；没有的进「待安排」区，
///   并可以**直接给它安排一个时间**（写回原条目：待办的截止时间 / 任务的时间 / 里程碑的时间）；
/// - 每条都能点回**原来的位置**去处理（待办 → 待办编辑页、任务/里程碑 → 任务详情页、
///   课程 → 课程编辑页）；待办还能在这里直接勾选完成。
class DayScheduleView extends ConsumerWidget {
  const DayScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todoListProvider).valueOrNull ?? const <TodoItem>[];
    final quests = ref.watch(questListProvider).valueOrNull ?? const <Quest>[];
    final courses =
        ref.watch(courseListProvider).valueOrNull ?? const <Course>[];
    final sections =
        ref.watch(sectionListProvider).valueOrNull ?? kDefaultSections;
    final term = ref.watch(currentTermProvider);

    final day = DateTime.now();
    final plan = DaySchedule.build(
      day: day,
      todos: todos,
      quests: quests,
      courses: courses,
      sections: sections,
      term: term,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('今天日程（${plan.total}）'),
        if (plan.timed.isEmpty)
          _hint('今天没有定时的安排')
        else
          for (final item in plan.timed) _timedTile(context, ref, item),
        if (plan.untimed.isNotEmpty) ...[
          _header('没有精确时分（${plan.untimed.length}）'),
          for (final item in plan.untimed) _untimedTile(context, ref, item),
        ],
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
    ),
  );

  // ── 时间轴 ──────────────────────────────────────────────────────────────

  Widget _timedTile(BuildContext context, WidgetRef ref, DayItem item) {
    final color = _colorOf(item.kind);
    return InkWell(
      onTap: () => _open(context, ref, item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间列
            SizedBox(
              width: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.time,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.endTime.isNotEmpty)
                    Text(
                      item.endTime,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // 左侧色条
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_iconOf(item.kind), size: 14, color: color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // 待办可以直接在这里勾完
            if (item.kind == DayKind.todo)
              IconButton(
                tooltip: '标记完成',
                iconSize: 20,
                icon: const Icon(Icons.radio_button_unchecked),
                onPressed: () => ref
                    .read(todoListProvider.notifier)
                    .setStatus(item.refId, TodoStatus.done),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ── 没有精确时分：可以在这里安排时间 ────────────────────────────────────

  Widget _untimedTile(BuildContext context, WidgetRef ref, DayItem item) {
    final color = _colorOf(item.kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(_iconOf(item.kind), size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _open(context, ref, item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    '${item.kind.label}'
                    '${item.subtitle.isEmpty ? '' : ' · ${item.subtitle}'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.schedule, size: 16),
            label: const Text('安排时间'),
            onPressed: () => _scheduleTime(context, ref, item),
          ),
        ],
      ),
    );
  }

  /// 给「没有精确时分」的条目安排一个时间，写回原条目
  Future<void> _scheduleTime(
    BuildContext context,
    WidgetRef ref,
    DayItem item,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '给「${item.title}」安排时间',
    );
    if (picked == null) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}'
        ':${picked.minute.toString().padLeft(2, '0')}';

    switch (item.kind) {
      case DayKind.todo:
        final todos =
            ref.read(todoListProvider).valueOrNull ?? const <TodoItem>[];
        TodoItem? target;
        for (final t in todos) {
          if (t.id == item.refId) target = t;
        }
        if (target == null) return;
        final t = target;
        await ref
            .read(todoListProvider.notifier)
            .saveItem(
              t.copyWith(
                deadline: DeadlineInfo(
                  date: t.deadline.date,
                  time: hhmm,
                  color: t.deadline.color,
                  highlight: t.deadline.highlight,
                ),
                updatedAt: DateTime.now(),
              ),
            );
      case DayKind.quest:
        await ref.read(questListProvider.notifier).setTime(item.questId, hhmm);
      case DayKind.milestone:
        await ref
            .read(questListProvider.notifier)
            .setMilestoneTime(item.questId, item.milestoneId, hhmm);
      case DayKind.course:
        return; // 课程的时间由作息表决定，不在这里安排
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已安排在 $hhmm')));
  }

  // ── 跳回原处 ────────────────────────────────────────────────────────────

  void _open(BuildContext context, WidgetRef ref, DayItem item) {
    switch (item.kind) {
      case DayKind.course:
        final courses =
            ref.read(courseListProvider).valueOrNull ?? const <Course>[];
        Course? c;
        for (final x in courses) {
          if (x.id == item.refId) c = x;
        }
        if (c == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CourseEditPage(course: c)),
        );
      case DayKind.todo:
        final todos =
            ref.read(todoListProvider).valueOrNull ?? const <TodoItem>[];
        TodoItem? t;
        for (final x in todos) {
          if (x.id == item.refId) t = x;
        }
        if (t == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TodoEditPage(item: t)),
        );
      case DayKind.quest:
      case DayKind.milestone:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuestDetailPage(questId: item.questId),
          ),
        );
    }
  }

  // ── 样式 ────────────────────────────────────────────────────────────────

  static IconData _iconOf(DayKind kind) {
    switch (kind) {
      case DayKind.course:
        return Icons.school;
      case DayKind.todo:
        return Icons.check_circle_outline;
      case DayKind.quest:
        return Icons.flag_outlined;
      case DayKind.milestone:
        return Icons.emoji_events_outlined;
    }
  }

  static Color _colorOf(DayKind kind) {
    switch (kind) {
      case DayKind.course:
        return const Color(0xFF7C3AED);
      case DayKind.todo:
        return AppTheme.primary;
      case DayKind.quest:
        return const Color(0xFF30A46C);
      case DayKind.milestone:
        return const Color(0xFFF5A623);
    }
  }
}
