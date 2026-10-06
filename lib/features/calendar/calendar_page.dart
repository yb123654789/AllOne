import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import '../diary/diary_models.dart';
import '../diary/diary_repository.dart';
import '../habit/habit_models.dart';
import '../habit/habit_repository.dart';
import '../schedule/schedule_models.dart';
import '../schedule/schedule_repository.dart';
import '../todo/todo_models.dart';
import '../todo/todo_repository.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

/// 日历模块入口页：当天 / 当月 / 当年 三视图聚合。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  int _view = 0; // 0 当天 / 1 当月 / 2 当年

  @override
  Widget build(BuildContext context) {
    final todoAsync = ref.watch(todoListProvider);
    final diaryAsync = ref.watch(diaryListProvider);
    final habitAsync = ref.watch(habitListProvider);
    final checkinAsync = ref.watch(habitCheckinProvider);
    final courseAsync = ref.watch(courseListProvider);
    final specialAsync = ref.watch(specialDayListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('当天')),
                ButtonSegment(value: 1, label: Text('当月')),
                ButtonSegment(value: 2, label: Text('当年')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
              showSelectedIcon: false,
            ),
          ),
        ),
      ),
      body: todoAsync.when(
        data: (todos) => diaryAsync.when(
          data: (diaries) => habitAsync.when(
            data: (habits) => checkinAsync.when(
              data: (checkins) => courseAsync.when(
                data: (courses) => specialAsync.when(
                  data: (specials) => _body(
                    todos,
                    diaries,
                    habits,
                    checkins,
                    courses,
                    specials,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败：$e')),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败：$e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  Widget _body(
    List<TodoItem> todos,
    List<DiaryEntry> diaries,
    List<Habit> habits,
    Map<String, CheckinMap> checkins,
    List<Course> courses,
    List<SpecialDay> specials,
  ) {
    switch (_view) {
      case 0:
        return DayView(
          todos: todos,
          diaries: diaries,
          habits: habits,
          checkins: checkins,
          courses: courses,
        );
      case 1:
        return MonthView(
          todos: todos,
          diaries: diaries,
          checkins: checkins,
          specials: specials,
        );
      case 2:
        return YearView(
          todos: todos,
          diaries: diaries,
          checkins: checkins,
          specials: specials,
        );
      default:
        return const SizedBox();
    }
  }
}

/// —— 当天视图 ——
class DayView extends StatelessWidget {
  final List<TodoItem> todos;
  final List<DiaryEntry> diaries;
  final List<Habit> habits;
  final Map<String, CheckinMap> checkins;
  final List<Course> courses;

  const DayView({
    super.key,
    required this.todos,
    required this.diaries,
    required this.habits,
    required this.checkins,
    required this.courses,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = AppTime.dateOnly(now);

    // 今天待办（未完成），按截止时间排序
    final todayTodos =
        todos
            .where(
              (t) => t.status != TodoStatus.done && t.deadline.date == today,
            )
            .toList()
          ..sort((a, b) => a.deadline.time.compareTo(b.deadline.time));

    // 今天课程
    final todayCourses = courses.where((c) => c.weekday == now.weekday).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // 今天习惯（已打卡 + 待打卡）
    final doneHabits = habits
        .where((h) => (checkins[h.id]?.entries[today] ?? 0) > 0)
        .toList();
    final pendingHabits = habits
        .where((h) => (checkins[h.id]?.entries[today] ?? 0) <= 0)
        .toList();

    // 今天日记（按创建时间排序）
    final todayDiaries =
        diaries.where((d) => AppTime.dateOnly(d.createdAt) == today).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _header('今天日记（${todayDiaries.length}）'),
        if (todayDiaries.isEmpty)
          _empty('今天还没有写日记')
        else
          for (final d in todayDiaries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.menu_book, color: AppTheme.primary),
              title: Text(d.title.isEmpty ? '（无标题）' : d.title),
              subtitle: Text(
                '${d.createdAt.hour.toString().padLeft(2, '0')}:${d.createdAt.minute.toString().padLeft(2, '0')}'
                '${d.tags.isEmpty ? '' : '  ${d.tags.join(' · ')}'}',
              ),
            ),
        _header('待办事项（${todayTodos.length}）'),
        if (todayTodos.isEmpty)
          _empty('今天没有到期待办')
        else
          for (final t in todayTodos)
            ListTile(
              dense: true,
              leading: Icon(Icons.schedule, color: _hex(t.deadline.color)),
              title: Text(t.title.isEmpty ? '（无标题）' : t.title),
              subtitle: Text(
                '${t.deadline.time.isEmpty ? '全天' : t.deadline.time}'
                '${t.location.text.isEmpty ? '' : ' · ${t.location.text}'}',
              ),
            ),
        _header('课程（${todayCourses.length}）'),
        if (todayCourses.isEmpty)
          _empty('今天没有课')
        else
          for (final c in todayCourses)
            ListTile(
              dense: true,
              leading: const Icon(Icons.school, color: AppTheme.primary),
              title: Text(c.name),
              subtitle: Text('${c.startTime}-${c.endTime}  ${c.classroom}'),
            ),
        _header('习惯打卡（已打卡 ${doneHabits.length} / ${habits.length}）'),
        if (habits.isEmpty)
          _empty('还没有习惯')
        else ...[
          for (final h in doneHabits)
            ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(h.title),
              trailing: const Text(
                '已打卡',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          for (final h in pendingHabits)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.radio_button_unchecked,
                color: AppTheme.textSecondary,
              ),
              title: Text(h.title),
              trailing: const Text(
                '待打卡',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ],
    );
  }

  Widget _header(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      s,
      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
    ),
  );

  Widget _empty(String s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      s,
      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
    ),
  );

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }
}

/// —— 当月视图：月历 + 完成情况可视化 + 特殊日子 ——
class MonthView extends ConsumerStatefulWidget {
  final List<TodoItem> todos;
  final List<DiaryEntry> diaries;
  final Map<String, CheckinMap> checkins;
  final List<SpecialDay> specials;

  const MonthView({
    super.key,
    required this.todos,
    required this.diaries,
    required this.checkins,
    required this.specials,
  });

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  late DateTime _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
  }

  @override
  Widget build(BuildContext context) {
    // 内置节假日（当前显示月份的年份 + 下一年）。
    //
    // 必须带上「下一年」：12 月视图的网格会把次年 1 月的日期一并渲染，
    // 否则那些格子不会显示元旦/春节之类的节日。
    //
    // 同时必须去重：除夕是用「该年最后一天是否仍在农历十二月」推出来的，
    // 所以同一个除夕会被相邻两年各生成一次（如 2025-01-28 同时出现在
    // 2024 与 2025 两份列表里，且两侧 id 不同、按 id 去重无效）。
    // 这里按「名称 + 日期」去重，避免同一格子叠出两个节日。
    final holidays = <SpecialDay>[];
    final seenHolidayKeys = <String>{};
    for (final y in [_month.year, _month.year + 1]) {
      final list =
          ref.watch(holidayListProvider(y)).valueOrNull ?? const <SpecialDay>[];
      for (final h in list) {
        if (seenHolidayKeys.add('${h.name}|${h.date}')) holidays.add(h);
      }
    }
    return Column(
      children: [
        // 月份导航
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                }),
              ),
              Expanded(
                child: Text(
                  '${_month.year} 年 ${_month.month} 月',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                }),
              ),
            ],
          ),
        ),
        // 星期表头
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 月历网格
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.1,
              ),
              itemCount: _dayCount(),
              itemBuilder: (ctx, i) {
                final day = _month.add(
                  Duration(days: i - _firstWeekdayOffset()),
                );
                final date = AppTime.dateOnly(day);
                final isCurrentMonth = day.month == _month.month;
                return _dayCell(day, date, isCurrentMonth, holidays);
              },
            ),
          ),
        ),
        // 选中日期详情 + 特殊日子
        if (_selected != null) _selectedPanel(_selected!, holidays),
      ],
    );
  }

  int _firstWeekdayOffset() {
    final first = DateTime(_month.year, _month.month, 1);
    return first.weekday - 1; // 周一起始
  }

  int _dayCount() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = _firstWeekdayOffset() + daysInMonth;
    return (cells / 7).ceil() * 7;
  }

  Widget _dayCell(
    DateTime day,
    String date,
    bool isCurrentMonth,
    List<SpecialDay> holidays,
  ) {
    final now = AppTime.dateOnly(DateTime.now());
    final isToday = date == now;
    final allSpecials = [...widget.specials, ...holidays];
    final special = allSpecials.where((s) => s.date == date).firstOrNull;
    // 完成情况：当天到期已完成的待办 + 习惯打卡 + 日记
    final dayTodos = widget.todos
        .where((t) => t.deadline.date == date)
        .toList();
    final doneCount = dayTodos.where((t) => t.status == TodoStatus.done).length;
    final checkinCount = widget.checkins.values
        .where((c) => (c.entries[date] ?? 0) > 0)
        .length;
    final diaryCount = widget.diaries
        .where((d) => AppTime.dateOnly(d.createdAt) == date)
        .length;

    return InkWell(
      onTap: () => setState(() => _selected = day),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: special != null
              ? _hex(special.color).withValues(alpha: 0.15)
              : isToday
              ? AppTheme.primary.withValues(alpha: 0.1)
              : isCurrentMonth
              ? Colors.white
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: AppTheme.primary) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                color: isCurrentMonth
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (doneCount > 0) _dot(AppTheme.primary, doneCount),
                if (checkinCount > 0) _dot(Colors.green, checkinCount),
                if (diaryCount > 0) _dot(const Color(0xFF7C3AED), diaryCount),
                if (special != null) _dot(_hex(special.color), 1),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, int count) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _selectedPanel(DateTime day, List<SpecialDay> holidays) {
    final date = AppTime.dateOnly(day);
    final dayTodos = widget.todos
        .where((t) => t.deadline.date == date)
        .toList();
    final specials = [
      ...widget.specials,
      ...holidays,
    ].where((s) => s.date == date).toList();
    final dayDiaries =
        widget.diaries
            .where((d) => AppTime.dateOnly(d.createdAt) == date)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (specials.isEmpty && dayTodos.isEmpty && dayDiaries.isEmpty)
            const Text(
              '这一天暂无安排',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          for (final s in specials)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.type == 'holiday' ? Icons.celebration : Icons.star,
                color: _hex(s.color),
              ),
              title: Text(s.name),
              subtitle: s.type == 'holiday'
                  ? const Text(
                      '内置节假日',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  : null,
              trailing: s.type == 'custom'
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () {
                        ref.read(specialDayListProvider.notifier).delete(s.id);
                      },
                    )
                  : null,
            ),
          for (final t in dayTodos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                t.status == TodoStatus.done
                    ? Icons.check_circle
                    : Icons.schedule,
                color: t.status == TodoStatus.done
                    ? Colors.green
                    : _hex(t.deadline.color),
              ),
              title: Text(t.title.isEmpty ? '（无标题）' : t.title),
              subtitle: Text(t.deadline.time.isEmpty ? '全天' : t.deadline.time),
            ),
          for (final d in dayDiaries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book, color: Color(0xFF7C3AED)),
              title: Text(d.title.isEmpty ? '（无标题）' : d.title),
              subtitle: Text(
                '日记 ${d.createdAt.hour.toString().padLeft(2, '0')}:${d.createdAt.minute.toString().padLeft(2, '0')}',
              ),
            ),
          TextButton.icon(
            onPressed: () => _addSpecialDay(day),
            icon: const Icon(Icons.star_outline, size: 18),
            label: const Text('添加特殊日子 / 节假日'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSpecialDay(DateTime day) async {
    final nameCtrl = TextEditingController();
    String color = '#F5A623';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('特殊日子'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '日期：${AppTime.dateOnly(day)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称（如：国庆节 / 纪念日）'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in const [
                    '#E5484D',
                    '#F5A623',
                    '#30A46C',
                    '#1E88E5',
                    '#7C3AED',
                  ])
                    _ColorPick(
                      c: c,
                      selected: color == c,
                      onTap: () => setState(() => color = c),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(specialDayListProvider.notifier)
          .save(
            SpecialDay(
              id: AppPaths.newId(),
              date: AppTime.dateOnly(day),
              name: nameCtrl.text.trim(),
              type: 'custom',
              color: color,
            ),
          );
    }
  }

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }
}

