import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import 'course_edit_page.dart';
import 'schedule_logic.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 周网格的尺寸参数
const double kAxisWidth = 44; // 左侧节次时间轴宽度
const double kRowHeight = 56; // 每节课的行高
const double kColGap = 2; // 列间距

/// 星期名（周一起始）
const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 课程表入口页：**只做周网格**（照课表截图那种「节次轴 + 色块」排版）。
///
/// 设计变化（2026-10-11）：
/// - 引入**节次**：左侧是节次与时间轴，课程按节次占行（连堂占多行），空间不再局促；
/// - **删掉「按天」排布**：看"今天上什么课"的场景移到「日历 → 当天」的日程表；
/// - **铺满屏幕**：7 列平分可用宽度，手机上也不需要左右平移；
/// - 「课程统计 / 学期管理 / 添加课程」的入口移到**工具页**（这里保持干净）。
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  /// 用户手动翻到的周（null = 跟随「当前周」）
  int? _weekNo;

  @override
  Widget build(BuildContext context) {
    final term = ref.watch(currentTermProvider);
    final courses =
        ref.watch(courseListProvider).valueOrNull ?? const <Course>[];
    final sections =
        ref.watch(sectionListProvider).valueOrNull ?? kDefaultSections;

    if (term == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('课程表')),
        body: _guide(
          '还没有学期。\n\n课程表按「学期」组织（半年一换）：'
          '先去「工具 → 课程表 · 学期管理」建一个学期并填上起止日期，'
          '这里就会自动算出当前是第几周。',
        ),
      );
    }

    final today = DateTime.now();
    final currentWeek = ScheduleLogic.weekNoOf(term, today);
    final total = ScheduleLogic.totalWeeks(term);
    final weekNo = (_weekNo ?? (currentWeek > 0 ? currentWeek : 1)).clamp(
      1,
      total > 0 ? total : 1,
    );
    final monday = ScheduleLogic.mondayOfWeek(term, weekNo) ?? today;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          term.name.isEmpty ? '课程表' : term.name,
          style: const TextStyle(fontSize: 17),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _weekBar(weekNo, total, currentWeek, monday),
        ),
      ),
      body: courses.isEmpty
          ? _guide(
              '这个学期还没有课程。\n\n去「工具 → 课程表 · 添加课程」添加：'
              '选好星期、第几节、上哪些周就行，不用手填时间。',
            )
          : _grid(courses, sections, monday, weekNo),
    );
  }

  Widget _guide(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.8,
          color: AppTheme.textSecondary,
        ),
      ),
    ),
  );

  /// 顶部：第几周 + 翻周 + 本周日期范围
  Widget _weekBar(int weekNo, int total, int currentWeek, DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    String md(DateTime d) =>
        AppTime.dateOnly(d).substring(5).replaceAll('-', '/');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            icon: const Icon(Icons.chevron_left),
            onPressed: weekNo <= 1
                ? null
                : () => setState(() => _weekNo = weekNo - 1),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weekNo == currentWeek ? '第 $weekNo 周 · 本周' : '第 $weekNo 周',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${md(monday)} ~ ${md(sunday)}'
                  '${total > 0 ? ' · 共 $total 周' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (weekNo != currentWeek && currentWeek > 0)
            TextButton(
              onPressed: () => setState(() => _weekNo = null),
              child: const Text('回到本周'),
            ),
          IconButton(
            tooltip: '下一周',
            icon: const Icon(Icons.chevron_right),
            onPressed: (total > 0 && weekNo >= total)
                ? null
                : () => setState(() => _weekNo = weekNo + 1),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    List<Course> courses,
    List<SectionTime> sections,
    DateTime monday,
    int weekNo,
  ) {
    return Column(
      children: [
        _headerRow(monday),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (ctx, c) {
                final colW = ScheduleLogic.columnWidth(c.maxWidth);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _axis(sections),
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: kColGap),
                      SizedBox(
                        width: colW,
                        child: _dayColumn(
                          courses,
                          sections,
                          monday.add(Duration(days: i)),
                          weekNo,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 日期行：周几 + 日期数字（今天用实心圆标出）
  Widget _headerRow(DateTime monday) {
    final today = AppTime.dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: kAxisWidth),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : kColGap),
                child: _dayHeader(
                  monday.add(Duration(days: i)),
                  AppTime.dateOnly(monday.add(Duration(days: i))) == today,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayHeader(DateTime date, bool isToday) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _weekNames[date.weekday - 1],
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday ? AppTheme.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// 左侧节次时间轴：第几节 + 起止时间
  Widget _axis(List<SectionTime> sections) {
    return SizedBox(
      width: kAxisWidth,
      child: Column(
        children: [
          for (final s in sections)
            Container(
              height: kRowHeight,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${s.index}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.start,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    s.end,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 一天的列：背景行 + 课程块（连堂占多行）
  Widget _dayColumn(
    List<Course> courses,
    List<SectionTime> sections,
    DateTime date,
    int weekNo,
  ) {
    final slots = ScheduleLogic.slotsOf(
      courses,
      sections,
      weekday: date.weekday,
      weekNo: weekNo,
    );
    final maxIndex = sections.isEmpty ? 0 : sections.last.index;
    return SizedBox(
      height: sections.length * kRowHeight,
      child: Stack(
        children: [
          Column(
            children: [
              for (var i = 0; i < sections.length; i++)
                Container(
                  height: kRowHeight,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.divider),
                    ),
                  ),
                ),
            ],
          ),
          for (final s in slots)
            Positioned(
              top: (s.startSection - 1).clamp(0, maxIndex) * kRowHeight + 2,
              height: s.span.clamp(1, sections.length) * kRowHeight - 4,
              left: 0,
              right: 0,
              child: _block(s),
            ),
        ],
      ),
    );
  }

  Widget _block(CourseSlot slot) {
    final bg = ScheduleLogic.colorOf(slot.course);
    final fg = ScheduleLogic.textColorOf(bg);
    final room = slot.session.classroom;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CourseEditPage(course: slot.course)),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.course.name.isEmpty ? '（未命名）' : slot.course.name,
              maxLines: slot.span > 1 ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (room.isNotEmpty && slot.span > 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  room,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: fg, height: 1.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
