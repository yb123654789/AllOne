import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ui_prefs.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import 'course_edit_page.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 星期名（周一起始）
const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 周视图 7 列网格的列宽（纯函数，便于单元测试）。
///
/// 关键约束：**7 列 + 列间距 + 左右留白 不会超过可用宽度**，
/// 这样内容才与窗口对齐（旧实现是 7 × 固定 150px，比窗口宽就得左右平移）。
/// 超过 [maxCol] 时不再拉宽（超宽屏上避免一列被拉成一条）。
double scheduleColumnWidth(
  double maxWidth, {
  int columns = 7,
  double gap = 6,
  double horizontalPadding = 8,
  double minCol = 60,
  double maxCol = 360,
}) {
  final available =
      maxWidth - horizontalPadding * 2 - gap * (columns - 1);
  if (available <= 0) return minCol;
  final w = available / columns;
  if (w < minCol) return minCol;
  if (w > maxCol) return maxCol;
  return w;
}

/// 课程表模块入口页：周视图 + 课程统计（学期制，半年一换）。
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _addCourse() async {
    final terms = ref.read(termListProvider).valueOrNull ?? [];
    if (terms.isEmpty) {
      await _manageTerms();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourseEditPage()),
    );
  }

  Future<void> _manageTerms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermManagePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_month_outlined),
            tooltip: '学期管理',
            onPressed: _manageTerms,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加课程',
            onPressed: _addCourse,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '周视图'),
            Tab(text: '课程统计'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_WeekView(), _CourseStatsView()],
      ),
    );
  }
}

/// 周视图的两种排布
enum ScheduleLayout {
  /// 7 列周网格（传统课程表）
  grid,

  /// 一天一段的纵向列表（手机友好，无需左右平移）
  list,
}

/// 周视图（两种排布可手动切换并记住，默认按窗口宽度自动选）
class _WeekView extends ConsumerWidget {
  const _WeekView();

  /// 窄于这个宽度（手机竖屏）自动改用「一天一段」：
  /// 7 列平分后每列只剩 50px 左右，字全被挤没。
  static const double _gridMinWidth = 560;

  /// 宽屏（电脑）时列宽上限，避免超宽屏把一张课卡拉成一条
  static const double _maxColWidth = 360;

  /// 用户手动选择的排布；null = 自动（随窗口宽度）。
  /// 选择会写进 `AllOneData/settings/ui.json`，重启后仍然记得。
  static ScheduleLayout? _overrideOf(String pref) => switch (pref) {
    UiPrefs.scheduleLayoutGrid => ScheduleLayout.grid,
    UiPrefs.scheduleLayoutList => ScheduleLayout.list,
    _ => null,
  };

