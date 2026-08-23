import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'diary_models.dart';
import 'diary_repository.dart';

/// 日记模板管理页。
class DiaryTemplatesPage extends ConsumerWidget {
  const DiaryTemplatesPage({super.key});

  Future<void> _createTemplate(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建模板'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '模板名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '模板内容（引导文本，可后续编辑）'),
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref
          .read(diaryTemplateListProvider.notifier)
          .save(
            DiaryTemplate(
              id: AppPaths.newId(),
              name: nameCtrl.text.trim(),
              contentDelta: contentCtrl.text.trim(),
              plainText: contentCtrl.text.trim(),
              createdAt: DateTime.now(),
            ),
          );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DiaryTemplate t,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确定删除模板「${t.name}」吗？'),
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
      await ref.read(diaryTemplateListProvider.notifier).delete(t.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(diaryTemplateListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('日记模板')),
      body: async.when(
        data: (templates) => templates.isEmpty
            ? const Center(
                child: Text(
                  '暂无模板，点击右下角 + 创建',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            : ListView.builder(
                itemCount: templates.length,
                itemBuilder: (ctx, i) {
                  final t = templates[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: AppTheme.primary,
                      ),
                      title: Text(t.name.isEmpty ? '未命名模板' : t.name),
                      subtitle: Text(
                        t.plainText.isEmpty ? '（空模板）' : t.plainText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, t),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createTemplate(context, ref),
        tooltip: '新建模板',
        child: const Icon(Icons.add),
      ),
    );
  }
}
