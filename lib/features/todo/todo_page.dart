import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'todo_edit_page.dart';
import 'todo_models.dart';
import 'todo_repository.dart';
import 'todo_templates_page.dart';

/// 待办事项模块入口页（树形：任务链 = 嵌套了子任务的普通待办）。
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
            icon: const Icon(Icons.description_outlined),
            tooltip: '待办模板',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TodoTemplatesPage()),
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
        Icon(
          Icons.checklist,
          size: 64,
          color: AppTheme.textSecondary.withValues(alpha: 0.4),
        ),
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
          for (final e in pending) _TodoNode(item: e, depth: 0),
        ],
        if (done.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '已完成',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          for (final e in done) _TodoNode(item: e, depth: 0),
        ],
      ],
    );
  }
}

/// 树形待办节点（可递归展开子任务）。
class _TodoNode extends ConsumerStatefulWidget {
  final TodoItem item;
  final int depth;

  const _TodoNode({required this.item, required this.depth});

  @override
  ConsumerState<_TodoNode> createState() => _TodoNodeState();
}

class _TodoNodeState extends ConsumerState<_TodoNode> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.item.hasChildren && widget.depth < 1;
  }

  void _toggleExpand() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final e = widget.item;
    final done = e.status == TodoStatus.done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                        .setStatus(
                          e.id,
                          v == true ? TodoStatus.done : TodoStatus.pending,
                        ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (e.hasChildren)
                              InkWell(
                                onTap: _toggleExpand,
                                child: Icon(
                                  _expanded
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                  size: 20,
                                  color: AppTheme.primary,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                e.title.isEmpty ? '（无标题）' : e.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: done
                                      ? AppTheme.textSecondary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (e.hasChildren)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  '${e.children.length}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.more_vert, size: 18),
                              onPressed: () => _itemMenu(e),
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
                        if (e.contentPlain.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              e.contentPlain.trim().replaceAll('\n', ' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        if (e.hasChildren && !done)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '子任务 ${e.children.where((c) => c.status == TodoStatus.done).length}/${e.children.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        if (!done)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TodoEditPage(parent: e),
                                ),
                              ),
                              icon: const Icon(Icons.add_task, size: 18),
                              label: const Text('添加子任务'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          for (final c in e.children)
            Padding(
              padding: EdgeInsets.only(left: (widget.depth * 16).toDouble()),
              child: _TodoNode(item: c, depth: widget.depth + 1),
            ),
      ],
    );
  }

  Future<void> _itemMenu(TodoItem e) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task, color: AppTheme.primary),
              title: const Text('添加子任务'),
              onTap: () => Navigator.pop(ctx, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('删除'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'add') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TodoEditPage(parent: e)),
      );
    } else if (act == 'delete') {
      await ref.read(todoListProvider.notifier).deleteItem(e.id);
    }
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

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }
}