class _ColorPick extends StatelessWidget {
  final String c;
  final bool selected;
  final VoidCallback onTap;

  const _ColorPick({
    required this.c,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _hex(c),
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.black, width: 2) : null,
        ),
      ),
    );
  }

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }
}

/// —— 当年视图：12 个月精简概览 ——
class YearView extends ConsumerWidget {
  final List<TodoItem> todos;
  final List<DiaryEntry> diaries;
  final Map<String, CheckinMap> checkins;
  final List<SpecialDay> specials;

  const YearView({
    super.key,
    required this.todos,
    required this.diaries,
    required this.checkins,
    required this.specials,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final holidays =
        ref.watch(holidayListProvider(year)).valueOrNull ??
        const <SpecialDay>[];
    final allSpecials = [...specials, ...holidays];
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: 12,
      itemBuilder: (ctx, i) {
        final month = i + 1;
        final ym = '$year-${month.toString().padLeft(2, '0')}';
        final monthTodos = todos
            .where((t) => t.deadline.date.startsWith(ym))
            .toList();
        final doneCount = monthTodos
            .where((t) => t.status == TodoStatus.done)
            .length;
        final checkinCount = checkins.values
            .where((c) => c.entries.keys.any((k) => k.startsWith(ym)))
            .length;
        final diaryCount = diaries
            .where((d) => AppTime.dateOnly(d.createdAt).startsWith(ym))
            .length;
        final specialCount = allSpecials
            .where((s) => s.date.startsWith(ym))
            .length;
        return Card(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$month 月',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '待办 $doneCount/${monthTodos.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '打卡 $checkinCount',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '日记 $diaryCount',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '特殊 $specialCount',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
