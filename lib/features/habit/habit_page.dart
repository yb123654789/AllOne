import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import 'habit_edit_page.dart';
import 'habit_models.dart';
import 'habit_repository.dart';

/// 习惯模块入口页：习惯列表 + 打卡。
class HabitPage extends ConsumerWidget {
  const HabitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitListProvider);
    final checkinAsync = ref.watch(habitCheckinProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('习惯')),
      body: habitsAsync.when(
        data: (habits) => checkinAsync.when(
          data: (checkins) =>
              habits.isEmpty ? _empty() : _list(context, ref, habits, checkins),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HabitEditPage()),
        ),
        tooltip: '新建习惯',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('还没有习惯', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _list(BuildContext context, WidgetRef ref, List<Habit> habits,
      Map<String, CheckinMap> checkins) {
    final today = AppTime.dateOnly(DateTime.now());
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: habits.length,
      itemBuilder: (ctx, i) {
        final h = habits[i];
        final cm = checkins[h.id] ?? const CheckinMap();
        final doneToday = (cm.entries[today] ?? 0) > 0;
        return _card(context, ref, h, cm, doneToday);
      },
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Habit h, CheckinMap cm, bool doneToday) {
    final target = h.target.value;
    final current = h.target.type == HabitType.count ? cm.totalCount : cm.totalDays;
    final progress = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    h.title.isEmpty ? '未命名习惯' : h.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                _checkinButton(context, ref, h, doneToday),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _tag(h.category),
                const SizedBox(width: 8),
                Text(
                  '${h.target.type == HabitType.count ? '次数' : '天数'} $current/$target',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
                Text('连续 ${cm.streakDays(DateTime.now())} 天',
                    style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
              ],
            ),
            if (h.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(h.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.divider,
                color: doneToday ? Colors.green : AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkinButton(BuildContext context, WidgetRef ref, Habit h, bool doneToday) {
    return TextButton.icon(
      onPressed: () async {
        final today = AppTime.dateOnly(DateTime.now());
        final notifier = ref.read(habitCheckinProvider.notifier);
        if (doneToday) {
          await notifier.uncheckin(h.id, today);
        } else {
          await notifier.checkin(h.id, today);
        }
      },
      icon: Icon(doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
          color: doneToday ? Colors.green : AppTheme.primary, size: 20),
      label: Text(doneToday ? '已打卡' : '打卡'),
      style: TextButton.styleFrom(
        foregroundColor: doneToday ? Colors.green : AppTheme.primary,
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
    );
  }
}
