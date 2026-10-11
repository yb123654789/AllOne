import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/storage_providers.dart';
import 'calendar_models.dart';
import 'holiday_data.dart';
import 'special_day_lifecycle.dart';

/// 特殊日子列表 Notifier
class SpecialDayListNotifier extends AsyncNotifier<List<SpecialDay>> {
  static const _path = 'calendar/special_days.json';

  @override
  Future<List<SpecialDay>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    final list =
        (json?['specialDays'] as List?)
            ?.map((e) => SpecialDay.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <SpecialDay>[];
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// 取当前列表；**尚未加载完成则先等待加载**。
  ///
  /// 这个方法是防「整表被清空」的关键：[_writeAll] 会重写整个
  /// `special_days.json`。若这里退化成 `state.valueOrNull ?? []`，
  /// 那么只要在数据还没加载好时触发一次写操作（例如刚打开 App 就点了保存），
  /// 就会把磁盘上**所有**特殊日子覆盖成空列表。
  Future<List<SpecialDay>> _listOrLoad() async {
    final current = state.valueOrNull;
    if (current != null) return current;
    return await ref.read(specialDayListProvider.future);
  }

  /// 整表写回（按日期排序，磁盘格式保持稳定）
  Future<void> _writeAll(List<SpecialDay> list) async {
    final store = await ref.read(jsonStoreProvider.future);
    final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
    await store.write(_path, {
      'specialDays': sorted.map((e) => e.toJson()).toList(),
    });
    ref.invalidateSelf();
  }

  Future<void> save(SpecialDay d) async {
    final current = await _listOrLoad();
    await _writeAll([...current.where((e) => e.id != d.id), d]);
  }

  /// 彻底删除（仅用于回收站里的「彻底删除」）
  Future<void> delete(String id) async {
    final current = await _listOrLoad();
    await _writeAll(SpecialDayLifecycle.remove(current, id));
  }

  /// 把过期单次项移入回收站，返回归档条数
  Future<int> archiveExpired(List<String> ids, {String? today}) async {
    if (ids.isEmpty) return 0;
    final current = await _listOrLoad();
    final t = today ?? AppTime.dateOnly(DateTime.now());
    await _writeAll(SpecialDayLifecycle.archive(current, ids, t));
    return ids.length;
  }

  /// 从回收站恢复
  Future<void> restore(String id) async {
    final current = await _listOrLoad();
    await _writeAll(SpecialDayLifecycle.restore(current, id));
  }

  /// 清空回收站（彻底删除全部已归档项），返回删除条数
  Future<int> purgeAll() async {
    final current = await _listOrLoad();
    final trashed = SpecialDayLifecycle.trashed(current);
    if (trashed.isEmpty) return 0;
    await _writeAll(
      SpecialDayLifecycle.removeAll(current, trashed.map((e) => e.id)),
    );
    return trashed.length;
  }

  /// 每年重复项推进到「下一次」（启动时 / 进入倒数日页时调用）。
  ///
  /// 无变化时不写盘。返回被推进的条数。
  Future<int> advanceRecurring({String? today}) async {
    final current = await _listOrLoad();
    final t = today ?? AppTime.dateOnly(DateTime.now());
    final next = SpecialDayLifecycle.advanceRecurring(current, t);
    if (!SpecialDayLifecycle.changed(current, next)) return 0;
    var count = 0;
    for (var i = 0; i < current.length; i++) {
      if (current[i].date != next[i].date) count++;
    }
    await _writeAll(next);
    return count;
  }

  /// 已过期、等待用户确认归档的单次项
  Future<List<SpecialDay>> pendingArchive({String? today}) async {
    final current = await _listOrLoad();
    final t = today ?? AppTime.dateOnly(DateTime.now());
    return SpecialDayLifecycle.expiredOneOffs(current, t);
  }
}

final specialDayListProvider =
    AsyncNotifierProvider<SpecialDayListNotifier, List<SpecialDay>>(
      SpecialDayListNotifier.new,
    );

/// 内置法定节假日 / 传统节日（按年份动态生成，不落盘）。
class HolidayListNotifier extends FamilyAsyncNotifier<List<SpecialDay>, int> {
  @override
  Future<List<SpecialDay>> build(int arg) async {
    return HolidayProvider.builtInHolidaysForYear(arg);
  }
}

final holidayListProvider =
    AsyncNotifierProvider.family<HolidayListNotifier, List<SpecialDay>, int>(
      HolidayListNotifier.new,
    );
