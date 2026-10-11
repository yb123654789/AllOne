import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/color_picker.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

/// 倒数日回收站：集中展示已归档（`archived`）的**单次**特殊日子，
/// 可「恢复」或「彻底删除」。
///
/// 归档是自动发生的（过期单次项经用户确认后移入），
/// 所以这里也提供「清空回收站」一次清干净。
class SpecialDaysTrashPage extends ConsumerWidget {
  const SpecialDaysTrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(specialDayListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          async.maybeWhen(
            data: (all) {
              final n = all.where((e) => e.archived).length;
              if (n == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空回收站',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _purgeAll(context, ref, n),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        data: (all) {
          final trashed = all.where((e) => e.archived).toList()
            ..sort(
              (a, b) => (b.archivedAt ?? '').compareTo(a.archivedAt ?? ''),
            );
          if (trashed.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '回收站是空的。\n\n单次的日子（如考试）过了之后，'
                  '在「特殊日子 · 倒数日」页确认归档，就会出现在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [for (final e in trashed) _TrashTile(item: e)],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  Future<void> _purgeAll(BuildContext context, WidgetRef ref, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除回收站中的 $count 条特殊日子，无法恢复。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(specialDayListProvider.notifier).purgeAll();
    }
  }
}

/// 回收站条目：显示名称 + 原本日期 + 归档日期，提供恢复 / 彻底删除。
class _TrashTile extends ConsumerWidget {
  final SpecialDay item;

  const _TrashTile({required this.item});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text(
          '将从本地永久删除「${item.name.isEmpty ? '未命名' : item.name}」，无法恢复。确定吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(specialDayListProvider.notifier).delete(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = <String>[
      '原本 ${item.date}',
      if (item.archivedAt != null) '归档于 ${item.archivedAt}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: hexColor(item.color),
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          item.name.isEmpty ? '（未命名）' : item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '恢复',
              icon: const Icon(Icons.restore, color: AppTheme.primary),
              onPressed: () =>
                  ref.read(specialDayListProvider.notifier).restore(item.id),
            ),
            IconButton(
              tooltip: '彻底删除',
              icon: const Icon(Icons.delete_forever, color: AppTheme.danger),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
