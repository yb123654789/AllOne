import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import 'habit_models.dart';

/// 习惯列表 Notifier
class HabitListNotifier extends AsyncNotifier<List<Habit>> {
  static const _dir = 'habit/habits';

  @override
  Future<List<Habit>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <Habit>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(Habit.fromJson(json));
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> saveHabit(Habit h) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${h.id}.json', h.toJson());
    ref.invalidateSelf();
  }

  /// 读单个习惯 —— **从磁盘读**，不依赖内存列表。
  ///
  /// 自动归档是在 build 期间被调用的，此时列表可能还没加载完；
  /// 用 `state.valueOrNull ?? []` 会静默什么都不做（归档失效），
  /// 而用旧快照又可能把更新的字段覆盖掉。
  Future<Habit?> _habitFromDisk(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read('$_dir/$id.json');
    return json == null ? null : Habit.fromJson(json);
  }

  /// 把某个习惯移入回收站（archived=true）
  Future<void> archiveHabit(String id) async {
    final h = await _habitFromDisk(id);
    if (h == null || h.archived) return;
    await saveHabit(h.copyWith(archived: true, updatedAt: DateTime.now()));
  }

  /// 把某个习惯从回收站恢复（archived=false）
  Future<void> restoreHabit(String id) async {
    final h = await _habitFromDisk(id);
    if (h == null || !h.archived) return;
    await saveHabit(h.copyWith(archived: false, updatedAt: DateTime.now()));
  }

  Future<void> deleteHabit(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    await store.delete('habit/checkins/$id.json');
    // 修改记录（审计日志）也一并删除
    await store.delete('habit/logs/$id.json');
    // 清理该习惯的附件目录，避免残留孤立附件
    await store.deleteDirectory(habitMediaDir(id));
    ref.invalidateSelf();
  }
}

/// 打卡记录 Notifier：按习惯存储 {date: count}
///
/// ⚠️ **写操作一律从磁盘读最新值**，不要读 `state.valueOrNull`：
/// 写完之后会 `invalidateSelf()`，而 rebuild 完成之前 `state` 仍是**旧快照**
/// （甚至是空表）。连续两次打卡（连点两下）就会出现
/// 「第二次覆盖掉第一次」的数据丢失；数据尚未加载完时更会把
/// **该习惯的全部历史打卡覆盖成只剩今天这一条**。
/// 从磁盘读同时消除这两个问题。
class HabitCheckinNotifier extends AsyncNotifier<Map<String, CheckinMap>> {
  static const _dir = 'habit/checkins';