  static Future<void> _saveLayout(WidgetRef ref, ScheduleLayout? mode) {
    return ref
        .read(uiPrefsProvider.notifier)
        .setScheduleLayout(mode?.name ?? UiPrefs.scheduleLayoutAuto);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseListProvider).valueOrNull ?? [];
    final today = DateTime.now().weekday;
    final override = _overrideOf(ref.watch(scheduleLayoutPrefProvider));
    return LayoutBuilder(
      builder: (context, c) {
        // 以前这里是一个横向 ListView（7 列 × 固定 150px ≈ 1050px）：
        // 窗口比它宽时右侧留白「对不齐」，比它窄（手机）时只能左右平移，
        // 每列内部还各有一个纵向 ListView，于是又得上下翻 —— 双重滚动。
        // 现在两种排布都保留：宽屏平分列宽铺满窗口，窄屏按天竖排；
        // 用户也可以随时手动切换（切换后按用户所选并记住，不再自动跟随）。
        final auto = c.maxWidth < _gridMinWidth
            ? ScheduleLayout.list
            : ScheduleLayout.grid;
        final mode = override ?? auto;
        return Column(
          children: [
            _layoutBar(ref, mode, override != null),
            Expanded(
              child: mode == ScheduleLayout.grid
                  ? _weekGrid(courses, today, c.maxWidth)
                  : _dayList(courses, today),
            ),
          ],
        );
      },
    );
  }

  /// 顶部切换条：网格 / 按天；手动选过之后出现「恢复自动」
  Widget _layoutBar(WidgetRef ref, ScheduleLayout mode, bool manual) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (manual)
            TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复自动'),
              onPressed: () => _saveLayout(ref, null),
            ),
          Tooltip(
            message: manual
                ? '已手动选择（会记住），可点「恢复自动」'
                : '当前按窗口宽度自动选择（宽屏网格 / 窄屏按天）',
            child: SegmentedButton<ScheduleLayout>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: ScheduleLayout.grid,
                  icon: Icon(Icons.grid_view_outlined, size: 16),
                  label: Text('网格'),
                ),
                ButtonSegment(
                  value: ScheduleLayout.list,
                  icon: Icon(Icons.view_agenda_outlined, size: 16),
                  label: Text('按天'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => _saveLayout(ref, s.first),
            ),
          ),
        ],
      ),
    );
  }

  /// 7 列周网格。列宽 = 可用宽度平分，**内容与窗口对齐**；
  /// 只有在用户手动选「网格」而窗口又太窄时，才退化为横向平移
  /// （此时也不再需要上下分别滚动：整块只有一个纵向滚动）。
  Widget _weekGrid(List<Course> courses, int today, double maxWidth) {
    const gap = 6.0;
    const padding = 8.0;
    final colWidth = scheduleColumnWidth(
      maxWidth,
      gap: gap,
      maxCol: _maxColWidth,
    );
    final gridWidth = colWidth * 7 + gap * 6;
    final grid = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var w = 1; w <= 7; w++) ...[
            if (w > 1) const SizedBox(width: gap),
            SizedBox(
              width: colWidth,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: w == today
                      ? AppTheme.primary.withValues(alpha: 0.06)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _dayHeader(w, w == today),
                    const SizedBox(height: 6),
                    ..._cellsOf(courses, w),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final fits = gridWidth <= maxWidth - padding * 2;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(padding),
      child: fits
          ? Center(child: SizedBox(width: gridWidth, child: grid))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: gridWidth, child: grid),
            ),
    );
  }

  /// 一天一段，纵向排列 —— 左右不再需要平移，整页只需上下滚动。
  /// 窄屏自动用它，宽屏也可以手动切到它（课多的日子看得更清楚）。
  Widget _dayList(List<Course> courses, int today) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (var w = 1; w <= 7; w++) ...[
          _dayHeader(w, w == today),
          const SizedBox(height: 6),
          ..._cellsOf(courses, w),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  /// 某一天的所有课程卡片；没有课时给一句提示（保持 7 天结构，方便定位）
  List<Widget> _cellsOf(List<Course> courses, int w) {
    final day = courses.where((c) => c.weekday == w).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (day.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '没有课',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ];
    }
    return [for (final c in day) _courseCell(c)];
  }

  Widget _dayHeader(int w, bool isToday) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isToday ? AppTheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? null : Border.all(color: AppTheme.divider),
      ),
      child: Text(
        '周${_weekNames[w - 1]}${isToday ? ' · 今天' : ''}',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isToday ? Colors.white : AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _courseCell(Course c) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.name.isEmpty ? '（未命名）' : c.name,
            // 窄列 / 长课名不再撑破布局，直接省略号
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${c.startTime}-${c.endTime}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppTheme.primary),
          ),
          if (c.classroom.isNotEmpty)
            Text(
              c.classroom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 课程统计视图
class _CourseStatsView extends ConsumerWidget {
  const _CourseStatsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseListProvider).valueOrNull ?? [];
    if (courses.isEmpty) {
      return const Center(
        child: Text(
          '暂无课程，点击右上角 + 添加',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: courses.length,
      itemBuilder: (ctx, i) {
        final c = courses[i];
        return Card(
          child: ExpansionTile(
            leading: const CircleAvatar(
              backgroundColor: AppTheme.primary,
              radius: 16,
              child: Icon(Icons.school, color: Colors.white, size: 18),
            ),
            title: Text(
              c.name.isEmpty ? '（未命名课程）' : c.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '周${_weekNames[c.weekday - 1]} ${c.startTime}-${c.endTime}',
              style: const TextStyle(fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              _row('教师', c.teacher),
              _row('地点', c.classroom),
              _row('周次', c.weeks.isEmpty ? '每周' : c.weeks.join(', ')),
              if (c.notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '课程说明：${c.notes}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// 学期管理页
class TermManagePage extends ConsumerWidget {
  const TermManagePage({super.key});

  Future<void> _createTerm(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    DateTime? start;
    DateTime? end;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新建学期（半年一换）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '学期名称（如：2026 秋季学期）',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始日期'),
                subtitle: Text(
                  start == null
                      ? '未设置'
                      : '${start!.year}-${start!.month}-${start!.day}',
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('结束日期'),
                subtitle: Text(
                  end == null
                      ? '未设置'
                      : '${end!.year}-${end!.month}-${end!.day}',
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => end = d);
                },
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
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(termListProvider.notifier)
          .saveTerm(
            Term(
              id: AppPaths.newId(),
              name: nameCtrl.text.trim(),
              start: start == null
                  ? ''
                  : '${start!.year}-${start!.month}-${start!.day}',
              end: end == null ? '' : '${end!.year}-${end!.month}-${end!.day}',
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('学期管理')),
      body: terms.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Text(
                  '暂无学期，点击右下角 + 创建',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final t = list[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.date_range,
                        color: AppTheme.primary,
                      ),
                      title: Text(t.name.isEmpty ? '未命名学期' : t.name),
                      subtitle: Text('${t.start} ~ ${t.end}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(termListProvider.notifier)
                            .deleteTerm(t.id),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createTerm(context, ref),
        tooltip: '新建学期',
        child: const Icon(Icons.add),
      ),
    );
  }
}
