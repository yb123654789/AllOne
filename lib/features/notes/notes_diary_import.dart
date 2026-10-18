import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../diary/diary_models.dart';
import '../diary/diary_repository.dart';
import 'note_topic_edit_page.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 把若干篇日记转存到指定主题，返回成功条数（单篇失败不影响其余）。
Future<int> _transfer(
  WidgetRef ref,
  String topicId,
  List<DiaryEntry> diaries,
) async {
  var ok = 0;
  for (final d in diaries) {
    try {
      await createEntryFromDiary(
        ref: ref,
        topicId: topicId,
        payload: DiaryTransferPayload(
          title: d.title,
          text: d.plainText,
          tags: d.tags,
          occurredAt: d.createdAt,
          media: d.media,
          mediaDirRelative: diaryMediaDir(d.id),
        ),
      );
      ok++;
    } catch (_) {
      // 单篇失败不影响其余
    }
  }
  return ok;
}

/// 从日记页发起转存：先选主题（或新建一个），再把选中的日记转过去。
Future<void> showDiaryTransferFlow(
  BuildContext context,
  WidgetRef ref,
  List<DiaryEntry> diaries,
) async {
  if (diaries.isEmpty) return;
  final topics = (ref.read(noteTopicListProvider).valueOrNull ?? const <NoteTopic>[])
      .where((t) => !t.inTrash)
      .toList();
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('转存到哪个主题？', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final t in topics)
            ListTile(
              leading: const Icon(Icons.folder_outlined, color: AppTheme.primary),
              title: Text(t.title.isEmpty ? '未命名主题' : t.title),
              onTap: () => Navigator.pop(ctx, t.id),
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('新建一个主题…'),
            onTap: () => Navigator.pop(ctx, '__new__'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  String? topicId = choice;
  if (choice == '__new__') {
    final created = await Navigator.push<NoteTopic>(
      context,
      MaterialPageRoute(builder: (_) => const NoteTopicEditPage()),
    );
    topicId = created?.id;
  }
  if (topicId == null || !context.mounted) return;

  final ok = await _transfer(ref, topicId, diaries);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok == diaries.length
              ? '已转存 ${diaries.length} 篇日记'
              : '已转存 $ok/${diaries.length} 篇（其余失败）',
        ),
      ),
    );
  }
}

/// 「从日记转存」选择面板：勾选若干篇日记 → 转存为当前主题下的记录。
///
/// 说明：这是笔记模块对日记的**单向只读引用**（与「工具 → 导出通用文本」
/// 读取各模块数据同一性质）；日记那边不会因为转存被修改，
/// 附件是**复制**一份过去，所以之后删除日记也不影响笔记。
Future<void> showDiaryTransferSheet(
  BuildContext context,
  WidgetRef ref,
  String topicId,
) async {
  final diaries = ref.read(diaryListProvider).valueOrNull ?? const <DiaryEntry>[];
  if (diaries.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('还没有日记可以转存')));
    return;
  }

  final picked = await showModalBottomSheet<List<DiaryEntry>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DiaryPickerSheet(diaries: diaries),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  final ok = await _transfer(ref, topicId, picked);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok == picked.length
              ? '已转存 $ok 篇日记'
              : '已转存 $ok/${picked.length} 篇（其余失败）',
        ),
      ),
    );
  }
}

class _DiaryPickerSheet extends StatefulWidget {
  final List<DiaryEntry> diaries;

  const _DiaryPickerSheet({required this.diaries});

  @override
  State<_DiaryPickerSheet> createState() => _DiaryPickerSheetState();
}

class _DiaryPickerSheetState extends State<_DiaryPickerSheet> {
  final Set<String> _selected = {};
  String _query = '';

  List<DiaryEntry> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.diaries;
    return widget.diaries
        .where(
          (d) =>
              d.title.toLowerCase().contains(q) ||
              d.plainText.toLowerCase().contains(q) ||
              d.tags.any((t) => t.toLowerCase().contains(q)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    '选择日记（已选 ${_selected.length}）',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            widget.diaries
                                .where((d) => _selected.contains(d.id))
                                .toList(),
                          ),
                    child: const Text('转存'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: '搜索日记标题 / 正文 / 标签',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                '转存只复制内容与附件，原日记不受影响。',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '没有匹配的日记',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final d = shown[i];
                        final checked = _selected.contains(d.id);
                        final summary = d.plainText.trim().replaceAll('\n', ' ');
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(d.id);
                            } else {
                              _selected.remove(d.id);
                            }
                          }),
                          title: Text(
                            d.title.isEmpty ? '无标题' : d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${d.createdAt.year}-${d.createdAt.month.toString().padLeft(2, '0')}-'
                            '${d.createdAt.day.toString().padLeft(2, '0')}'
                            '${summary.isEmpty ? '' : ' · $summary'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
