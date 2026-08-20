import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'calendar_models.dart';

/// 特殊日子列表 Notifier
class SpecialDayListNotifier extends AsyncNotifier<List<SpecialDay>> {
  static const _path = 'calendar/special_days.json';

  @override
  Future<List<SpecialDay>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    final list = (json?['specialDays'] as List?)
            ?.map((e) => SpecialDay.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <SpecialDay>[];
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  Future<void> save(SpecialDay d) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull ?? [];
    final updated = [
      ...current.where((e) => e.id != d.id),
      d,
    ]..sort((a, b) => a.date.compareTo(b.date));
    await store.write(_path, {'specialDays': updated.map((e) => e.toJson()).toList()});
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull ?? [];
    final updated = current.where((e) => e.id != id).toList();
    await store.write(_path, {'specialDays': updated.map((e) => e.toJson()).toList()});
    ref.invalidateSelf();
  }
}

final specialDayListProvider = AsyncNotifierProvider<SpecialDayListNotifier, List<SpecialDay>>(
    SpecialDayListNotifier.new);
