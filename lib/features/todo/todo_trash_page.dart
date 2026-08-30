import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'todo_models.dart';
import 'todo_repository.dart';

/// 回收站：集中展示「已完成」和「已归档」的待办，可「恢复」或「彻底删除」。
class TodoTrashPage extends ConsumerWidget {
  const TodoTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(todoListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: async.when(
        data: (items) {
          final done = items
              .where((e) => e.status == TodoStatus.done)
              .toList();
          final trashed = items
              .where((e) => e.status == TodoStatus.archived)
              .toList();
          if (done.isEmpty && trashed.isEmpty) {
            return const Center(
              child: Text(
                '回收站是空的',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (done.isNotEmpty) ...[
                const _SectionHeader(icon: Icons.check_circle_outline, text: '已完成'),
                for (final e in done) _TrashTile(item: e, kind: _TrashKind.done),
              ],
              if (trashed.isNotEmpty) ...[
                const _SectionHeader(icon: Icons.archive_outlined, text: '已归档'),
                for (final e in trashed)
                  _TrashTile(item: e, kind: _TrashKind.archived),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }
}

/// 分节标题
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionHeader({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 条目类型：已完成 / 已归档
enum _TrashKind { done, archived }

/// 回收站条目：显示标题 + 子任务数量，提供恢复 / 彻底删除。
class _TrashTile extends ConsumerWidget {
  final TodoItem item;
  final _TrashKind kind;

  const _TrashTile({required this.item, required this.kind});

  int _countAll(TodoItem e) {
    var n = e.children.length;
    for (final c in e.children) {
      n += _countAll(c);
    }
    return n;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: const Text('将从本地永久删除该待办（含所有子任务），无法恢复。确定吗？'),
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
      await ref.read(todoListProvider.notifier).deleteItem(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = _countAll(item);
    final isDone = kind == _TrashKind.done;
    final subtitle = item.children.isEmpty
        ? (isDone ? '已完成' : '已归档')
        : (isDone ? '已完成 · 含 $count 个子任务' : '已归档 · 含 $count 个子任务');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: Icon(
          isDone ? Icons.check_circle_outline : Icons.archive_outlined,
          color: isDone ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          item.title.isEmpty ? '（无标题）' : item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isDone ? '恢复为待办' : '恢复',
              icon: const Icon(Icons.restore, color: AppTheme.primary),
              onPressed: () =>
                  ref.read(todoListProvider.notifier).restoreItem(item.id),
            ),
            IconButton(
              tooltip: '彻底删除',
              icon: const Icon(
                Icons.delete_forever,
                color: AppTheme.danger,
              ),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
