import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'habit_edit_page.dart';
import 'habit_models.dart';
import 'habit_repository.dart';

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
    final today = AppTime.dateOnly(DateTime.now());
    final filtered = habits
        .where((h) => _filterTags.every((t) => h.tags.contains(t)))
        .toList();
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
          _habitCard(context, ref, h, checkins, today),
      ],
    );
  }

  Widget _habitCard(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    Map<String, CheckinMap> checkins,
    String today,
  ) {
    final cm = checkins[h.id] ?? const CheckinMap();
    return _card(context, ref, h, cm, (cm.entries[today] ?? 0) > 0);
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

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    CheckinMap cm,
    bool doneToday,
  ) {
    final target = h.target.value;
    final current = h.target.type == HabitType.count
        ? cm.totalCount
        : cm.totalDays;
    final progress = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0);
    return Card(
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
                _checkinButton(context, ref, h, doneToday),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _tag(h.category),
                const SizedBox(width: 8),
                Text(
                  '${h.target.type == HabitType.count ? '次数' : '天数'} $current/$target',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '连续 ${cm.streakDays(DateTime.now())} 天',
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
                color: doneToday ? Colors.green : AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkinButton(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    bool doneToday,
  ) {
    return TextButton.icon(
      onPressed: () async {
        final today = AppTime.dateOnly(DateTime.now());
        final notifier = ref.read(habitCheckinProvider.notifier);
        if (doneToday) {
          await notifier.uncheckin(h.id, today);
        } else {
          await notifier.checkin(h.id, today);
        }
      },
      icon: Icon(
        doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
        color: doneToday ? Colors.green : AppTheme.primary,
        size: 20,
      ),
      label: Text(doneToday ? '已打卡' : '打卡'),
      style: TextButton.styleFrom(
        foregroundColor: doneToday ? Colors.green : AppTheme.primary,
      ),
    );
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
