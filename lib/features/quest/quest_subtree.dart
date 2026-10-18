import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ui_prefs.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import 'quest_detail_page.dart';
import 'quest_edit_page.dart';
import 'quest_models.dart';
import 'quest_repository.dart';

/// 任务的子项目区块（详情页用）。
///
/// 为什么单独抽出来：它要递归渲染任意深度、要能展开折叠、
/// 还要给每一行提供「调整层级」的操作，放在详情页里会把那一页撑爆。
///
/// 层级调整（用户明确要「方便地调整层级和所属关系」）：
/// 上移 / 下移 · 降一级（挂到上一个同级下面）· 升一级（与父任务平级）·
/// 移动到…（弹出整棵树选新父级，会拒绝移到自己子孙下面）
///
/// 进度表**只算一次**逐层下传：`progressMap` 是 O(整棵树) 的，
/// 如果每一行各自算一遍，子项目一多就会明显卡。
class QuestSubtree extends ConsumerWidget {
  /// 列出这个任务的子项目
  final String parentId;

  const QuestSubtree({super.key, required this.parentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(questListProvider).valueOrNull ?? const <Quest>[];
    final logs = ref.watch(questLogProvider).valueOrNull ?? const {};
    final weights = ref.watch(questWeightsProvider);
    final hideResolved = ref.watch(hideResolvedSubtasksProvider);
    final progress = QuestLogic.progressMap(all, logs, weights);

    final kids = QuestLogic.childrenOf(all, parentId);
    final visible = hideResolved
        ? kids.where((c) => !QuestLogic.isResolved(c)).toList()
        : kids;
    final resolvedCount = kids.where(QuestLogic.isResolved).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '子项目',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kids.isEmpty
                        ? '还没有子项目'
                        : '${kids.length} 个 · 已了结 $resolvedCount',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '添加子项目',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => addSubQuest(context, ref, parentId),
                ),
              ],
            ),
            if (kids.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: Icon(
                    hideResolved
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text(
                    hideResolved ? '显示已了结' : '隐藏已了结',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => ref
                      .read(uiPrefsProvider.notifier)
                      .set(UiPrefs.hideResolvedSubtasksKey, !hideResolved),
                ),
              ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  kids.isEmpty
                      ? '把大任务拆成几个子项目，父任务的进度会按子项目加权算出来。'
                      : '子项目都已了结（点「显示已了结」可以再看）。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              for (final c in visible)
                _SubQuestRow(
                  quest: c,
                  all: all,
                  progress: progress,
                  depth: 1,
                  hideResolved: hideResolved,
                ),
            const SizedBox(height: 2),
            if (kids.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 2, top: 4),
                child: Text(
                  '升/降级与移动都在每行的「⋮」里；有子项目的任务不能直接删除或归档。',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子项目的一行（递归渲染自己的子项目）
class _SubQuestRow extends ConsumerStatefulWidget {
  final Quest quest;
  final List<Quest> all;
  final Map<String, double> progress;
  final int depth;
  final bool hideResolved;

  const _SubQuestRow({
    required this.quest,
    required this.all,
    required this.progress,
    required this.depth,
    required this.hideResolved,
  });

  @override
  ConsumerState<_SubQuestRow> createState() => _SubQuestRowState();
}

class _SubQuestRowState extends ConsumerState<_SubQuestRow> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    final pct = ((widget.progress[q.id] ?? 0) * 100).round();

    final kids = QuestLogic.childrenOf(widget.all, q.id);
    final visibleKids = widget.hideResolved
        ? kids.where((c) => !QuestLogic.isResolved(c)).toList()
        : kids;
    final resolved = QuestLogic.isResolved(q);
    final color = q.status == QuestStatus.done
        ? const Color(0xFF30A46C)
        : q.status == QuestStatus.dropped
        ? AppTheme.textSecondary
        : q.status == QuestStatus.paused
        ? const Color(0xFFF5A623)
        : AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => QuestDetailPage(questId: q.id)),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: (widget.depth - 1) * 16.0),
            child: Row(
              children: [
                // 归属指引线：层级一深，光靠缩进容易看错归属
                Container(
                  width: 1,
                  height: 20,
                  color: AppTheme.divider,
                ),
                const SizedBox(width: 6),
                // 展开箭头（有子项目才显示）
                SizedBox(
                  width: 26,
                  child: kids.isEmpty
                      ? null
                      : IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: _expanded ? '收起' : '展开',
                          icon: Icon(
                            _expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                          ),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                        ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    q.title.isEmpty ? '未命名' : q.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.depth <= 1 ? 14 : 13,
                      decoration: resolved ? TextDecoration.lineThrough : null,
                      color: resolved ? AppTheme.textSecondary : null,
                    ),
                  ),
                ),
                if (kids.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${kids.length} 项',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                // 子项目的「完成」快捷入口。
                // 之前这里只有「打开 / 层级调整 / 删除」，想完成子项目必须
                // 打开 → 编辑 → 改状态 → 保存，实际上等于「只能创建、无法完成」。
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: resolved ? '恢复为进行中' : '标记完成',
                  icon: Icon(
                    resolved
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    size: 20,
                    color: resolved
                        ? const Color(0xFF30A46C)
                        : AppTheme.textSecondary,
                  ),
                  onPressed: () => _toggleResolved(context, ref, q),
                ),
                _menu(context, ref, q),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final k in visibleKids)
            _SubQuestRow(
              quest: k,
              all: widget.all,
              progress: widget.progress,
              depth: widget.depth + 1,
              hideResolved: widget.hideResolved,
            ),
      ],
    );
  }

  /// 一键完成 / 恢复（子项目最常用的操作，不该藏在编辑页里）
  Future<void> _toggleResolved(
    BuildContext context,
    WidgetRef ref,
    Quest q,
  ) async {
    final target = QuestLogic.isResolved(q)
        ? QuestStatus.active
        : QuestStatus.done;
    final err = await ref.read(questListProvider.notifier).setStatus(q.id, target);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            err ??
                (target == QuestStatus.done ? '已标记完成' : '已恢复为进行中'),
          ),
          duration: Duration(seconds: err == null ? 2 : 5),
        ),
      );
  }

  Widget _menu(BuildContext context, WidgetRef ref, Quest q) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
      tooltip: '调整 / 操作',
      onSelected: (v) => _act(context, ref, q, v),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_new, size: 18),
            title: Text('打开'),
          ),
        ),
        const PopupMenuItem(
          value: 'add',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add, size: 18),
            title: Text('添加子项目'),
          ),
        ),
        // 状态操作：完成有行内按钮，这里补「暂停 / 放弃 / 恢复」
        if (q.status != QuestStatus.paused)
          const PopupMenuItem(
            value: 'paused',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.pause_circle_outline, size: 18),
              title: Text('设为暂停'),
            ),
          ),
        if (!QuestLogic.isResolved(q))
          const PopupMenuItem(
            value: 'dropped',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cancel_outlined, size: 18),
              title: Text('设为放弃'),
              subtitle: Text('放弃也算了结，不再卡住父任务', style: TextStyle(fontSize: 11)),
            ),
          ),
        if (QuestLogic.isResolved(q))
          const PopupMenuItem(
            value: 'active',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.play_circle_outline, size: 18),
              title: Text('恢复为进行中'),
            ),
          ),
        const PopupMenuItem(
          value: 'up',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.arrow_upward, size: 18),
            title: Text('上移'),
          ),
        ),
        const PopupMenuItem(
          value: 'down',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.arrow_downward, size: 18),
            title: Text('下移'),
          ),
        ),
        const PopupMenuItem(
          value: 'indent',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.subdirectory_arrow_right, size: 18),
            title: Text('降一级'),
            subtitle: Text('挂到上一个同级下面', style: TextStyle(fontSize: 11)),
          ),
        ),
        const PopupMenuItem(
          value: 'outdent',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.subdirectory_arrow_left, size: 18),
            title: Text('升一级'),
            subtitle: Text('与父任务平级', style: TextStyle(fontSize: 11)),
          ),
        ),
        const PopupMenuItem(
          value: 'move',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.drive_file_move_outline, size: 18),
            title: Text('移动到…'),
            subtitle: Text('选一个新的父任务', style: TextStyle(fontSize: 11)),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline,
              size: 18,
              color: AppTheme.danger,
            ),
            title: Text('删除'),
          ),
        ),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Quest q,
    String v,
  ) async {
    final n = ref.read(questListProvider.notifier);
    String? err;
    switch (v) {
      case 'open':
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuestDetailPage(questId: q.id)),
        );
        return;
      case 'add':
        await addSubQuest(context, ref, q.id);
        return;
      case 'paused':
        err = await n.setStatus(q.id, QuestStatus.paused);
      case 'dropped':
        err = await n.setStatus(q.id, QuestStatus.dropped);
      case 'active':
        err = await n.setStatus(q.id, QuestStatus.active);
      case 'up':
        err = await n.moveSibling(q.id, -1);
      case 'down':
        err = await n.moveSibling(q.id, 1);
      case 'indent':
        err = await n.indent(q.id);
      case 'outdent':
        err = await n.outdent(q.id);
      case 'move':
        if (!context.mounted) return;
        final target = await _pickParent(context, ref, q);
        if (target == null) return;
        err = await n.moveTo(q.id, target);
      case 'delete':
        if (!context.mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除子项目'),
            content: Text(
              '将删除「${q.title.isEmpty ? '未命名' : q.title}」及其里程碑、'
              '投入记录（关联的待办不会删）。\n\n'
              '如果它还有子项目，需要先处理掉。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        err = await n.delete(q.id);
    }
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    }
  }

  /// 选一个新的父任务：列出整棵树（含「顶层」），排除自己与自己的子孙
  Future<String?> _pickParent(
    BuildContext context,
    WidgetRef ref,
    Quest q,
  ) async {
    final all = ref.read(questListProvider).valueOrNull ?? const <Quest>[];
    final forbidden = {
      q.id,
      ...QuestLogic.descendants(all, q.id).map((d) => d.id),
    };
    final options = <(String, String)>[('', '顶层（不再属于任何任务）')];
    void walk(String parentId, int depth) {
      for (final c in QuestLogic.childrenOf(all, parentId)) {
        if (forbidden.contains(c.id)) continue;
        options.add((
          c.id,
          '${'　' * depth}${c.title.isEmpty ? '未命名' : c.title}',
        ));
        walk(c.id, depth + 1);
      }
    }

    walk('', 0);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移动到…'),
        content: SizedBox(
          width: 380,
          height: 380,
          child: ListView(
            children: [
              for (final (id, label) in options)
                ListTile(
                  dense: true,
                  leading: Icon(
                    id.isEmpty
                        ? Icons.home_outlined
                        : Icons.subdirectory_arrow_right,
                    size: 18,
                  ),
                  title: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(ctx, id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 新建一个子项目。
///
/// 走**完整的编辑页**（标题 / 描述 / 附件 / 时间），不再是一个只有名字的输入框 ——
/// 子项目常常需要一张参考图、一段语音或几个文件来说明，光有标题不够用。
Future<void> addSubQuest(
  BuildContext context,
  WidgetRef ref,
  String parentId,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => QuestEditPage(parentId: parentId)),
  );
}
