import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import 'quest_detail_page.dart';
import 'quest_edit_page.dart';
import 'quest_models.dart';
import 'quest_repository.dart';
import 'quest_subtree.dart';
import 'quest_trash_page.dart';
import 'quest_weights_dialog.dart';

/// 总览筛选
enum QuestFilter { all, active, stalled, paused, closed }

extension on QuestFilter {
  String get label {
    switch (this) {
      case QuestFilter.all:
        return '全部';
      case QuestFilter.active:
        return '进行中';
      case QuestFilter.stalled:
        return '停滞';
      case QuestFilter.paused:
        return '暂停';
      case QuestFilter.closed:
        return '已结束';
    }
  }
}

/// 任务总览页：**当前重心**（钉住的）排最前，其余按状态分组。
///
/// 这一页要回答的问题只有一个：**接下来我的力气该放哪**。
/// 所以：只列**顶层任务**（子项目在详情页里管理，否则总览会被层级淹掉），
/// 每张卡片直接给出加权进度、目标日期倒数、最近活动 / 停滞天数。
class QuestPage extends ConsumerStatefulWidget {
  const QuestPage({super.key});

  @override
  ConsumerState<QuestPage> createState() => _QuestPageState();
}

class _QuestPageState extends ConsumerState<QuestPage> {
  QuestFilter _filter = QuestFilter.all;

