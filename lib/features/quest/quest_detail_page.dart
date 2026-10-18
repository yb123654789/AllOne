import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/attachment_view.dart';
import '../todo/todo_models.dart';
import '../todo/todo_repository.dart';
import 'quest_edit_page.dart';
import 'quest_models.dart';
import 'quest_repository.dart';
import 'quest_subtree.dart';

/// 状态中文名（详情页的状态菜单用）
String _statusText(QuestStatus s) {
  switch (s) {
    case QuestStatus.active:
      return '进行中';
    case QuestStatus.paused:
      return '暂停';
    case QuestStatus.done:
      return '已完成';
    case QuestStatus.dropped:
      return '已放弃';
  }
}

/// 任务详情页：**推进这个任务的地方**。
///
/// 三个区块对应三种推进方式：
/// ① 里程碑（阶段）—— 勾选即推进，进度由它算；
/// ② 行动项（关联待办）—— 「下一步做什么」落到待办模块里去做；
/// ③ 投入记录 —— 花了多少时间，决定它是否算「停滞」。
class QuestDetailPage extends ConsumerWidget {
  final String questId;

  const QuestDetailPage({super.key, required this.questId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(questListProvider).valueOrNull;
    final logsMap = ref.watch(questLogProvider).valueOrNull;
    if (quests == null || logsMap == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    Quest? found;
    for (final x in quests) {
      if (x.id == questId) found = x;
    }
    if (found == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('任务详情')),
        body: const Center(child: Text('任务不存在或已删除')),
      );
    }
    final q = found;
    final logs = logsMap[q.id] ?? const <InvestLog>[];
    final today = AppTime.dateOnly(DateTime.now());
    final stalled = QuestLogic.isStalled(q, logs, today: today);
    final stalledDays = QuestLogic.stalledDays(q, logs, today: today);
    // 进度按「子项目加权」递归计算（没有子项目时回退到里程碑 / 手动百分比）
    final weights = ref.watch(questWeightsProvider);
    final progress = QuestLogic.progressMap(quests, logsMap, weights)[q.id] ?? 0;
    final kids = QuestLogic.childrenOf(quests, q.id);
    final progressNote = kids.isEmpty
        ? q.progressLabel
        : '子项目 ${kids.length} 个 · 进度按子项目加权';

    return Scaffold(
      appBar: AppBar(
        title: Text(q.title.isEmpty ? '未命名任务' : q.title),
        actions: [
          IconButton(
            tooltip: q.pinned ? '取消钉住' : '钉住（当前重心）',
            icon: Icon(q.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () =>
                ref.read(questListProvider.notifier).togglePin(q.id),
          ),
          // 状态切换放在详情页：子项目只会在这里被打开，
          // 没有这个入口就只能绕到「编辑 → 状态」里去改，等于改不了。
          PopupMenuButton<QuestStatus>(
            tooltip: '设置状态',
            icon: const Icon(Icons.flag_outlined),
            onSelected: (s) async {
              final err = await ref
                  .read(questListProvider.notifier)
                  .setStatus(q.id, s);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(err ?? '状态已改为「${_statusText(s)}」'),
                    duration: Duration(seconds: err == null ? 2 : 5),
                  ),
                );
            },
            itemBuilder: (_) => [
              for (final s in QuestStatus.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      // 标出当前状态，避免「点了没反应」的错觉
                      SizedBox(
                        width: 24,
                        child: s == q.status
                            ? const Icon(Icons.check, size: 16)
                            : null,
                      ),
                      Text('设为${_statusText(s)}'),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => QuestEditPage(quest: q)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (stalled)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5A623).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_bottom, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已经 $stalledDays 天没有推进了 —— 要么记一笔投入，'
                      '要么把它设为「暂停」，别让它一直挂着。',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          _headCard(q, today, logs, progress, progressNote),
          const SizedBox(height: 14),
          QuestSubtree(parentId: q.id),
          const SizedBox(height: 14),
          _milestones(context, ref, q),
          if (q.media.isNotEmpty) ...[
            const SizedBox(height: 14),
            _attachments(context, ref, q),
          ],
          const SizedBox(height: 14),
          _actions(context, ref, q),
          const SizedBox(height: 14),
          _invest(context, ref, q, logs, today),
        ],
      ),
    );
  }

  // ── 附件：参考图 / 录音 / 视频 / 文件 ──────────────────────────────────

  Widget _attachments(BuildContext context, WidgetRef ref, Quest q) {
    final root = ref.read(jsonStoreProvider).valueOrNull?.root.path;
    final mediaDir = root == null ? null : p.join(root, questMediaDir(q.id));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '附件（${q.media.length}）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '点一下打开：图片看大图 / 录音直接播 / 文件交给系统程序',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => QuestEditPage(quest: q)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            for (final m in q.media) AttachmentTile(media: m, mediaDir: mediaDir),
          ],
        ),
      ),
    );
  }

  // ── 头部：状态 / 进度 / 目标 ────────────────────────────────────────────

  Widget _headCard(
    Quest q,
    String today,
    List<InvestLog> logs,
    double progress,
    String progressNote,
  ) {
    final overdue = QuestLogic.isOverdue(q, today);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  q.statusLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  q.category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (q.vision.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                q.vision,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppTheme.divider,
                color: q.status == QuestStatus.done
                    ? const Color(0xFF30A46C)
                    : AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  progressNote,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  QuestLogic.targetLabel(q, today),
                  style: TextStyle(
                    fontSize: 12,
                    color: overdue ? AppTheme.danger : AppTheme.textSecondary,
                  ),
                ),
                if (q.startDate.isNotEmpty)
                  Text(
                    '始于 ${q.startDate}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 里程碑 ──────────────────────────────────────────────────────────────

  Widget _milestones(BuildContext context, WidgetRef ref, Quest q) {
    final n = ref.read(questListProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '里程碑（阶段）',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  q.usesMilestones
                      ? '${q.milestoneDone}/${q.milestoneTotal} · 进度由它计算'
                      : '还没有里程碑（进度用手动百分比）',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '添加里程碑',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _addMilestone(context, ref, q),
                ),
              ],
            ),
            if (q.milestones.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  '把长期任务切成几段，每段一个里程碑（如「第一版写完」）。',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final m in q.milestones)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: m.done,
                  onChanged: (_) => n.toggleMilestone(q.id, m.id),
                  title: Text(
                    m.title.isEmpty ? '未命名里程碑' : m.title,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: m.done ? TextDecoration.lineThrough : null,
                      color: m.done ? AppTheme.textSecondary : null,
                    ),
                  ),
                  subtitle: (m.dueDate.isEmpty && m.doneAt.isEmpty)
                      ? null
                      : Text(
                          [
                            if (m.dueDate.isNotEmpty) '计划 $m.dueDate',
                            if (m.doneAt.isNotEmpty) '完成于 $m.doneAt',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                  secondary: IconButton(
                    tooltip: '删除里程碑',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => n.removeMilestone(q.id, m.id),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMilestone(
    BuildContext context,
    WidgetRef ref,
    Quest q,
  ) async {
    final titleCtrl = TextEditingController();
    String due = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('添加里程碑'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '阶段目标（如：第一版写完）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      due.isEmpty ? '计划完成日期：未设置' : '计划完成：$due',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.tryParse(due) ?? now,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 30),
                      );
                      if (picked != null) {
                        setLocal(() => due = AppTime.dateOnly(picked));
                      }
                    },
                    child: const Text('选日期'),
                  ),
                ],
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
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    await ref
        .read(questListProvider.notifier)
        .addMilestone(q.id, title, dueDate: due);
  }

  // ── 行动项（关联待办） ──────────────────────────────────────────────────

  Widget _actions(BuildContext context, WidgetRef ref, Quest q) {
    final todos =
        ref.watch(todoListProvider).valueOrNull ?? const <TodoItem>[];
    final byId = {for (final t in todos) t.id: t};
    final n = ref.read(questListProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '行动项（关联待办）',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '下一步要做的事，仍然在「待办」里管理',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关联待办',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _pickTodo(context, ref, q, todos),
                ),
              ],
            ),
            if (q.todoIds.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  '还没有行动项。长期任务要靠一件件待办推进，'
                  '把「下一步」挂上来。',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final id in q.todoIds)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    byId[id] == null
                        ? Icons.link_off
                        : (byId[id]!.status == TodoStatus.done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked),
                    size: 18,
                    color: byId[id] == null
                        ? AppTheme.textSecondary
                        : (byId[id]!.status == TodoStatus.done
                              ? const Color(0xFF30A46C)
                              : AppTheme.primary),
                  ),
                  title: Text(
                    byId[id]?.title.isNotEmpty == true
                        ? byId[id]!.title
                        : '（无标题待办）',
                    style: TextStyle(
                      fontSize: 14,
                      decoration:
                          byId[id]?.status == TodoStatus.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: byId[id] == null
                      ? const Text(
                          '该待办已被删除（可解除关联）',
                          style: TextStyle(fontSize: 11, color: AppTheme.danger),
                        )
                      : (byId[id]!.deadline.date.isEmpty
                            ? null
                            : Text(
                                '截止 ${byId[id]!.deadline.date}'
                                '${byId[id]!.deadline.time.isEmpty ? '' : ' ${byId[id]!.deadline.time}'}',
                                style: const TextStyle(fontSize: 11),
                              )),
                  trailing: IconButton(
                    tooltip: '解除关联',
                    icon: const Icon(Icons.link_off, size: 16),
                    onPressed: () => n.unlinkTodo(q.id, id),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTodo(
    BuildContext context,
    WidgetRef ref,
    Quest q,
    List<TodoItem> todos,
  ) async {
    final candidates = todos
        .where((t) => !q.todoIds.contains(t.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可关联的待办了 —— 先去「待办」页新建一个'),
        ),
      );
      return;
    }
    // 未完成的排前面
    candidates.sort((a, b) {
      final ad = a.status == TodoStatus.done ? 1 : 0;
      final bd = b.status == TodoStatus.done ? 1 : 0;
      if (ad != bd) return ad - bd;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关联待办'),
        content: SizedBox(
          width: 380,
          height: 360,
          child: ListView(
            children: [
              for (final t in candidates)
                ListTile(
                  dense: true,
                  leading: Icon(
                    t.status == TodoStatus.done
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  title: Text(
                    t.title.isEmpty ? '（无标题待办）' : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: t.deadline.date.isEmpty
                      ? null
                      : Text(
                          '截止 ${t.deadline.date}',
                          style: const TextStyle(fontSize: 11),
                        ),
                  onTap: () => Navigator.pop(ctx, t.id),
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
    if (picked == null) return;
    await ref.read(questListProvider.notifier).linkTodo(q.id, picked);
  }

  // ── 投入记录 ────────────────────────────────────────────────────────────

  Widget _invest(
    BuildContext context,
    WidgetRef ref,
    Quest q,
    List<InvestLog> logs,
    String today,
  ) {
    final stats = QuestStats.of(q, logs, today);
    final weeks = QuestLogic.weeklyMinutes(logs, today: today, weeks: 12);
    final sorted = [...logs]..sort((a, b) => b.at.compareTo(a.at));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '投入记录',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stats.investCount == 0
                        ? '还没记过投入'
                        : '${stats.investCount} 次 · 合计 ${stats.totalLabel}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => _addInvest(context, ref, q),
                  child: const Text('记一笔'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _bars(weeks),
            const Center(
              child: Text(
                '近 12 周每周投入',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
            if (sorted.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              for (final l in sorted.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.timer_outlined, size: 18),
                  title: Text(
                    QuestLogic.minutesLabel(l.minutes),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    [
                      _stamp(l.at),
                      if (l.note.isNotEmpty) l.note,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: '删除这条记录',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => ref
                        .read(questLogProvider.notifier)
                        .remove(q.id, l.id),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bars(List<int> weeks) {
    final maxV = weeks.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in weeks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Tooltip(
                  message: QuestLogic.minutesLabel(v),
                  child: Container(
                    height: maxV <= 0 ? 3 : (4 + 52 * (v / maxV)),
                    decoration: BoxDecoration(
                      color: v <= 0
                          ? AppTheme.divider
                          : AppTheme.primary.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _addInvest(
    BuildContext context,
    WidgetRef ref,
    Quest q,
  ) async {
    final minutesCtrl = TextEditingController(text: '30');
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '记一笔投入 · ${q.title.isEmpty ? '未命名任务' : q.title}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minutesCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '这次投入多少分钟',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final m in const [15, 30, 60, 120])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('$m 分'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => minutesCtrl.text = '$m',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '做了什么（可空）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('记下'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final minutes = int.tryParse(minutesCtrl.text.trim()) ?? 0;
    if (minutes <= 0) return;
    await ref
        .read(questLogProvider.notifier)
        .append(q.id, minutes: minutes, note: noteCtrl.text);
  }
}
