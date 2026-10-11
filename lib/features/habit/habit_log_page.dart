import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'habit_models.dart';
import 'habit_repository.dart';

/// 「修改记录」页：按时间倒序展示补打卡 / 标记未完成 / 清除记录的审计日志。
///
/// 需求来源：热力图上修改历史必须**写清原因**，且这些修改要被收录、可回看。
class HabitLogPage extends ConsumerWidget {
  final String habitId;
  final String title;

  const HabitLogPage({super.key, required this.habitId, this.title = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(habitLogProvider);
    final logs = (async.valueOrNull?[habitId] ?? const <HabitEditLog>[]).toList()
      ..sort((a, b) => b.at.compareTo(a.at));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.isEmpty ? '修改记录' : '「${title.isEmpty ? '' : title}」修改记录',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: async.when(
        data: (_) {
          if (logs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有修改记录。\n\n在习惯详情页点选日期后修改，'
                  '每一次改动都会连同原因记录在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: logs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _tile(logs[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  Widget _tile(HabitEditLog log) {
    final (icon, color) = switch (log.action) {
      HabitEditAction.checkin => (Icons.add_task, AppTheme.primary),
      HabitEditAction.markUndone => (Icons.cancel_outlined, AppTheme.danger),
      HabitEditAction.clear => (Icons.cleaning_services_outlined, AppTheme.textSecondary),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        '${log.actionLabel} · ${log.dates.length} 天',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            _timeText(log.at),
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(log.changeSummary, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            '原因：${log.reason.isEmpty ? '（未填写）' : log.reason}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  static String _timeText(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
