import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'notes_models.dart';
import 'notes_repository.dart';
import 'notes_style.dart';

/// 分组管理：新建 / 改名 / 换色 / 删除。
///
/// 分组只是收纳用的「文件夹」，删分组不会删主题（组内主题变回未分组）。
Future<void> showNoteGroupManager(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GroupSheet(),
  );
}

class _GroupSheet extends ConsumerWidget {
  const _GroupSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(noteGroupListProvider).valueOrNull ?? const <NoteGroup>[];
    final topics = ref.watch(noteTopicListProvider).valueOrNull ?? const <NoteTopic>[];
    int countOf(String id) =>
        topics.where((t) => !t.inTrash && t.groupIds.contains(id)).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('笔记分组', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _editGroup(context, ref, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建分组'),
                ),
              ],
            ),
            const Text(
              '分组用来收纳主题（如「学习」「读书」「工作」）。删分组不会删主题。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '还没有分组，不建也不影响使用',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in groups)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 8,
                          backgroundColor: noteColor(g.color),
                        ),
                        title: Text(g.name.isEmpty ? '未命名分组' : g.name),
                        subtitle: Text(
                          '${countOf(g.id)} 个主题',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: '重命名 / 换色',
                              onPressed: () => _editGroup(context, ref, g),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: '删除分组',
                              onPressed: () => _deleteGroup(context, ref, g),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref, NoteGroup g) async {
    final n = (ref.read(noteTopicListProvider).valueOrNull ?? [])
        .where((t) => !t.inTrash && t.groupIds.contains(g.id))
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text(
          n == 0
              ? '删除分组「${g.name}」？'
              : '删除分组「${g.name}」？\n\n组内 $n 个主题不会被删除，只会变成「未分组」。',
        ),
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
    if (ok == true) await ref.read(noteGroupListProvider.notifier).delete(g.id);
  }

  Future<void> _editGroup(BuildContext context, WidgetRef ref, NoteGroup? g) async {
    final nameCtrl = TextEditingController(text: g?.name ?? '');
    var color = g?.color ?? kNotePalette.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(g == null ? '新建分组' : '编辑分组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '分组名称', hintText: '如：学习 / 读书 / 工作'),
              ),
              const SizedBox(height: 14),
              const Text('颜色', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              NoteColorPicker(value: color, onChanged: (c) => setState(() => color = c)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final group = g == null
        ? NoteGroup(
            id: AppPaths.newId(),
            name: name,
            color: color,
            order: (ref.read(noteGroupListProvider).valueOrNull ?? []).length,
            createdAt: now,
            updatedAt: now,
          )
        : g.copyWith(name: name, color: color, updatedAt: now);
    await ref.read(noteGroupListProvider.notifier).save(group);
  }
}
