import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 笔记回收站：被删的主题（连同记录与附件）在这里，可恢复或彻底删除。
class NotesTrashPage extends ConsumerWidget {
  const NotesTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(noteTopicListProvider);
    final trashed = (async.valueOrNull ?? const <NoteTopic>[])
        .where((t) => t.inTrash)
        .toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记回收站'),
        actions: [
          if (trashed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空回收站',
              onPressed: () => _purgeAll(context, ref, trashed.length),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (_) => trashed.isEmpty
            ? const Center(
                child: Text(
                  '回收站是空的',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: trashed.length,
                itemBuilder: (_, i) => _TrashCard(topic: trashed[i]),
              ),
      ),
    );
  }

  Future<void> _purgeAll(BuildContext context, WidgetRef ref, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text(
          '将彻底删除回收站里的 $count 个主题，**连同它们的全部记录与附件**，无法恢复。\n\n'
          '如果只是想腾地方，建议先导出备份。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref.read(noteTopicListProvider.notifier).purgeTrash();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已彻底删除 $n 个主题')));
    }
  }
}

class _TrashCard extends ConsumerWidget {
  final NoteTopic topic;

  const _TrashCard({required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(noteTopicStatsProvider(topic.id));
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              topic.title.isEmpty ? '未命名主题' : topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '删除于 ${dateTimeText(topic.deletedAt!)}'
              '${stats.valueOrNull == null ? '' : ' · ${stats.valueOrNull!.count} 条记录'}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref.read(noteTopicListProvider.notifier).restore(topic.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('已恢复')));
                    }
                  },
                  child: const Text('恢复'),
                ),
                TextButton(
                  onPressed: () => _purge(context, ref),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  child: const Text('彻底删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purge(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text(
          '彻底删除「${topic.title.isEmpty ? '未命名主题' : topic.title}」？\n\n'
          '主题下的全部记录与附件都会被删除，无法恢复。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(noteTopicListProvider.notifier).purge(topic.id);
  }
}
