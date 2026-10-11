import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'schedule_logic.dart';
import 'schedule_models.dart';

/// 学期列表 Notifier
class TermListNotifier extends AsyncNotifier<List<Term>> {
  static const _dir = 'schedule/terms';

  @override
  Future<List<Term>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <Term>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(Term.fromJson(json));
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  Future<void> saveTerm(Term t) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${t.id}.json', t.toJson());
    ref.invalidateSelf();
  }

  Future<void> deleteTerm(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }
}

/// 作息表 Notifier（节次 → 起止时间）。
///
/// 存 `schedule/sections.json`：没写过就用 [kDefaultSections]，
/// 所以旧用户第一次打开课程表也能立刻用节次排版。
class SectionListNotifier extends AsyncNotifier<List<SectionTime>> {
  static const _path = 'schedule/sections.json';

  @override
  Future<List<SectionTime>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    final raw = json?['sections'] as List?;
    if (raw == null) return kDefaultSections;
    final list =
        raw
            .whereType<Map<String, dynamic>>()
            .map(SectionTime.fromJson)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    return list.isEmpty ? kDefaultSections : list;
  }

  /// 整表保存（节次号会重排为 1..n）
  Future<void> saveAll(List<SectionTime> sections) async {
    final store = await ref.read(jsonStoreProvider.future);
    final sorted = [...sections]..sort((a, b) => a.index.compareTo(b.index));
    final normalized = [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(index: i + 1),
    ];
    await store.write(_path, {
      'sections': normalized.map((e) => e.toJson()).toList(),
    });
    ref.invalidateSelf();
  }

  Future<void> resetDefault() => saveAll(kDefaultSections);
}

/// 课程列表 Notifier
class CourseListNotifier extends AsyncNotifier<List<Course>> {
  static const _dir = 'schedule/courses';

  @override
  Future<List<Course>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <Course>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(Course.fromJson(json));
    }
    // 按第一个时段的「周几 + 起始节次」排序（多时段课程取最早的那个时段）
    list.sort((a, b) {
      final sa = a.sessions.isEmpty ? null : a.sessions.first;
      final sb = b.sessions.isEmpty ? null : b.sessions.first;
      final wa = sa?.weekday ?? 9;
      final wb = sb?.weekday ?? 9;
      if (wa != wb) return wa - wb;
      final oa = sa?.startSection ?? 99;
      final ob = sb?.startSection ?? 99;
      if (oa != ob) return oa - ob;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  Future<void> saveCourse(Course c) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${c.id}.json', c.toJson());
    ref.invalidateSelf();
  }

  Future<void> deleteCourse(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }
}

final termListProvider = AsyncNotifierProvider<TermListNotifier, List<Term>>(
  TermListNotifier.new,
);
final sectionListProvider =
    AsyncNotifierProvider<SectionListNotifier, List<SectionTime>>(
      SectionListNotifier.new,
    );
final courseListProvider =
    AsyncNotifierProvider<CourseListNotifier, List<Course>>(
      CourseListNotifier.new,
    );

/// 当前学期（今天落在区间内的那个；都不在则取最近开始的）
final currentTermProvider = Provider<Term?>((ref) {
  final terms = ref.watch(termListProvider).valueOrNull ?? const <Term>[];
  return ScheduleLogic.currentTerm(terms, DateTime.now());
});
