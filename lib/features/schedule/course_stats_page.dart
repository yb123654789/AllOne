import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'course_edit_page.dart';
import 'schedule_logic.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 课程统计页：列出全部课程及其**全部时段**。
///
/// 入口在工具页（「课程表 · 课程统计」）；这里同时也是课程的编辑入口
/// —— 点任意一条即可改课程名 / 时段 / 周次。
class CourseStatsPage extends ConsumerWidget {
  const CourseStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses =
        ref.watch(courseListProvider).valueOrNull ?? const <Course>[];
    final sections =
        ref.watch(sectionListProvider).valueOrNull ?? kDefaultSections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程统计'),
        actions: [
          IconButton(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CourseEditPage()),
            ),
          ),
        ],
      ),
      body: courses.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有课程。\n\n点右上角「+」添加：选星期、第几节、上哪些周即可，'
                  '不用手填时间。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.8,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                for (final c in courses) _card(context, c, sections),
              ],
            ),
    );
  }

  Widget _card(BuildContext context, Course c, List<SectionTime> sections) {
    final bg = ScheduleLogic.colorOf(c);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CourseEditPage(course: c)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.name.isEmpty ? '（未命名课程）' : c.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (c.teacher.isNotEmpty)
                    Text(
                      c.teacher,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final s in c.sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '周${_cn(s.weekday)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ScheduleLogic.sectionLabel(s, sections)}'
                              '${s.classroom.isEmpty ? '' : ' · ${s.classroom}'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Text(
                              '${ScheduleLogic.clockOf(s, sections)}'
                              ' · ${_weeksLabel(s.weeks)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (c.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  c.notes.trim().replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _cn(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][(weekday - 1).clamp(0, 6)];

  /// 周次文案：`1-16 周` / `1,3,5 周` / `每周`
  static String _weeksLabel(List<int> weeks) {
    if (weeks.isEmpty) return '每周';
    final sorted = [...weeks]..sort();
    final contiguous =
        sorted.last - sorted.first == sorted.length - 1;
    if (contiguous) return '第 ${sorted.first}-${sorted.last} 周';
    if (sorted.length <= 6) return '第 ${sorted.join(',')} 周';
    return '第 ${sorted.first}…${sorted.last} 周（共 ${sorted.length} 周）';
  }
}
