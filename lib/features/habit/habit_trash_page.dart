import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'habit_models.dart';
import 'habit_repository.dart';

/// 回收站：集中展示已归档（archived）的习惯，可「恢复」或「彻底删除」。
class HabitTrashPage extends ConsumerWidget {
  const HabitTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(habitListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: async.when(
        data: (items) {
          final trashed = items.where((e) => e.archived).toList();
          if (trashed.isEmpty) {
            return const Center(
              child: Text(
                '回收站是空的',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [for (final e in trashed) _TrashTile(item: e)],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }
}

/// 回收站条目：显示标题 + 分类，提供恢复 / 彻底删除。
class _TrashTile extends ConsumerWidget {
  final Habit item;

  const _TrashTile({required this.item});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: const Text('将从本地永久删除该习惯及其全部打卡记录，无法恢复。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(habitListProvider.notifier).deleteHabit(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: const Icon(
          Icons.archive_outlined,
          color: AppTheme.textSecondary,
        ),
        title: Text(
          item.title.isEmpty ? '（无标题）' : item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '分类：${item.category}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '恢复',
              icon: const Icon(Icons.restore, color: AppTheme.primary),
              onPressed: () =>
                  ref.read(habitListProvider.notifier).restoreHabit(item.id),
            ),
            IconButton(
              tooltip: '彻底删除',
              icon: const Icon(Icons.delete_forever, color: AppTheme.danger),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
