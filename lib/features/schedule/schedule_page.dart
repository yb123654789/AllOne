import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'course_edit_page.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 星期名（周一起始）
const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

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
        children: const [
          _WeekView(),
          _CourseStatsView(),
        ],
      ),
    );
  }
}

/// 周视图
class _WeekView extends ConsumerWidget {
  const _WeekView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseListProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final today = now.weekday;
    return SizedBox(
      height: double.infinity,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        children: [
          for (var w = 1; w <= 7; w++)
            Container(
              width: 150,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: w == today ? AppTheme.primary.withValues(alpha: 0.06) : AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: w == today ? AppTheme.primary : Colors.transparent,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: Text(
                      '周${_weekNames[w - 1]}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: w == today ? Colors.white : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(6),
                      children: [
                        for (final c in courses.where((c) => c.weekday == w))
                          _courseCell(c),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseCell(Course c) {
    return Container(
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text('${c.startTime}-${c.endTime}',
              style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
          Text(c.classroom.isEmpty ? '' : c.classroom,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
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
        child: Text('暂无课程，点击右上角 + 添加',
            style: TextStyle(color: AppTheme.textSecondary)),
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
            title: Text(c.name.isEmpty ? '（未命名课程）' : c.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                  child: Text('课程说明：${c.notes}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
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
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13)),
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
                decoration: const InputDecoration(labelText: '学期名称（如：2026 秋季学期）'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始日期'),
                subtitle: Text(start == null ? '未设置' : '${start!.year}-${start!.month}-${start!.day}'),
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
                subtitle: Text(end == null ? '未设置' : '${end!.year}-${end!.month}-${end!.day}'),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref.read(termListProvider.notifier).saveTerm(Term(
            id: AppPaths.newId(),
            name: nameCtrl.text.trim(),
            start: start == null ? '' : '${start!.year}-${start!.month}-${start!.day}',
            end: end == null ? '' : '${end!.year}-${end!.month}-${end!.day}',
          ));
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
                child: Text('暂无学期，点击右下角 + 创建',
                    style: TextStyle(color: AppTheme.textSecondary)))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final t = list[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.date_range, color: AppTheme.primary),
                      title: Text(t.name.isEmpty ? '未命名学期' : t.name),
                      subtitle: Text('${t.start} ~ ${t.end}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref.read(termListProvider.notifier).deleteTerm(t.id),
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
