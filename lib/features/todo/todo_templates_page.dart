import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'todo_models.dart';
import 'todo_repository.dart';
import 'todo_template_edit_page.dart';

/// 待办模板管理 / 选择页。
///
/// - `selectable == false`（默认）：管理页，可新建 / 编辑 / 删除模板。
/// - `selectable == true`：选择页（从待办编辑页进入），点击模板即返回该模板。
class TodoTemplatesPage extends ConsumerWidget {
  final bool selectable;

  const TodoTemplatesPage({super.key, this.selectable = false});

  Future<void> _useTemplate(
    BuildContext context,
    WidgetRef ref,
    TodoTemplate t,
  ) async {
    if (selectable) {
      Navigator.pop(context, t);
      return;
    }
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
              title: const Text('使用此模板创建待办'),
              onTap: () => Navigator.pop(ctx, 'use'),
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: AppTheme.primary),
              title: const Text('编辑模板'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('删除模板'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (act == 'use') {
      Navigator.pop(context, t);
    } else if (act == 'edit') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TodoTemplateEditPage(template: t)),
      );
    } else if (act == 'delete') {
      await ref.read(todoTemplateListProvider.notifier).delete(t.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(todoTemplateListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(selectable ? '选择待办模板' : '待办模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '说明',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('待办模板'),
                content: const Text(
                  '模板可整体保存「内容 + 截止时间 + 地点 + 标签」，'
                  '新建待办时一键套用，无需重复填写。\n\n'
                  '模板存放在 AllOneData/todo/templates/ 下，格式通用，随备份一起导出。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: async.when(
        data: (templates) => templates.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 64,
                      color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '还没有待办模板',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    if (!selectable) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TodoTemplateEditPage(),
                          ),
                        ),
                        child: const Text('新建一个'),
                      ),
                    ],
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [for (final t in templates) _tile(context, ref, t)],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: selectable
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TodoTemplateEditPage()),
              ),
              tooltip: '新建模板',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, TodoTemplate t) {
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.description_outlined,
          color: AppTheme.primary,
        ),
        title: Text(t.name.isEmpty ? '未命名模板' : t.name),
        subtitle: Text(
          [
            if (t.title.isNotEmpty) t.title,
            if (t.deadline.date.isNotEmpty) '截止 ${t.deadline.date}',
            if (t.location.text.isNotEmpty) '地点 ${t.location.text}',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _useTemplate(context, ref, t),
      ),
    );
  }
}
