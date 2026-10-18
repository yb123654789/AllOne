import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import '../../core/widgets/heat_map.dart';
import 'habit_log_page.dart';
import 'habit_models.dart';
import 'habit_progress.dart';
import 'habit_repository.dart';

/// 习惯详情页：近一年热力图 + 统计 + **手动批量修改历史记录**。
///
/// 为什么要有这一页：卡片上的小热力图只看趋势，而
/// 「忘打卡的日子事后补上」「把某天标成没完成」这类操作需要
/// 明确的手动动作 + 原因留档（见 [HabitEditLog]）。
class HabitDetailPage extends ConsumerStatefulWidget {
  final String habitId;

  const HabitDetailPage({super.key, required this.habitId});

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  /// 热力图里选中的日期（多选，批量修改用）
  final Set<String> _selected = {};

  static const _weeksInYear = 53;

  /// 热力图实际铺多少周：**从习惯创建那一周算起**（最多一年）。
  ///
  /// 之前固定铺满 53 周：习惯刚建几周时，左边几十周全是「习惯还不存在」的
  /// 灰格子，手机一屏几乎看不到一个彩色格 —— 观感就是「热力图没有颜色」。
  int _weeksFor(Habit h) {
    final c = DateTime(h.createdAt.year, h.createdAt.month, h.createdAt.day);
    final n = DateTime.now();
    final days = DateTime(n.year, n.month, n.day).difference(c).inDays;
    if (days < 0) return 1;
    return ((days ~/ 7) + 1).clamp(1, _weeksInYear);
  }

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitListProvider).valueOrNull;
    final checkins = ref.watch(habitCheckinProvider).valueOrNull;
    if (habits == null || checkins == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    Habit? habit;
    for (final h in habits) {
      if (h.id == widget.habitId) habit = h;
    }
    if (habit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('习惯详情')),
        body: const Center(child: Text('习惯不存在或已删除')),
      );
    }
    final h = habit;
    final cm = checkins[h.id] ?? const CheckinMap();
    final today = AppTime.dateOnly(DateTime.now());
    final weeks = _weeksFor(h);
    // 近一年（含今天）
    final start = AppTime.dateOnly(
      DateTime.now().subtract(const Duration(days: 364)),
    );
    final stats = HabitProgress.summarize(
      h,
      cm,
      start: start,
      end: today,
      today: today,
    );
    final (dailyP, dailyText) = HabitProgress.dailyProgress(h, cm, today);

    return Scaffold(
      appBar: AppBar(
        title: Text(h.title.isEmpty ? '未命名习惯' : h.title),
        actions: [
          IconButton(
            tooltip: '修改记录',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HabitLogPage(habitId: h.id, title: h.title),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty ? null : _actionBar(h, today),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _todayCard(h, cm, today, dailyP, dailyText, stats),
          const SizedBox(height: 12),
          _statsCard(stats, cm, today),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '打卡热力图（创建至今 · 最多一年）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _selected.isEmpty ? '点格子可多选 → 补打卡' : '再点一次可取消选择',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          HeatMap(
            cells: HabitProgress.heatCells(
              h,
              cm,
              today: today,
              weeks: weeks,
            ),
            weeks: weeks,
            anchorDate: today,
            cellSize: 20,
            gap: 3,
            selected: _selected,
            scrollable: true,
            showWeekdayLabels: true,
            weekHeaders: _weekHeaders(h, cm, today, weeks),
            onTapDay: (d) => _toggle(d, today),
          ),
          const SizedBox(height: 10),
          _legend(),
        ],
      ),
    );
  }

  // ── 今天 / 统计 ─────────────────────────────────────────────────────────

  Widget _todayCard(
    Habit h,
    CheckinMap cm,
    String today,
    double progress,
    String text,
    HabitStats stats,
  ) {
    final status = HabitProgress.dayStatus(h, cm, today, today: today);
    final color = HabitProgress.colorOf(status);
    final streak = cm.streakDays(
      DateTime.now(),
      isMet: (d) => cm.dayMet(d, h.dailyTarget, h.dailyTargetValue),
    );
    final (weekCount, weekTarget) = HabitProgress.weeklyProgress(h, cm, today);
    // 坚持周期进度（与列表摘要共用同一套算法）
    final (doneDays, doneTotal) = HabitProgress.doneCounts(h, cm);
    final (persistP, persistText) = HabitProgress.persistenceProgress(
      h,
      doneDays,
      doneTotal,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  HabitProgress.labelOf(status),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppTheme.divider,
                color: color,
              ),
            ),
            // 坚持周期进度（「不限」周期的习惯没有这一条）
            if (persistText != '不限') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: persistP,
                        minHeight: 5,
                        backgroundColor: AppTheme.divider,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    persistText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _kv('连续', '$streak 天'),
                if (h.frequency == HabitFrequency.weeklyTimes)
                  _kv('本周', '$weekCount/$weekTarget 次'),
                _kv('达标率', '${(stats.metRate * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$k ',
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      Text(
        v,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ],
  );

  Widget _statsCard(HabitStats s, CheckinMap cm, String today) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '近一年统计',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCell('已完成', s.met, HabitDayStatus.met),
                _statCell('未完全完成', s.partial, HabitDayStatus.partial),
                _statCell('漏打卡', s.missed, HabitDayStatus.missed),
                _statCell('标记未完成', s.markedUndone, HabitDayStatus.markedUndone),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '该打卡 ${s.scheduled} 天 · 累计打卡 ${cm.totalDays} 天 / ${cm.totalCount} 次',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, int value, HabitDayStatus status) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: HabitProgress.colorOf(status),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    ),
  );

  Widget _legend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final s in [
          HabitDayStatus.met,
          HabitDayStatus.partial,
          HabitDayStatus.missed,
          HabitDayStatus.markedUndone,
          HabitDayStatus.off,
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: HabitProgress.colorOf(s),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                HabitProgress.labelOf(s),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── 热力图数据 ──────────────────────────────────────────────────────────

  /// 周行头：仅「每周 N 次」需要（其它频率没有周目标）
  Map<String, String> _weekHeaders(
    Habit h,
    CheckinMap cm,
    String today,
    int weeks,
  ) {
    if (h.frequency != HabitFrequency.weeklyTimes) return const {};
    final target = h.weeklyTimes <= 0 ? 1 : h.weeklyTimes;
    final anchor = DateTime.tryParse(today) ?? DateTime.now();
    final lastMonday = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: anchor.weekday - 1));
    final out = <String, String>{};
    for (var i = 0; i < weeks; i++) {
      final ws = AppTime.dateOnly(
        lastMonday.subtract(Duration(days: 7 * i)),
      );
      final c = HabitProgress.weekCount(h, cm, ws);
      if (c <= 0) continue;
      out[ws] = c >= target ? '✓' : '$c/$target';
    }
    return out;
  }

  // ── 选择与批量修改 ──────────────────────────────────────────────────────

  void _toggle(String date, String today) {
    if (date.compareTo(today) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未来的日子不能修改')),
      );
      return;
    }
    setState(() {
      if (!_selected.remove(date)) _selected.add(date);
    });
  }

  Widget _actionBar(Habit h, String today) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: const Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已选 ${_selected.length} 天',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清除选择'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => _showEditSheet(h, today),
              child: const Text('修改选中'),
            ),
          ],
        ),
      ),
    );
  }

  /// 批量修改弹窗：动作 + 数值 + **必填原因**
  Future<void> _showEditSheet(Habit h, String today) async {
    final dates = _selected.toList()..sort();
    var action = HabitEditAction.checkin;
    final amountCtrl = TextEditingController(
      text: h.dailyTarget == HabitDailyTarget.once ? '1' : '1',
    );
    final reasonCtrl = TextEditingController();
    String? error;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final unit = h.dailyTarget == HabitDailyTarget.minutes ? '分钟' : '次';
          return SafeArea(
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
                    '修改 ${dates.length} 天的记录',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dates.length > 4
                        ? '${dates.take(3).join('、')} 等 ${dates.length} 天'
                        : dates.join('、'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<HabitEditAction>(
                    segments: const [
                      ButtonSegment(
                        value: HabitEditAction.checkin,
                        label: Text('补打卡'),
                      ),
                      ButtonSegment(
                        value: HabitEditAction.markUndone,
                        label: Text('未完成'),
                      ),
                      ButtonSegment(
                        value: HabitEditAction.clear,
                        label: Text('清除'),
                      ),
                    ],
                    selected: {action},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setSheetState(() => action = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (action == HabitEditAction.checkin)
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '每天补记多少$unit（默认 1）',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: '原因（必填）',
                      hintText: '如：那几天做了但忘了打卡',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) setSheetState(() => error = null);
                    },
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '修改会写入「修改记录」，可随时回看。',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (reasonCtrl.text.trim().isEmpty) {
                              setSheetState(() => error = '请填写原因');
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('确认修改'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok != true) return;
    final n = await ref
        .read(habitCheckinProvider.notifier)
        .applyEdit(
          habitId: h.id,
          dates: dates,
          action: action,
          reason: reasonCtrl.text,
          amount: int.tryParse(amountCtrl.text.trim()) ?? 1,
        );
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 0 ? '这些天本来就是该状态，没有改动' : '已修改 $n 天，并记录了原因',
        ),
      ),
    );
  }
}
