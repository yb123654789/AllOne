import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/storage/storage_providers.dart';
import 'note_entry_detail_page.dart';
import 'note_topic_page.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 一条搜索结果：命中主题本身（[entry] 为 null）或命中某条记录。
class NoteSearchHit {
  final NoteTopic topic;
  final NoteEntry? entry;

  const NoteSearchHit({required this.topic, this.entry});
}

/// 跨主题搜索：主题（标题/简介）+ 所有主题下的记录（标题/正文/标签）。
///
/// 长期积累后「记得写过但想不起在哪个主题」是常态，所以单独做了这一页。
final noteSearchProvider =
    FutureProvider.autoDispose.family<List<NoteSearchHit>, String>((
      ref,
      query,
    ) async {
      final q = query.trim();
      if (q.isEmpty) return const [];
      final store = await ref.watch(jsonStoreProvider.future);
      final topics = (await ref.watch(noteTopicListProvider.future))
          .where((t) => !t.inTrash)
          .toList();

      final hits = <NoteSearchHit>[];
      final entryHits = <NoteSearchHit>[];
      for (final t in sortTopics(topics)) {
        if (topicMatches(t, q)) hits.add(NoteSearchHit(topic: t));
        final dir = noteEntriesDir(t.id);
        final files = await store.listFiles(dir);
        final matched = <NoteEntry>[];
        for (final f in files) {
          final json = await store.read('$dir/$f');
          if (json == null) continue;
          final e = NoteEntry.fromJson(json);
          if (entryMatches(e, q)) matched.add(e);
        }
        for (final e in sortEntriesDesc(matched)) {
          entryHits.add(NoteSearchHit(topic: t, entry: e));
        }
      }
      return [...hits, ...entryHits];
    });

/// 笔记搜索页。
class NotesSearchPage extends ConsumerStatefulWidget {
  const NotesSearchPage({super.key});

  @override
  ConsumerState<NotesSearchPage> createState() => _NotesSearchPageState();
}

class _NotesSearchPageState extends ConsumerState<NotesSearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    // 输入停顿 250ms 再查：避免每敲一个字就扫一遍全部记录文件
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final async = q.isEmpty ? null : ref.watch(noteSearchProvider(q));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '搜索标题 / 正文 / 标签',
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清空',
              onPressed: () {
                _ctrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: q.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '输入关键词，会在所有主题和记录里找。',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          : async!.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('搜索失败：$e')),
              data: (hits) => hits.isEmpty
                  ? Center(
                      child: Text(
                        '没有找到「$q」',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : _results(hits),
            ),
    );
  }

  Widget _results(List<NoteSearchHit> hits) {
    final topicHits = hits.where((h) => h.entry == null).toList();
    final entryHits = hits.where((h) => h.entry != null).toList();
    final children = <Widget>[];

    if (topicHits.isNotEmpty) {
      children.add(_sectionLabel('主题（${topicHits.length}）'));
      for (final h in topicHits) {
        children.add(
          ListTile(
            leading: const Icon(Icons.folder_outlined, color: AppTheme.primary),
            title: Text(
              h.topic.title.isEmpty ? '未命名主题' : h.topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: h.topic.intro.trim().isEmpty
                ? null
                : Text(
                    h.topic.intro.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NoteTopicPage(topicId: h.topic.id)),
            ),
          ),
        );
      }
    }

    if (entryHits.isNotEmpty) {
      children.add(_sectionLabel('记录（${entryHits.length}）'));
      for (final h in entryHits) {
        final e = h.entry!;
        final snippet = e.plainText.trim().replaceAll('\n', ' ');
        children.add(
          ListTile(
            leading: const Icon(Icons.subject, color: AppTheme.textSecondary),
            title: Text(
              e.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${h.topic.title.isEmpty ? '未命名主题' : h.topic.title} · ${dateText(e.occurredAt)}'
              '${snippet.isEmpty ? '' : ' · $snippet'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEntryDetailPage(topicId: h.topic.id, entry: e),
              ),
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    ),
  );
}