  @override
  Future<Map<String, CheckinMap>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final map = <String, CheckinMap>{};
    for (final f in files) {
      final id = f.replaceAll('.json', '');
      final json = await store.read('$_dir/$f');
      if (json != null) map[id] = CheckinMap.fromJson(json);
    }
    return map;
  }

  /// 磁盘上该习惯的最新打卡表（不存在则空）
  Future<CheckinMap> _mapOf(String habitId) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read('$_dir/$habitId.json');
    return json == null ? const CheckinMap() : CheckinMap.fromJson(json);
  }

  Future<void> _write(String habitId, CheckinMap updated) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/$habitId.json', updated.toJson());
    ref.invalidateSelf();
  }

  /// 打卡：本次累加 [amount]（数量 / 分钟）。当天目标为「一次即完成」时用 1。
  Future<void> checkin(String habitId, String date, {int amount = 1}) async {
    final current = await _mapOf(habitId);
    final entries = Map<String, int>.from(current.entries);
    // 若某天已被标记为失败，重新打卡时清零失败标记
    final base = (entries[date] ?? 0) < 0 ? 0 : (entries[date] ?? 0);
    entries[date] = base + (amount <= 0 ? 1 : amount);
    await _write(habitId, CheckinMap(entries: entries));
  }

  /// 标记某天为「失败 / 未完成」（存入 -1）
  Future<void> failCheckin(String habitId, String date) async {
    final current = await _mapOf(habitId);
    final entries = Map<String, int>.from(current.entries);
    entries[date] = -1;
    await _write(habitId, CheckinMap(entries: entries));
  }

  Future<void> uncheckin(String habitId, String date) async {
    final current = await _mapOf(habitId);
    final entries = Map<String, int>.from(current.entries);
    entries.remove(date);
    await _write(habitId, CheckinMap(entries: entries));
  }

  /// 批量修改历史记录（仅由热力图里的**手动操作**调用）：
  /// 改写打卡文件，并追加一条审计日志（原因必填，由界面校验）。
  ///
  /// 返回本次实际改动的天数（本来就已是目标状态的天数不计入，也不留日志）。
  Future<int> applyEdit({
    required String habitId,
    required List<String> dates,
    required HabitEditAction action,
    required String reason,
    int amount = 1,
  }) async {
    if (dates.isEmpty) return 0;
    final current = await _mapOf(habitId);
    final entries = Map<String, int>.from(current.entries);
    final before = <String, int>{};
    final applied = <String>[];
    for (final d in dates) {
      if (d.length < 10) continue;
      final old = entries[d] ?? 0;
      // 已经就是要改成的样子：不写日志、不计数（避免留下无意义的记录）
      if (action == HabitEditAction.clear && old == 0) continue;
      if (action == HabitEditAction.markUndone && old < 0) continue;
      before[d] = old;
      applied.add(d);
      switch (action) {
        case HabitEditAction.checkin:
          final base = old < 0 ? 0 : old;
          entries[d] = base + (amount <= 0 ? 1 : amount);
        case HabitEditAction.markUndone:
          entries[d] = -1;
        case HabitEditAction.clear:
          entries.remove(d);
      }
    }
    if (applied.isEmpty) return 0;
    await _write(habitId, CheckinMap(entries: entries));
    applied.sort();
    final log = HabitEditLog(
      id: AppPaths.newId(),
      at: DateTime.now(),
      action: action,
      dates: applied,
      amount: action == HabitEditAction.checkin
          ? (amount <= 0 ? 1 : amount)
          : 0,
      before: before,
      reason: reason.trim(),
    );
    await ref.read(habitLogProvider.notifier).append(habitId, log);
    return applied.length;
  }
}

/// 修改记录（审计日志）Notifier：按习惯存一个数组，只追加。
///
/// 与打卡一样：写之前**从磁盘读**，避免用旧快照把已有日志覆盖掉。
class HabitLogNotifier extends AsyncNotifier<Map<String, List<HabitEditLog>>> {
  static const _dir = 'habit/logs';

  @override
  Future<Map<String, List<HabitEditLog>>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final map = <String, List<HabitEditLog>>{};
    for (final f in files) {
      final id = f.replaceAll('.json', '');
      final list = await store.readList('$_dir/$f');
      map[id] = list.map(HabitEditLog.fromJson).toList();
    }
    return map;
  }

  /// 磁盘上该习惯的最新日志列表
  Future<List<HabitEditLog>> logsOf(String habitId) async {
    final store = await ref.read(jsonStoreProvider.future);
    final list = await store.readList('$_dir/$habitId.json');
    return list.map(HabitEditLog.fromJson).toList();
  }

  /// 追加一条日志（新的在后）
  Future<void> append(String habitId, HabitEditLog log) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = await logsOf(habitId);
    final all = [...current, log];
    await store.writeList(
      '$_dir/$habitId.json',
      all.map((e) => e.toJson()).toList(),
    );
    ref.invalidateSelf();
  }
}

final habitListProvider = AsyncNotifierProvider<HabitListNotifier, List<Habit>>(
  HabitListNotifier.new,
);
final habitCheckinProvider =
    AsyncNotifierProvider<HabitCheckinNotifier, Map<String, CheckinMap>>(
      HabitCheckinNotifier.new,
    );
final habitLogProvider =
    AsyncNotifierProvider<
      HabitLogNotifier,
      Map<String, List<HabitEditLog>>
    >(HabitLogNotifier.new);

/// 习惯附件目录
String habitMediaDir(String habitId) => 'habit/habits/$habitId/media';
