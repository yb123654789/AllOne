import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'diary_detail_page.dart';
import 'diary_edit_page.dart';
import 'diary_import_page.dart';
import 'diary_models.dart';
import 'diary_repository.dart';
import 'diary_templates_page.dart';

/// 日记模块入口页：日记列表。
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  /// 多标签交叉筛选（AND：必须同时包含全部所选标签）
  final Set<String> _filterTags = {};

  Future<void> _openNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DiaryEditPage()),
    );
  }

  Future<void> _openDetail(DiaryEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: e)),
    );
  }

  Future<void> _confirmDelete(DiaryEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日记'),
        content: Text('确定删除「${e.title.isEmpty ? '无标题' : e.title}」吗？该操作不可恢复。'),
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
      await ref.read(diaryListProvider.notifier).deleteEntry(e.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(diaryListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _filterTags.isNotEmpty,
              label: Text('${_filterTags.length}'),
              child: const Icon(Icons.filter_alt_outlined),
            ),
            tooltip: '按标签筛选（多标签交叉）',
            onPressed: _showTagFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: '模板管理',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiaryTemplatesPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入外部日记（txt / PDF，不覆盖现有日记）',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiaryImportPage()),
            ),
          ),
        ],
      ),
      body: async.when(
        data: (entries) => entries.isEmpty ? _empty() : _list(entries),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNew,
        tooltip: '写日记',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_stories_outlined,
          size: 64,
          color: AppTheme.textSecondary.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 12),
        const Text('还没有日记', style: TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        const Text(
          '点击右下角 + 开始记录',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    ),
  );

  Widget _list(List<DiaryEntry> entries) {
    final filtered = entries
        .where((e) => _filterTags.every((t) => e.tags.contains(t)))
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _filterTags.isEmpty ? '没有日记' : '没有匹配的日记（请调整筛选标签）',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (_filterTags.isNotEmpty) _tagFilterBar(),
        for (final e in filtered) _card(e),
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

  /// 多标签交叉筛选对话框
  Future<void> _showTagFilterDialog() async {
    final allTags =
        ref
            .read(diaryListProvider)
            .valueOrNull
            ?.expand((e) => e.tags)
            .toSet() ??
        <String>{};
    final result = await showTagFilterDialog(
      context,
      allTags: allTags.toList(),
      initial: Set.of(_filterTags),
    );
    if (result != null) {
      setState(
        () => _filterTags
          ..clear()
          ..addAll(result),
      );
    }
  }

  Widget _card(DiaryEntry e) {
    final summary = e.plainText.trim().replaceAll('\n', ' ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(e),
        onLongPress: () => _confirmDelete(e),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (e.pinned) ...[
                    const Icon(
                      Icons.push_pin,
                      size: 16,
                      color: AppTheme.danger,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (e.timeStamp.enabled) ...[
                    const Icon(
                      Icons.schedule,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (e.locationStamp.enabled) ...[
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      e.title.isEmpty ? '无标题' : e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _fmtDate(e.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              if (e.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: e.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
