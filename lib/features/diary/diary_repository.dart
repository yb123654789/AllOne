import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
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
    // 清理整个附件目录（照片/录音/视频），避免残留孤立附件
    await store.deleteDirectory(diaryMediaDir(id));
    ref.invalidateSelf();
  }

  /// 批量导入日记（来自外部 txt / PDF）：**只新增，绝不覆盖或删除已有日记**。
  ///
  /// - 每篇都会写入全新文件；若 ID 与现有文件冲突则自动重新生成 ID；
  /// - [imagesOf] 可选：为某篇提供随附图片（PDF 里抽出的内嵌照片），
  ///   会写入 `diary/entries/<id>/media/` 并登记进该篇的 `media` 数组；
  /// - 中途某一篇写入失败不影响其它篇（异常向上抛出，由调用方提示）。
  /// - 返回成功写入的篇数。
  Future<int> importEntries(
    List<DiaryEntry> entries, {
    List<Uint8List> Function(DiaryEntry entry)? imagesOf,
  }) async {
    if (entries.isEmpty) return 0;
    final store = await ref.read(jsonStoreProvider.future);
    final used = (await store.listFiles(_dir)).toSet();
    var written = 0;
    for (final entry in entries) {
      var e = entry;
      var id = e.id;
      // ID 为空或与现有文件冲突时重新生成（加递增后缀，确保循环一定终止）
      var suffix = 0;
      while (id.isEmpty || used.contains('$id.json')) {
        id = suffix == 0 ? AppPaths.newId() : '${AppPaths.newId()}-$suffix';
        suffix++;
      }
      if (id != e.id) e = e.copyWith(id: id);
      used.add('$id.json');

      // 写入随附图片（PDF 内嵌照片），并登记到 media 数组
      final images = imagesOf?.call(entry) ?? const <Uint8List>[];
      if (images.isNotEmpty) {
        final media = <MediaAttachment>[...e.media];
        for (var i = 0; i < images.length; i++) {
          final bytes = images[i];
          // 文件名沿用项目既有约定：<毫秒>-<序号>.jpg
          final name = '${DateTime.now().millisecondsSinceEpoch}-$i.jpg';
          await store.writeBytes('${diaryMediaDir(id)}/$name', bytes);
          media.add(
            MediaAttachment(
              type: MediaType.photo,
              file: name,
              size: bytes.length,
            ),
          );
        }
        e = e.copyWith(media: media);
      }

      await store.write('$_dir/$id.json', e.toJson());
      written++;
    }
    if (written > 0) ref.invalidateSelf();
    return written;
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
