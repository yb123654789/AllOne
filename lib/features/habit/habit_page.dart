import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'habit_edit_page.dart';
import 'habit_models.dart';
import 'habit_repository.dart';
import 'habit_trash_page.dart';

/// 习惯模块入口页：习惯列表 + 打卡。
class HabitPage extends ConsumerStatefulWidget {
  const HabitPage({super.key});

  @override
  ConsumerState<HabitPage> createState() => _HabitPageState();
}

class _HabitPageState extends ConsumerState<HabitPage> {
  /// 多标签交叉筛选（AND：必须同时包含全部所选标签）
  Set<String> _filterTags = {};

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitListProvider);
    final checkinAsync = ref.watch(habitCheckinProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('习惯'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '回收站',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HabitTrashPage()),
            ),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _filterTags.isNotEmpty,
              label: Text('${_filterTags.length}'),
              child: const Icon(Icons.filter_alt_outlined),
            ),
            tooltip: '按标签筛选（多标签交叉）',
            onPressed: _showTagFilterDialog,
          ),
        ],
      ),
      body: habitsAsync.when(
        data: (habits) => checkinAsync.when(
          data: (checkins) => habits.isEmpty
              ? _empty()
              : _list(context, ref, habits, checkins),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HabitEditPage()),
        ),
        tooltip: '新建习惯',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.repeat_outlined,
          size: 64,
          color: AppTheme.textSecondary.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 12),
        const Text('还没有习惯', style: TextStyle(color: AppTheme.textSecondary)),
      ],
    ),
  );

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<Habit> habits,
    Map<String, CheckinMap> checkins,
  ) {
    // 过滤掉已归档的；对「坚持周期达成」的进行自动归档（在 build 后延迟触发）
    final filtered = habits
        .where((h) => !h.archived && _filterTags.every((t) => h.tags.contains(t)))
        .toList();
    // 自动归档：达成目标（非不限/非循环且进度>=1）的习惯移入回收站
    for (final h in filtered) {
      final cm = checkins[h.id] ?? const CheckinMap();
      if (_isCompleted(h, cm)) {
        // 延迟到帧后异步归档，避免在 build 中直接写状态触发重建
        Future.microtask(
          () => ref.read(habitListProvider.notifier).archiveHabit(h.id),
        );
      }
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _filterTags.isEmpty ? '没有习惯' : '没有匹配的习惯（请调整筛选标签）',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (_filterTags.isNotEmpty) _tagFilterBar(),
        for (final h in filtered)
          if (!_isCompleted(h, checkins[h.id] ?? const CheckinMap()))
            _habitCard(context, ref, h, checkins),
      ],
    );
  }

  /// 判断习惯是否已「完成」（坚持周期达成且非不限 / 非循环）。
  bool _isCompleted(Habit h, CheckinMap cm) {
    if (h.persistence == HabitPersistence.unlimited ||
        h.persistence == HabitPersistence.cycles) {
      return false;
    }
    final today = AppTime.dateOnly(DateTime.now());
    bool met(String d) => cm.dayMet(d, h.dailyTarget, h.dailyTargetValue);
    final doneDays = cm.entries.keys.where(met).length;
    final doneTotal = cm.totalCount;
    final (progress, _) = _persistenceProgress(h, cm, doneDays, doneTotal);
    return progress >= 1.0;
  }

  Widget _habitCard(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    Map<String, CheckinMap> checkins,
  ) {
    final cm = checkins[h.id] ?? const CheckinMap();
    return _card(context, ref, h, cm);
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
    final allTags = ref
            .read(habitListProvider)
            .valueOrNull
            ?.expand((h) => h.tags)
            .toSet() ??
        <String>{};
    final result = await showTagFilterDialog(
      context,
      allTags: allTags.toList(),
      initial: Set.of(_filterTags),
    );
    if (result != null) setState(() => _filterTags..clear()..addAll(result));
  }

  /// 依据坚持周期计算进度 (0.0~1.0) 与展示文案。
  /// [doneDays] 达标天数，[doneTotal] 达标次数（累计打卡数）。
  (double, String) _persistenceProgress(
    Habit h,
    CheckinMap cm,
    int doneDays,
    int doneTotal,
  ) {
    final pv = h.persistenceValue;
    switch (h.persistence) {
      case HabitPersistence.unlimited:
        return (0, '不限 · 已达标 $doneDays 天');
      case HabitPersistence.days:
        final p = pv <= 0 ? 0.0 : (doneDays / pv).clamp(0.0, 1.0);
        return (p, '坚持 $doneDays/$pv 天');
      case HabitPersistence.times:
        final p = pv <= 0 ? 0.0 : (doneTotal / pv).clamp(0.0, 1.0);
        return (p, '累计 $doneTotal/$pv 次');
      case HabitPersistence.cycles:
        // 每轮 pv 天，计算已完成的完整轮数 + 本轮进度
        final p = pv <= 0 ? 0.0 : (doneDays % pv) / pv;
        final rounds = pv <= 0 ? 0 : doneDays ~/ pv;
        return (
          p,
          '第 ${rounds + 1} 轮 · 本轮 ${doneDays % pv}/$pv 天',
        );
    }
  }

  /// 频率说明文案
  String _frequencyText(Habit h) {
    switch (h.frequency) {
      case HabitFrequency.daily:
        return '每天';
      case HabitFrequency.weekly:
        final names = h.weekdays.map(_weekdayName).join('/');
        return '每周 $names'.trim();
      case HabitFrequency.interval:
        return '每 ${h.intervalDays} 天';
      case HabitFrequency.weeklyTimes:
        return '每周 ${h.weeklyTimes} 次';
    }
  }

  String _weekdayName(int d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return (d >= 1 && d <= 7) ? names[d - 1] : '?';
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    CheckinMap cm,
  ) {
    final today = AppTime.dateOnly(DateTime.now());
    final doneToday = cm.isDone(today);
    final failedToday = cm.isFailed(today);
    // 依据「当天目标」判断达标
    bool met(String d) => cm.dayMet(d, h.dailyTarget, h.dailyTargetValue);
    // 统计达标天数 / 达标次数
    final doneDays = cm.entries.keys.where(met).length;
    final doneTotal = cm.totalCount;
    // 持久周期进度
    final (progress, progressText) = _persistenceProgress(h, cm, doneDays, doneTotal);
    // 频率说明
    final freqText = _frequencyText(h);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editHabit(context, h),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      h.title.isEmpty ? '未命名习惯' : h.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _checkinButton(context, ref, h, doneToday, failedToday),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: '更多操作',
                    onSelected: (v) => _menuAction(context, ref, h, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('编辑习惯'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.archive_outlined),
                          title: Text('移到回收站'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: AppTheme.danger,
                          ),
                          title: Text('删除习惯'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _tag(h.category),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$freqText · $progressText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '连续 ${cm.streakDays(DateTime.now(), isMet: met)} 天',
                    style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                  ),
                ],
              ),
              if (h.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  h.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              if (h.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: h.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
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
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.divider,
                  color: failedToday
                      ? AppTheme.danger
                      : doneToday
                      ? Colors.green
                      : AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editHabit(BuildContext context, Habit h) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HabitEditPage(habit: h)),
    );
  }

  Future<void> _menuAction(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    String v,
  ) async {
    if (v == 'edit') {
      _editHabit(context, h);
    } else if (v == 'archive') {
      await ref.read(habitListProvider.notifier).archiveHabit(h.id);
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除习惯'),
          content: Text('将永久删除「${h.title.isEmpty ? '未命名习惯' : h.title}」及其全部打卡记录，无法恢复。确定吗？'),
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
        await ref.read(habitListProvider.notifier).deleteHabit(h.id);
      }
    }
  }

  Widget _checkinButton(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    bool doneToday,
    bool failedToday,
  ) {
    final IconData icon;
    final Color color;
    final String label;
    if (doneToday) {
      icon = Icons.check_circle;
      color = Colors.green;
      label = '已打卡';
    } else if (failedToday) {
      icon = Icons.cancel;
      color = AppTheme.danger;
      label = '失败';
    } else {
      icon = Icons.radio_button_unchecked;
      color = AppTheme.primary;
      label = '打卡';
    }
    return TextButton.icon(
      onPressed: () => _showCheckinSheet(context, ref, h),
      icon: Icon(icon, color: color, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: color),
    );
  }

  /// 打卡弹窗：完成（可输入本次数量/分钟）/ 失败 / 清除今日记录
  Future<void> _showCheckinSheet(
    BuildContext context,
    WidgetRef ref,
    Habit h,
  ) async {
    final today = AppTime.dateOnly(DateTime.now());
    final notifier = ref.read(habitCheckinProvider.notifier);
    final target = h.dailyTarget;
    final targetValue = h.dailyTargetValue;

    // 「一次即完成」目标：直接打卡，无需输入数值
    if (target == HabitDailyTarget.once) {
      final act = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  h.title.isEmpty ? '未命名习惯' : h.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('完成打卡'),
                onTap: () => Navigator.pop(ctx, 'done'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: AppTheme.danger),
                title: const Text('标记失败'),
                onTap: () => Navigator.pop(ctx, 'fail'),
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清除今日记录'),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (act == 'done') {
        await notifier.checkin(h.id, today, amount: 1);
      } else if (act == 'fail') {
        await notifier.failCheckin(h.id, today);
      } else if (act == 'clear') {
        await notifier.uncheckin(h.id, today);
      }
      return;
    }

    // 「定量 / 时长」目标：弹窗输入本次数值（数量 / 分钟）
    final unit = target == HabitDailyTarget.minutes ? '分钟' : '次 / 量';
    final inputCtrl = TextEditingController();
    final act = await showModalBottomSheet<String>(
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
                h.title.isEmpty ? '未命名习惯' : h.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '当天目标：累计 ${targetValue} $unit',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '本次打卡 $unit',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'fail'),
                      child: const Text('标记失败'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'done'),
                      child: const Text('确认打卡'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'done') {
      final amount = int.tryParse(inputCtrl.text.trim()) ?? 1;
      await notifier.checkin(h.id, today, amount: amount <= 0 ? 1 : amount);
    } else if (act == 'fail') {
      await notifier.failCheckin(h.id, today);
    }
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: AppTheme.primary),
      ),
    );
  }
}
