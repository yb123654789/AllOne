import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
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
    list.sort((a, b) {
      if (a.weekday != b.weekday) return a.weekday - b.weekday;
      return a.startTime.compareTo(b.startTime);
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
final courseListProvider =
    AsyncNotifierProvider<CourseListNotifier, List<Course>>(
      CourseListNotifier.new,
    );
