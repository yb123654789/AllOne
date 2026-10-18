import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ui_prefs.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import 'note_group_dialog.dart';
import 'note_topic_edit_page.dart';
import 'note_topic_page.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';
import 'notes_search_page.dart';
import 'notes_style.dart';
import 'notes_trash_page.dart';

/// 笔记模块入口页：主题列表。
///
/// 两种视图（偏好会记住）：
/// - **分组视图**（默认）：按大分组折叠展示 —— 「大航海时代」下面挂着一本本书；
/// - **平铺视图**：一长列主题卡片，顶部用分组标签筛选。
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  /// 平铺视图的分组筛选：null = 全部，'' = 未分组，其它 = 分组 id
  String? _groupId;

  /// 是否显示已归档的主题（默认收起，避免长期积累后列表被占满）
  bool _showArchived = false;

  /// 分组视图里被折叠起来的分组（'' 代表「未分组」）
  final Set<String> _collapsed = {};

  bool get _groupedView =>
      ref.watch(uiPrefsProvider).valueOrNull?.flag(
        UiPrefs.notesGroupedViewKey,
        fallback: true,
      ) ??
      true;

  Future<void> _setGroupedView(bool grouped) async {
    await ref.read(uiPrefsProvider.notifier).set(UiPrefs.notesGroupedViewKey, grouped);
  }

  Future<void> _newTopic() async {
    final group = (_groupId != null && _groupId!.isNotEmpty) ? _groupId : null;
    final created = await Navigator.push<NoteTopic>(
      context,
      MaterialPageRoute(builder: (_) => NoteTopicEditPage(initialGroupId: group)),
    );
    if (created != null && mounted) await _openTopic(created);
  }

  Future<void> _openTopic(NoteTopic topic) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteTopicPage(topicId: topic.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(noteTopicListProvider);
    final groups = ref.watch(noteGroupListProvider).valueOrNull ?? const <NoteGroup>[];
    final grouped = _groupedView;

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            icon: Icon(grouped ? Icons.view_list_outlined : Icons.account_tree_outlined),
            tooltip: grouped ? '切换为平铺视图' : '切换为分组视图',
            onPressed: () => _setGroupedView(!grouped),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索笔记（标题 / 正文 / 标签）',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotesSearchPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '回收站',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotesTrashPage()),
            ),
          ),
        ],
      ),
      body: async.when(
        data: (all) => _body(all, groups, grouped),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTopic,
        tooltip: '新建主题',
        icon: const Icon(Icons.add),
        label: const Text('新的主题'),
      ),
    );
  }

  Widget _body(List<NoteTopic> all, List<NoteGroup> groups, bool grouped) {
    final active = all.where((t) => !t.inTrash).toList();
    final archivedCount = active.where((t) => t.archived).length;
    final visible = active.where((t) => _showArchived || !t.archived).toList();
    final groupNames = {
      for (final g in groups) g.id: (g.name.isEmpty ? '未命名分组' : g.name),
    };

    final children = <Widget>[];
    if (grouped) {
      children.addAll(
        _groupedSections(visible, groups, groupNames, noTopicAtAll: active.isEmpty),
      );
    } else {
      children.add(_flatFilterBar(visible, groups));
      final list = _flatList(visible);
      if (list.isEmpty) {
        children.add(Expanded(child: _empty(active.isEmpty)));
      } else {
        children.add(
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 96, top: 4),
              itemCount: list.length,
              itemBuilder: (_, i) => _TopicCard(
                topic: list[i],
                groupNames: _namesOf(list[i], groupNames),
                onTap: () => _openTopic(list[i]),
                onLongPress: () => _showActions(list[i]),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      children: [
        if (archivedCount > 0) _archivedBar(archivedCount),
        ...children,
      ],
    );
  }

  List<String> _namesOf(NoteTopic t, Map<String, String> groupNames) => [
    for (final id in t.groupIds)
      if (groupNames[id] != null) groupNames[id]!,
  ];

  /// 分组视图：分组标题（可折叠）+ 组内主题；未分组放最后
  List<Widget> _groupedSections(
    List<NoteTopic> visible,
    List<NoteGroup> groups,
    Map<String, String> groupNames, {
    required bool noTopicAtAll,
  }) {
    if (visible.isEmpty) {
      return [Expanded(child: _empty(noTopicAtAll))];
    }
    final list = <Widget>[];
    for (final g in groups) {
      final items = sortTopics(
        visible.where((t) => t.groupIds.contains(g.id)).toList(),
      );
      if (items.isEmpty) continue;
      list.add(_groupHeader(g.id, g.name.isEmpty ? '未命名分组' : g.name, g.color, items.length));
      if (!_collapsed.contains(g.id)) {
        for (final t in items) {
          list.add(
            _TopicCard(
              topic: t,
              groupNames: _namesOf(t, groupNames),
              onTap: () => _openTopic(t),
              onLongPress: () => _showActions(t),
            ),
          );
        }
      }
    }
    final ungrouped = sortTopics(visible.where((t) => t.ungrouped).toList());
    if (ungrouped.isNotEmpty) {
      list.add(_groupHeader('', '未分组', null, ungrouped.length));
      if (!_collapsed.contains('')) {
        for (final t in ungrouped) {
          list.add(
            _TopicCard(
              topic: t,
              groupNames: const [],
              onTap: () => _openTopic(t),
              onLongPress: () => _showActions(t),
            ),
          );
        }
      }
    }
    return [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96, top: 4),
          children: list,
        ),
      ),
    ];
  }

  Widget _groupHeader(String id, String name, String? color, int count) {
    final collapsed = _collapsed.contains(id);
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(id);
        } else {
          _collapsed.add(id);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            if (color != null)
              CircleAvatar(radius: 6, backgroundColor: noteColor(color))
            else
              const Icon(Icons.inbox_outlined, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(
              '$count 个主题',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const Spacer(),
            Icon(
              collapsed ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  List<NoteTopic> _flatList(List<NoteTopic> visible) {
    var shown = visible.where(
      (t) => _groupId == null
          ? true
          : (_groupId == ''
                ? t.ungrouped
                : t.groupIds.contains(_groupId)),
    );
    return sortTopics(shown.toList());
  }

  /// 平铺视图的分组筛选条
  Widget _flatFilterBar(List<NoteTopic> visible, List<NoteGroup> groups) {
    int countOf(String? gid) => gid == null
        ? visible.length
        : visible.where((t) => gid == '' ? t.ungrouped : t.groupIds.contains(gid)).length;

    Widget chip(String label, String? gid, {String? color}) {
      final selected = _groupId == gid;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label ${countOf(gid)}'),
          selected: selected,
          visualDensity: VisualDensity.compact,
          avatar: color == null
              ? null
              : CircleAvatar(radius: 5, backgroundColor: noteColor(color)),
          onSelected: (_) => setState(() => _groupId = selected ? null : gid),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        children: [
          chip('全部', null),
          chip('未分组', ''),
          for (final g in groups)
            chip(g.name.isEmpty ? '未命名分组' : g.name, g.id, color: g.color),
          ActionChip(
            avatar: const Icon(Icons.tune, size: 16),
            label: const Text('分组'),
            visualDensity: VisualDensity.compact,
            onPressed: () => showNoteGroupManager(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _archivedBar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 15, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            '已归档 $count 个主题',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _showArchived = !_showArchived),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(_showArchived ? '收起' : '显示'),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool noTopicAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note,
              size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              noTopicAtAll ? '还没有笔记主题' : '这里还没有主题',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            const Text(
              '任何值得长期记录的事都可以建一个「主题」，\n然后在这个主题下一条条往里记，久了就是一条时间线。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _newTopic,
              icon: const Icon(Icons.add),
              label: const Text('新建主题'),
            ),
          ],
        ),
      ),
    );
  }

  /// 长按主题卡片：编辑 / 置顶 / 归档 / 删除
  Future<void> _showActions(NoteTopic topic) async {
    final notifier = ref.read(noteTopicListProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑主题'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NoteTopicEditPage(topic: topic)),
                );
              },
            ),
            ListTile(
              leading: Icon(topic.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(topic.pinned ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setPinned(topic.id, !topic.pinned);
              },
            ),
            ListTile(
              leading: Icon(topic.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(topic.archived ? '取消归档' : '归档（不再活跃）'),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setArchived(topic.id, !topic.archived);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('删除主题', style: TextStyle(color: AppTheme.danger)),
              subtitle: const Text('移入回收站，记录与附件都保留'),
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmTrash(topic);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTrash(NoteTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主题'),
        content: Text(
          '把「${topic.title.isEmpty ? '未命名主题' : topic.title}」移入回收站？\n\n'
          '主题下的记录和附件都会保留，可以在「回收站」里恢复。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteTopicListProvider.notifier).moveToTrash(topic.id);
    }
  }
}

/// 主题卡片：标题 + 简介 + 统计行 + 分组标签
class _TopicCard extends ConsumerWidget {
  final NoteTopic topic;
  final List<String> groupNames;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TopicCard({
    required this.topic,
    required this.groupNames,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(noteTopicStatsProvider(topic.id));
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteColorBar(color: topic.color, height: 50),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (topic.pinned) ...[
                          const Icon(Icons.push_pin, size: 15, color: AppTheme.danger),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            topic.title.isEmpty ? '未命名主题' : topic.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (topic.archived)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.textSecondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '已归档',
                              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ),
                      ],
                    ),
                    if (topic.intro.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        topic.intro.trim().replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 5),
                    stats.when(
                      data: (s) => Text(
                        s.line(),
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      loading: () => const Text(
                        '统计中…',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      error: (_, _) => const Text(
                        '统计失败',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                    if (groupNames.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              groupNames.join('、'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
