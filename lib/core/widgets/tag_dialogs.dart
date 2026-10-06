import 'package:flutter/material.dart';

import '../theme.dart';

/// 标签选择 / 复用对话框：支持**模糊搜索**已有标签并点击复用、输入新标签、删除已选。
/// 返回点击「完成」时选中的标签列表（null = 取消）。
Future<List<String>?> showTagPicker(
  BuildContext context, {
  required List<String> allTags,
  required List<String> initial,
  String title = '标签',
}) async {
  var selected = List<String>.of(initial);
  var query = '';
  final inputCtrl = TextEditingController();
  try {
    return await showDialog<List<String>>(
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
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索已有标签（模糊匹配，避免忘记标签名）…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialog(() => query = v),
                  ),
                  if (selected.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '已选标签',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: selected
                          .map(
                            (t) => InputChip(
                              label: Text(t),
                              onDeleted: () =>
                                  setDialog(() => selected.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (allTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '已有标签（点击添加）',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: candidates
                              .map(
                                (t) => ActionChip(
                                  label: Text(t),
                                  avatar: selected.contains(t)
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: AppTheme.primary,
                                        )
                                      : null,
                                  onPressed: selected.contains(t)
                                      ? null
                                      : () => setDialog(() => selected.add(t)),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputCtrl,
                          decoration: const InputDecoration(
                            hintText: '输入新标签后回车',
                          ),
                          onSubmitted: (_) {
                            final s = inputCtrl.text.trim();
                            if (s.isNotEmpty && !selected.contains(s)) {
                              setDialog(() => selected.add(s));
                              inputCtrl.clear();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final s = inputCtrl.text.trim();
                          if (s.isNotEmpty && !selected.contains(s)) {
                            setDialog(() => selected.add(s));
                            inputCtrl.clear();
                          }
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    inputCtrl.dispose();
  }
}

/// 多标签交叉筛选对话框（AND 交集）：勾选多个标签，支持模糊搜索。
/// 返回选中的筛选标签集合；「清除」返回空集合；null = 取消。
Future<Set<String>?> showTagFilterDialog(
  BuildContext context, {
  required List<String> allTags,
  required Set<String> initial,
}) {
  var selected = Set<String>.of(initial);
  var query = '';
  return showDialog<Set<String>>(
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
                  '勾选多个标签：只显示同时包含全部所选标签的条目',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                if (selected.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: selected
                        .map(
                          (t) => InputChip(
                            label: Text(t),
                            onDeleted: () =>
                                setDialog(() => selected.remove(t)),
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
                                selected: selected.contains(t),
                                onSelected: (v) => setDialog(() {
                                  if (v) {
                                    selected.add(t);
                                  } else {
                                    selected.remove(t);
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
              onPressed: () => Navigator.pop(ctx, <String>{}),
              child: const Text('清除', style: TextStyle(color: AppTheme.danger)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('完成'),
            ),
          ],
        );
      },
    ),
  );
}
