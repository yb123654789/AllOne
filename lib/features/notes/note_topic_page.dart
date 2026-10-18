import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'note_entry_detail_page.dart';
import 'note_entry_edit_page.dart';
import 'note_topic_edit_page.dart';
import 'notes_diary_import.dart';
import 'notes_export.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';
import 'notes_style.dart';

/// 主题内页：这个主题的**时间线**（按年月分组，新的在上）。
class NoteTopicPage extends ConsumerStatefulWidget {
  final String topicId;

  const NoteTopicPage({super.key, required this.topicId});

  @override
  ConsumerState<NoteTopicPage> createState() => _NoteTopicPageState();
}

class _NoteTopicPageState extends ConsumerState<NoteTopicPage> {
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  NoteTopic? _topicOf(List<NoteTopic> topics) {
    for (final t in topics) {
      if (t.id == widget.topicId) return t;
    }
    return null;
  }

  Future<void> _addEntry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEntryEditPage(topicId: widget.topicId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topicsAsync = ref.watch(noteTopicListProvider);
    final entriesAsync = ref.watch(noteEntryListProvider(widget.topicId));

    return topicsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('加载失败：$e'))),
      data: (topics) {
        final topic = _topicOf(topics);
        if (topic == null) {
          // 主题被彻底删除 / 恢复失败时，避免白屏
          return Scaffold(
            appBar: AppBar(title: const Text('笔记')),
            body: const Center(
              child: Text('这个主题不存在了', style: TextStyle(color: AppTheme.textSecondary)),
            ),
          );
        }
        final groups = ref.watch(noteGroupListProvider).valueOrNull ?? const <NoteGroup>[];
        final groupNames = <String>[
          for (final g in groups)
            if (topic.groupIds.contains(g.id)) (g.name.isEmpty ? '未命名分组' : g.name),
        ];
        final groupText = groupNames.isEmpty ? null : groupNames.join('、');
        return Scaffold(
          appBar: AppBar(
            title: Text(
              topic.title.isEmpty ? '未命名主题' : topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                tooltip: '在本主题内搜索',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _searchCtrl.clear();
                }),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteTopicEditPage(topic: topic),
                        ),
                      );
                    case 'export':
                      await NotesExporter.exportTopic(ref, topic: topic, groupName: groupText);
                    case 'fromDiary':
                      await showDiaryTransferSheet(context, ref, widget.topicId);
                    case 'delete':
                      await _confirmTrash(topic);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑主题')),
                  PopupMenuItem(value: 'export', child: Text('导出为 Markdown')),
                  PopupMenuItem(value: 'fromDiary', child: Text('从日记转存')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除主题', style: TextStyle(color: AppTheme.danger)),
                  ),
                ],
              ),
            ],
          ),
          body: entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (entries) => _body(topic, groupText, entries),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addEntry,
            tooltip: '记一条',
            icon: const Icon(Icons.add),
            label: const Text('记一条'),
          ),
        );
      },
    );
  }

  Widget _body(NoteTopic topic, String? groupName, List<NoteEntry> all) {
    final stats = NoteTopicStats.of(all);
    final query = _searchCtrl.text.trim();
    final shown = searchEntries(all, query);
    final groups = groupEntriesByMonth(shown);

    return Column(
      children: [
        _header(topic, groupName, stats),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '在本主题内搜索（标题 / 正文 / 标签）',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchCtrl.clear()),
                      ),
              ),
            ),
          ),
        Expanded(
          child: all.isEmpty
              ? _empty(topic)
              : shown.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配「$query」的记录',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  // 年月标题与记录卡片拼成一个扁平列表，滚动更跟手
                  itemCount: _flatCount(groups),
                  itemBuilder: (_, i) => _flatItem(groups, i),
                ),
        ),
      ],
    );
  }

  int _flatCount(List<NoteMonthGroup> groups) {
    var n = 0;
    for (final g in groups) {
      n += 1 + g.entries.length; // 月份标题 + 记录
    }
    return n;
  }

  Widget _flatItem(List<NoteMonthGroup> groups, int index) {
    var i = index;
    for (final g in groups) {
      if (i == 0) return _monthHeader(g);
      i -= 1;
      if (i < g.entries.length) {
        final e = g.entries[i];
        return _entryCard(e);
      }
      i -= g.entries.length;
    }
    return const SizedBox.shrink();
  }

  Widget _header(NoteTopic topic, String? groupName, NoteTopicStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NoteColorBar(color: topic.color, width: 3, height: 16),
              const SizedBox(width: 8),
              if (groupName != null) ...[
                const Icon(Icons.folder_outlined, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(
                  groupName,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
              ],
              if (topic.pinned) ...[
                const Icon(Icons.push_pin, size: 13, color: AppTheme.danger),
                const SizedBox(width: 3),
              ],
              if (topic.archived)
                const Text(
                  '已归档',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ),
          if (topic.intro.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              topic.intro.trim(),
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.5),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            stats.line(),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (stats.count > 1 && stats.firstAt != null && stats.lastAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '从 ${dateText(stats.firstAt!)} 到 ${dateText(stats.lastAt!)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthHeader(NoteMonthGroup g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(
            g.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${g.count} 条',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }

  Widget _entryCard(NoteEntry e) {
    final snippet = e.plainText.trim().replaceAll('\n', ' ');
    final sameDay = dateText(e.occurredAt) == dateText(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteEntryDetailPage(topicId: widget.topicId, entry: e),
          ),
        ),
        onLongPress: () => _confirmDeleteEntry(e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${e.occurredAt.month.toString().padLeft(2, '0')}-'
                    '${e.occurredAt.day.toString().padLeft(2, '0')} '
                    '${e.occurredAt.hour.toString().padLeft(2, '0')}:'
                    '${e.occurredAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: sameDay ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (e.media.isNotEmpty) ...[
                    const Icon(Icons.attach_file, size: 14, color: AppTheme.textSecondary),
                    Text(
                      '${e.media.length}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ],
              ),
              if (snippet.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  snippet,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                ),
              ],
              if (e.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: e.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(fontSize: 10, color: AppTheme.primary),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (e.locationStamp.enabled) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 12, color: Colors.green),
                    const SizedBox(width: 3),
                    Text(
                      e.locationStamp.name.isEmpty ? '地图标记' : e.locationStamp.name,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(NoteTopic topic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 56,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有记录',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            const Text(
              '点右下角「记一条」开始；以后每次有想法就记一条，\n会自动按年月排成时间线。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addEntry,
              icon: const Icon(Icons.add),
              label: const Text('记一条'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEntry(NoteEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('删除「${e.displayTitle}」？附件会一并删除，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteEntryListProvider(widget.topicId).notifier).delete(e.id);
    }
  }

  Future<void> _confirmTrash(NoteTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主题'),
        content: const Text('把整个主题（含所有记录与附件）移入回收站？可以在回收站恢复。'),
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
      if (mounted) Navigator.pop(context);
    }
  }
}
