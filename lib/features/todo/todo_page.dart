import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'todo_chains_page.dart';
import 'todo_edit_page.dart';
import 'todo_models.dart';
import 'todo_repository.dart';

/// 待办事项模块入口页。
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(todoListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('待办事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: '任务链',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TodoChainsPage()),
            ),
          ),
        ],
      ),
      body: async.when(
        data: (items) => items.isEmpty ? _empty() : _list(context, ref, items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TodoEditPage()),
        ),
        tooltip: '新建待办',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('还没有待办', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _list(BuildContext context, WidgetRef ref, List<TodoItem> items) {
    final pending = items.where((e) => e.status != TodoStatus.done).toList();
    final done = items.where((e) => e.status == TodoStatus.done).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (pending.isNotEmpty) ...[
          for (final e in pending) _tile(context, ref, e),
        ],
        if (done.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('已完成', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          for (final e in done) _tile(context, ref, e),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, TodoItem e) {
    final done = e.status == TodoStatus.done;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TodoEditPage(item: e)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: done,
                onChanged: (v) => ref
                    .read(todoListProvider.notifier)
                    .setStatus(e.id, v == true ? TodoStatus.done : TodoStatus.pending),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title.isEmpty ? '（无标题）' : e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              decoration: done ? TextDecoration.lineThrough : null,
                              color: done ? AppTheme.textSecondary : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (e.deadline.date.isNotEmpty || e.location.text.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.more_vert, size: 18),
                            onPressed: () => _itemMenu(context, ref, e),
                          ),
                      ],
                    ),
                    if (e.deadline.date.isNotEmpty)
                      _badge(
                        Icons.schedule,
                        '截止 ${e.deadline.date}${e.deadline.time.isEmpty ? '' : ' ${e.deadline.time}'}',
                        _hex(e.deadline.color),
                        e.deadline.highlight,
                      ),
                    if (e.location.text.isNotEmpty)
                      _badge(
                        Icons.place,
                        e.location.text,
                        _hex(e.location.color),
                        e.location.highlight,
                      ),
                    if (e.contentPlain.trim().isNotEmpty && e.mode == TodoMode.plain)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          e.contentPlain.trim().replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String text, Color color, bool highlight) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlight ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: highlight ? Border.all(color: color) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Future<void> _itemMenu(BuildContext context, WidgetRef ref, TodoItem e) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('删除'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (act == 'delete') {
      await ref.read(todoListProvider.notifier).deleteItem(e.id);
    }
  }

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }
}
