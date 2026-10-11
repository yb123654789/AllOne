import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ui_prefs.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import 'todo_edit_page.dart';
import 'todo_models.dart';
import 'todo_repository.dart';
import 'todo_templates_page.dart';
import 'todo_trash_page.dart';

/// 模糊匹配：标题 / 内容 / 标签是否包含关键词
bool _matchTodo(TodoItem e, String query) {
  if (query.trim().isEmpty) return true;
  final q = query.trim().toLowerCase();
  return e.title.toLowerCase().contains(q) ||
      e.contentPlain.toLowerCase().contains(q) ||
      e.tags.any((t) => t.toLowerCase().contains(q));
}

/// 节点是否包含全部筛选标签（多标签交叉，AND 逻辑；空集合恒真）
bool _tagMatchTodo(TodoItem e, Set<String> tags) =>
    tags.every((t) => e.tags.contains(t));

/// 子树中是否存在匹配（父不匹配但子任务匹配时父也保留显示）。
/// [query] 关键词模糊匹配，[tags] 多标签交叉（AND）筛选。
bool _subtreeMatchTodo(TodoItem e, String query, Set<String> tags) =>
    (_matchTodo(e, query) && _tagMatchTodo(e, tags)) ||
    e.children.any((c) => _subtreeMatchTodo(c, query, tags));

/// 递归收集待办树中全部标签（含子任务），用于标签筛选
Set<String> _collectTodoTags(List<TodoItem> items) {
  final set = <String>{};
  void walk(List<TodoItem> list) {
    for (final t in list) {
      set.addAll(t.tags);
      walk(t.children);
    }
  }

  walk(items);
  return set;
}

