import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'diary_models.dart';

/// 日记条目列表的异步 Notifier：负责读写与刷新。
class DiaryListNotifier extends AsyncNotifier<List<DiaryEntry>> {
  static const _dir = 'diary/entries';

  @override
  Future<List<DiaryEntry>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <DiaryEntry>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(DiaryEntry.fromJson(json));
    }
    // 排序：置顶优先，再按创建时间倒序
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  /// 保存（新增或更新）日记
  Future<void> saveEntry(DiaryEntry entry) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${entry.id}.json', entry.toJson());
    ref.invalidateSelf();
  }

  /// 删除日记（含附件目录）
  Future<void> deleteEntry(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    // 清理附件目录（容错）
    await store.delete('$_dir/$id/media/.keep');
    ref.invalidateSelf();
  }
}

/// 日记模板列表 Notifier
class DiaryTemplateListNotifier extends AsyncNotifier<List<DiaryTemplate>> {
  static const _dir = 'diary/templates';

  @override
  Future<List<DiaryTemplate>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <DiaryTemplate>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(DiaryTemplate.fromJson(json));
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> save(DiaryTemplate t) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${t.id}.json', t.toJson());
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }
}

final diaryListProvider =
    AsyncNotifierProvider<DiaryListNotifier, List<DiaryEntry>>(
      DiaryListNotifier.new,
    );
final diaryTemplateListProvider =
    AsyncNotifierProvider<DiaryTemplateListNotifier, List<DiaryTemplate>>(
      DiaryTemplateListNotifier.new,
    );

/// 生成附件保存目录相对路径
String diaryMediaDir(String entryId) => 'diary/entries/$entryId/media';
