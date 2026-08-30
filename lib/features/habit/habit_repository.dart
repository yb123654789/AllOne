import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// 把某个习惯移入回收站（archived=true）
  Future<void> archiveHabit(String id) async {
    final list = state.valueOrNull ?? [];
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    await saveHabit(
      list[idx].copyWith(archived: true, updatedAt: DateTime.now()),
    );
  }

  /// 把某个习惯从回收站恢复（archived=false）
  Future<void> restoreHabit(String id) async {
    final list = state.valueOrNull ?? [];
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    await saveHabit(
      list[idx].copyWith(archived: false, updatedAt: DateTime.now()),
    );
  }

  Future<void> deleteHabit(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    await store.delete('habit/checkins/$id.json');
    ref.invalidateSelf();
  }
}

/// 打卡记录 Notifier：按习惯存储 {date: count}
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

  /// 打卡：本次累加 [amount]（数量 / 分钟）。当天目标为「一次即完成」时用 1。
  Future<void> checkin(
    String habitId,
    String date, {
    int amount = 1,
  }) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull?[habitId] ?? const CheckinMap();
    final entries = Map<String, int>.from(current.entries);
    // 若某天已被标记为失败，重新打卡时清零失败标记
    final base = (entries[date] ?? 0) < 0 ? 0 : (entries[date] ?? 0);
    entries[date] = base + (amount <= 0 ? 1 : amount);
    final updated = CheckinMap(entries: entries);
    await store.write('$_dir/$habitId.json', updated.toJson());
    ref.invalidateSelf();
  }

  /// 标记某天为「失败」（存入 -1）
  Future<void> failCheckin(String habitId, String date) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull?[habitId] ?? const CheckinMap();
    final entries = Map<String, int>.from(current.entries);
    entries[date] = -1;
    final updated = CheckinMap(entries: entries);
    await store.write('$_dir/$habitId.json', updated.toJson());
    ref.invalidateSelf();
  }

  Future<void> uncheckin(String habitId, String date) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull?[habitId] ?? const CheckinMap();
    final entries = Map<String, int>.from(current.entries);
    entries.remove(date);
    final updated = CheckinMap(entries: entries);
    await store.write('$_dir/$habitId.json', updated.toJson());
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

/// 习惯附件目录
String habitMediaDir(String habitId) => 'habit/habits/$habitId/media';
