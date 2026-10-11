import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'quest_models.dart';
import 'quest_repository.dart';

/// 任务回收站：展示已归档的任务，可「恢复」或「彻底删除」。
///
/// 彻底删除会连投入记录与附件目录一起清掉，所以必须确认。
class QuestTrashPage extends ConsumerWidget {
  const QuestTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(questListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: async.when(
        data: (all) {
          final trashed = all.where((q) => q.archived).toList()
            ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
          if (trashed.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '回收站是空的。\n\n在任务总览的菜单里选「移入回收站」，任务会先放到这里，'
                  '确认不要了再彻底删除。',
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
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [for (final q in trashed) _tile(context, ref, q)],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Quest q) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: const Icon(Icons.archive_outlined, color: AppTheme.textSecondary),
        title: Text(
          q.title.isEmpty ? '未命名任务' : q.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            q.category,
            q.statusLabel,
            if (q.archivedAt.isNotEmpty) '归档于 ${q.archivedAt}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '恢复',
              icon: const Icon(Icons.restore, color: AppTheme.primary),
              onPressed: () =>
                  ref.read(questListProvider.notifier).restore(q.id),
            ),
            IconButton(
              tooltip: '彻底删除',
              icon: const Icon(Icons.delete_forever, color: AppTheme.danger),
              onPressed: () => _confirmDelete(context, ref, q),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Quest q,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text(
          '将永久删除「${q.title.isEmpty ? '未命名任务' : q.title}」及其全部里程碑、'
          '投入记录，无法恢复。确定吗？\n\n（关联的待办不会被删除）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(questListProvider.notifier).delete(q.id);
    }
  }
}
