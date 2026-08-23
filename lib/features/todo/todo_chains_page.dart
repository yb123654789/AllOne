import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'todo_models.dart';
import 'todo_repository.dart';

/// 任务链管理页（抽箱式长期任务）。
class TodoChainsPage extends ConsumerWidget {
  const TodoChainsPage({super.key});

  Future<void> _createChain(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final goalCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建任务链'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '任务链名称（如：学习 Python）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: goalCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '目标描述'),
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
    );
    if (saved == true) {
      final now = DateTime.now();
      await ref
          .read(taskChainListProvider.notifier)
          .saveChain(
            TaskChain(
              id: AppPaths.newId(),
              title: titleCtrl.text.trim(),
              goal: goalCtrl.text.trim(),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<void> _addSubTask(
    BuildContext context,
    WidgetRef ref,
    TaskChain chain,
  ) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加子任务'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '子任务名称'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (saved == true && ctrl.text.trim().isNotEmpty) {
      final updated = chain.copyWith(
        subTasks: [
          ...chain.subTasks,
          ChainSubTask(id: AppPaths.newId(), title: ctrl.text.trim()),
        ],
        updatedAt: DateTime.now(),
      );
      await ref.read(taskChainListProvider.notifier).saveChain(updated);
    }
  }

  Future<void> _deleteChain(
    BuildContext context,
    WidgetRef ref,
    TaskChain chain,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务链'),
        content: Text('确定删除「${chain.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(taskChainListProvider.notifier).deleteChain(chain.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskChainListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('任务链（抽箱式长期任务）')),
      body: async.when(
        data: (chains) => chains.isEmpty
            ? const Center(
                child: Text(
                  '暂无任务链\n点击右下角 + 创建长期任务链',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: chains.length,
                itemBuilder: (ctx, i) => _chainCard(context, ref, chains[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createChain(context, ref),
        tooltip: '新建任务链',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _chainCard(BuildContext context, WidgetRef ref, TaskChain c) {
    final doneCount = c.subTasks.where((s) => s.done).length;
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
                    c.title.isEmpty ? '未命名任务链' : c.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteChain(context, ref, c),
                ),
              ],
            ),
            if (c.goal.isNotEmpty)
              Text(
                c.goal,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: c.progress,
                minHeight: 6,
                backgroundColor: AppTheme.divider,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '进度 $doneCount/${c.subTasks.length}（${(c.progress * 100).toStringAsFixed(0)}%）',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final s in c.subTasks)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: s.done,
                title: Text(
                  s.title,
                  style: TextStyle(
                    decoration: s.done ? TextDecoration.lineThrough : null,
                    color: s.done
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary,
                  ),
                ),
                onChanged: (v) => ref
                    .read(taskChainListProvider.notifier)
                    .toggleSubTask(c.id, s.id, v ?? false),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _addSubTask(context, ref, c),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加子任务'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