  @override
  Widget build(BuildContext context) {
    final questsAsync = ref.watch(questListProvider);
    final logsAsync = ref.watch(questLogProvider);
    final weights = ref.watch(questWeightsProvider);
    final today = AppTime.dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions: [
          IconButton(
            tooltip: '进度权重（子项目如何影响父任务）',
            icon: const Icon(Icons.tune),
            onPressed: () => showQuestWeightsDialog(context, ref),
          ),
          IconButton(
            tooltip: '回收站',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuestTrashPage()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in QuestFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新任务'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuestEditPage()),
        ),
      ),
      body: questsAsync.when(
        data: (quests) => logsAsync.when(
          data: (logs) => _body(quests, logs, today, weights),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  Widget _body(
    List<Quest> all,
    Map<String, List<InvestLog>> logs,
    String today,
    QuestWeights weights,
  ) {
    // 只列顶层任务：子项目在详情页里看（避免总览被层级淹掉）
    final live = QuestLogic.roots(all);
    if (live.isEmpty) return _empty();
    final progress = QuestLogic.progressMap(all, logs, weights);

    // 先按筛选器过滤
    final filtered = live.where((q) {
      final l = logs[q.id] ?? const <InvestLog>[];
      switch (_filter) {
        case QuestFilter.all:
          return true;
        case QuestFilter.active:
          return q.status == QuestStatus.active;
        case QuestFilter.paused:
          return q.status == QuestStatus.paused;
        case QuestFilter.closed:
          return q.status == QuestStatus.done || q.status == QuestStatus.dropped;
        case QuestFilter.stalled:
          return QuestLogic.isStalled(q, l, today: today);
      }
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          '没有符合条件的任务',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    final pinned = QuestLogic.sorted(
      filtered.where((q) => q.pinned).toList(),
    );
    final others = filtered.where((q) => !q.pinned).toList();
    final active = QuestLogic.sorted(
      others.where((q) => q.status == QuestStatus.active).toList(),
    );
    final paused = QuestLogic.sorted(
      others.where((q) => q.status == QuestStatus.paused).toList(),
    );
    final closed = QuestLogic.sorted(
      others
          .where(
            (q) =>
                q.status == QuestStatus.done ||
                q.status == QuestStatus.dropped,
          )
          .toList(),
    );

    Widget card(Quest q) => _card(
      q,
      logs[q.id] ?? const <InvestLog>[],
      today,
      progress[q.id] ?? 0,
      all,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (pinned.isNotEmpty) ...[
          _section('当前重心', pinned.length, pin: true),
          for (final q in pinned) card(q),
        ],
        if (active.isNotEmpty) ...[
          _section('进行中', active.length),
          for (final q in active) card(q),
        ],
        if (paused.isNotEmpty) ...[
          _section('暂停', paused.length),
          for (final q in paused) card(q),
        ],
        if (closed.isNotEmpty) ...[
          _section('已结束', closed.length),
          for (final q in closed) card(q),
        ],
      ],
    );
  }

  Widget _section(String title, int count, {bool pin = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Row(
      children: [
        if (pin) ...[
          const Icon(Icons.push_pin, size: 14, color: AppTheme.primary),
          const SizedBox(width: 4),
        ],
        Text(
          '$title（$count）',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _card(
    Quest q,
    List<InvestLog> logs,
    String today,
    double progress,
    List<Quest> all,
  ) {
    final stalled = QuestLogic.isStalled(q, logs, today: today);
    final stalledDays = QuestLogic.stalledDays(q, logs, today: today);
    final overdue = QuestLogic.isOverdue(q, today);
    final minutes = QuestLogic.totalMinutes(logs);
    final statusColor = _statusColor(q.status);
    final kids = QuestLogic.childrenOf(all, q.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuestDetailPage(questId: q.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (q.pinned) ...[
                    const Icon(
                      Icons.push_pin,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      q.title.isEmpty ? '未命名任务' : q.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _chip(q.statusLabel, statusColor),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: '更多操作',
                    onSelected: (v) => _menu(q, v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            q.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                          ),
                          title: Text(q.pinned ? '取消钉住' : '钉住（当前重心）'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'addchild',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.account_tree_outlined),
                          title: Text('添加子项目'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'active',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.play_arrow_outlined),
                          title: Text('设为进行中'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'paused',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.pause_outlined),
                          title: Text('设为暂停'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'done',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.check_circle_outline),
                          title: Text('设为已完成'),
                          subtitle: Text(
                            '子项目全部了结才能完成',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'dropped',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.block_outlined),
                          title: Text('设为已放弃'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('编辑'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'archive',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.archive_outlined),
                          title: Text('移入回收站'),
                          subtitle: Text(
                            '有子项目时需先处理',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (q.vision.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  q.vision,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _chip(q.category, AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      QuestLogic.targetLabel(q, today),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: overdue
                            ? AppTheme.danger
                            : AppTheme.textSecondary,
                        fontWeight: overdue ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (q.isLive)
                    Text(
                      stalled
                          ? '停滞 $stalledDays 天'
                          : '最近活动 $stalledDays 天前',
                      style: TextStyle(
                        fontSize: 12,
                        color: stalled
                            ? const Color(0xFFF5A623)
                            : AppTheme.textSecondary,
                        fontWeight: stalled ? FontWeight.w600 : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: AppTheme.divider,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _progressLabel(q, kids),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _meta(q, minutes),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 进度文案：有子项目时说明进度是由子项目加权得来的
  String _progressLabel(Quest q, List<Quest> kids) {
    if (kids.isEmpty) return q.progressLabel;
    final resolved = kids.where(QuestLogic.isResolved).length;
    return '子项目 $resolved/${kids.length} 了结';
  }

  /// 卡片右下角的一行小字：行动项 / 投入
  /// （进度与子项目情况已在别处显示，这里不重复）
  String _meta(Quest q, int minutes) {
    final parts = <String>[
      if (q.todoIds.isNotEmpty) '行动项 ${q.todoIds.length}',
      if (minutes > 0) '已投入 ${QuestLogic.minutesLabel(minutes)}',
    ];
    return parts.isEmpty ? '还没有行动项与投入' : parts.join(' · ');
  }

  Color _statusColor(QuestStatus s) {
    switch (s) {
      case QuestStatus.active:
        return AppTheme.primary;
      case QuestStatus.paused:
        return const Color(0xFFF5A623);
      case QuestStatus.done:
        return const Color(0xFF30A46C);
      case QuestStatus.dropped:
        return AppTheme.textSecondary;
    }
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _menu(Quest q, String v) async {
    final n = ref.read(questListProvider.notifier);
    String? err;
    switch (v) {
      case 'pin':
        await n.togglePin(q.id);
        return;
      case 'addchild':
        await addSubQuest(context, ref, q.id);
        return;
      case 'active':
        err = await n.setStatus(q.id, QuestStatus.active);
      case 'paused':
        err = await n.setStatus(q.id, QuestStatus.paused);
      case 'done':
        err = await n.setStatus(q.id, QuestStatus.done);
      case 'dropped':
        err = await n.setStatus(q.id, QuestStatus.dropped);
      case 'edit':
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuestEditPage(quest: q)),
        );
        return;
      case 'archive':
        err = await n.archive(q.id);
        if (err == null) {
          _snack('已移入回收站');
        }
    }
    if (err != null) _snack(err);
  }

  Widget _empty() => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        '还没有任务。\n\n「任务」用来放那些需要经年累月做的事（长期项目、想学的东西、'
        '要养的长期习惯之外的大事）。\n'
        '点右下角新建，写下目标，再拆几个子项目或里程碑就能开始推进了。',
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