/// 待办事项模块入口页（树形：任务链 = 嵌套了子任务的普通待办）。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  bool _showSearch = false;
  String _query = '';

  /// 多标签交叉筛选（AND：必须同时包含全部所选标签）
  final Set<String> _filterTags = {};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(todoListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_showSearch ? '' : '待办事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '排序方式',
            onPressed: _showSortModeSheet,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _filterTags.isNotEmpty,
              label: Text('${_filterTags.length}'),
              child: const Icon(Icons.filter_alt_outlined),
            ),
            tooltip: '按标签筛选（多标签交叉）',
            onPressed: _showTagFilterDialog,
          ),
          if (_showSearch)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消搜索',
              onPressed: () => setState(() {
                _showSearch = false;
                _query = '';
              }),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => setState(() => _showSearch = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '回收站',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TodoTrashPage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: '待办模板',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TodoTemplatesPage()),
              ),
            ),
          ],
        ],
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: '搜索标题 / 内容 / 标签（模糊匹配）…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              )
            : null,
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
    final pending = items
        .where(
          (e) =>
              e.status == TodoStatus.pending &&
              _subtreeMatchTodo(e, _query, _filterTags),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (_filterTags.isNotEmpty) _tagFilterBar(),
        if (pending.isNotEmpty) ...[
          for (final e in pending)
            _TodoNode(item: e, depth: 0, query: _query, tags: _filterTags),
        ],
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                _filterTags.isEmpty && _query.trim().isEmpty
                    ? '没有待办（已完成项已移到回收站）'
                    : '没有匹配的待办（请调整关键词或筛选标签）',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
      ],
    );
  }

  /// 多标签筛选条：显示已选标签，可单独移除或一键清除
  Widget _tagFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            '标签筛选：',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          for (final t in _filterTags)
            InputChip(
              label: Text(t),
              visualDensity: VisualDensity.compact,
              onDeleted: () => setState(() => _filterTags.remove(t)),
            ),
          ActionChip(
            avatar: const Icon(Icons.clear_all, size: 16),
            label: const Text('清除'),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _filterTags.clear()),
          ),
        ],
      ),
    );
  }

  /// 按标签交叉筛选对话框：多选标签（AND 交集），支持模糊搜索
  /// 排序方式选择（底部弹窗）。
  ///
  /// 排序方式**只管顶层列表**：子任务的顺序始终由你自己排
  /// （每条子任务的「⋮」里都有上移 / 下移），不会被自动排序覆盖。
  Future<void> _showSortModeSheet() async {
    final prefs = ref.read(uiPrefsProvider).valueOrNull;
    final current = todoSortModeFrom(prefs?.raw(UiPrefs.todoSortModeKey));
    final picked = await showModalBottomSheet<TodoSortMode>(
      context: context,
      builder: (ctx) => SafeArea(
        // 小屏 / 横屏时内容会超过弹窗可用高度，必须可滚动
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '排序方式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final m in TodoSortMode.values)
              ListTile(
                leading: Icon(
                  m == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: m == current
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                title: Text(m.label),
                subtitle: Text(m.hint, style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                '子任务的顺序始终由你自己排（子任务的「⋮」里有上移 / 下移），不受这里影响。',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(todoListProvider.notifier).setSortMode(picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换为「${picked.label}」')),
    );
  }

  Future<void> _showTagFilterDialog() async {
    final allTags = _collectTodoTags(
      ref.read(todoListProvider).valueOrNull ?? const [],
    );
    var query = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final candidates =
              allTags
                  .where(
                    (t) =>
                        query.isEmpty ||
                        t.toLowerCase().contains(query.toLowerCase()),
                  )
                  .toList()
                ..sort();
          return AlertDialog(
            title: const Text('按标签筛选（交叉）'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '勾选多个标签：只显示同时包含全部所选标签的待办',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索标签（模糊匹配）…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialog(() => query = v),
                  ),
                  if (_filterTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _filterTags
                          .map(
                            (t) => InputChip(
                              label: Text(t),
                              onDeleted: () =>
                                  setDialog(() => _filterTags.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        '还没有标签',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: candidates
                              .map(
                                (t) => FilterChip(
                                  label: Text(t),
                                  selected: _filterTags.contains(t),
                                  onSelected: (v) => setDialog(() {
                                    if (v) {
                                      _filterTags.add(t);
                                    } else {
                                      _filterTags.remove(t);
                                    }
                                  }),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }
}

/// 树形待办节点（可递归展开子任务）。
class _TodoNode extends ConsumerStatefulWidget {
  final TodoItem item;
  final int depth;
  final String query;
  final Set<String> tags;

  const _TodoNode({
    required this.item,
    required this.depth,
    this.query = '',
    this.tags = const {},
  });

  @override
  ConsumerState<_TodoNode> createState() => _TodoNodeState();
}

class _TodoNodeState extends ConsumerState<_TodoNode> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // 任务链（含子任务的待办）默认收起，避免一打开就显示长长一列子任务。
    _expanded = false;
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            if (_subtreeMatchTodo(c, widget.query, widget.tags))
              Padding(
                padding: EdgeInsets.only(left: (widget.depth * 16).toDouble()),
                child: _TodoNode(
                  item: c,
                  depth: widget.depth + 1,
                  query: widget.query,
                  tags: widget.tags,
                ),
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
              leading: const Icon(
                Icons.arrow_upward,
                color: AppTheme.primary,
              ),
              title: const Text('上移'),
              onTap: () => Navigator.pop(ctx, 'up'),
            ),
            ListTile(
              leading: const Icon(
                Icons.arrow_downward,
                color: AppTheme.primary,
              ),
              title: const Text('下移'),
              onTap: () => Navigator.pop(ctx, 'down'),
            ),
            ListTile(
              leading: const Icon(Icons.add_task, color: AppTheme.primary),
              title: const Text('添加子任务'),
              onTap: () => Navigator.pop(ctx, 'add'),
            ),
            ListTile(
              leading: const Icon(
                Icons.archive_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('移到回收站'),
              onTap: () => Navigator.pop(ctx, 'archive'),
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
    if (act == 'up' || act == 'down') {
      final wasManual =
          todoSortModeFrom(
            ref.read(uiPrefsProvider).valueOrNull?.raw(UiPrefs.todoSortModeKey),
          ) ==
          TodoSortMode.manual;
      await ref.read(todoListProvider.notifier).moveItem(e.id, act == 'up' ? -1 : 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasManual
                ? '已${act == 'up' ? '上移' : '下移'}'
                : '已切换为「手动排序」并调整了顺序',
          ),
        ),
      );
      return;
    }
    if (act == 'add') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TodoEditPage(parent: e)),
      );
    } else if (act == 'archive') {
      await ref.read(todoListProvider.notifier).archiveItem(e.id);
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
