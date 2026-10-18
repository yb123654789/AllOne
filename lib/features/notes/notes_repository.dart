import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import 'notes_logic.dart';
import 'notes_models.dart';

/// 笔记主题的存储目录（一个主题一个 JSON 文件）
const String kNoteTopicsDir = 'notes/topics';

/// 笔记分组的存储目录
const String kNoteGroupsDir = 'notes/groups';

/// 某主题的记录目录
String noteEntriesDir(String topicId) => '$kNoteTopicsDir/$topicId/entries';

/// 某条记录的附件目录
String noteMediaDir(String topicId, String entryId) =>
    '${noteEntriesDir(topicId)}/$entryId/media';

/// 某主题的元数据文件
String noteTopicFile(String topicId) => '$kNoteTopicsDir/$topicId.json';

// ————————————————————————————————————————————————————————————
// 分组
// ————————————————————————————————————————————————————————————

/// 笔记分组列表：新增 / 改名 / 换色 / 删除。
class NoteGroupListNotifier extends AsyncNotifier<List<NoteGroup>> {
  @override
  Future<List<NoteGroup>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(kNoteGroupsDir);
    final list = <NoteGroup>[];
    for (final f in files) {
      final json = await store.read('$kNoteGroupsDir/$f');
      if (json != null) list.add(NoteGroup.fromJson(json));
    }
    // 手工排序号优先，其次名称（保持稳定，不随更新时间跳动）
    list.sort((a, b) {
      final c = a.order.compareTo(b.order);
      if (c != 0) return c;
      final n = a.name.compareTo(b.name);
      if (n != 0) return n;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Future<void> save(NoteGroup group) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$kNoteGroupsDir/${group.id}.json', group.toJson());
    ref.invalidateSelf();
  }

  /// 删除分组：组内主题不会被删，只是从这个分组里移出（数据安全优先）
  Future<void> delete(String groupId) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$kNoteGroupsDir/$groupId.json');
    // 把该分组从所有主题的归属里移除（主题本身保留）
    final files = await store.listFiles(kNoteTopicsDir);
    for (final f in files) {
      final json = await store.read('$kNoteTopicsDir/$f');
      if (json == null) continue;
      final topic = NoteTopic.fromJson(json);
      if (!topic.groupIds.contains(groupId)) continue;
      await store.write('$kNoteTopicsDir/$f', topic.withoutGroup(groupId).toJson());
    }
    ref.invalidateSelf();
    ref.invalidate(noteTopicListProvider);
  }
}

// ————————————————————————————————————————————————————————————
// 主题
// ————————————————————————————————————————————————————————————

/// 笔记主题列表（含回收站里的主题，界面按 [NoteTopic.inTrash] 过滤）。
class NoteTopicListNotifier extends AsyncNotifier<List<NoteTopic>> {
  @override
  Future<List<NoteTopic>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(kNoteTopicsDir);
    final list = <NoteTopic>[];
    for (final f in files) {
      final json = await store.read('$kNoteTopicsDir/$f');
      if (json != null) list.add(NoteTopic.fromJson(json));
    }
    return sortTopics(list);
  }

  /// 保存主题（新建或编辑）
  Future<void> save(NoteTopic topic) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write(noteTopicFile(topic.id), topic.toJson());
    ref.invalidateSelf();
  }

  Future<void> setPinned(String id, bool pinned) =>
      _mutate(id, (t) => t.copyWith(pinned: pinned, updatedAt: DateTime.now()));

  Future<void> setArchived(String id, bool archived) => _mutate(
    id,
    (t) => t.copyWith(archived: archived, updatedAt: DateTime.now()),
  );

  /// 移动到回收站（软删除：记录与附件全部保留）
  Future<void> moveToTrash(String id) =>
      _mutate(id, (t) => t.copyWith(deletedAt: DateTime.now()));

  /// 从回收站恢复
  Future<void> restore(String id) =>
      _mutate(id, (t) => t.copyWith(clearDeletedAt: true));

  /// 彻底删除：主题 JSON + 全部记录 + 附件目录一并删除，不可恢复
  Future<void> purge(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete(noteTopicFile(id));
    await store.deleteDirectory('$kNoteTopicsDir/$id');
    ref.invalidateSelf();
    ref.invalidate(noteEntryListProvider(id));
    ref.invalidate(noteTopicStatsProvider(id));
  }

  /// 清空回收站：[before] 为空则全部删除，否则只删该时间之前进的回收站
  Future<int> purgeTrash({DateTime? before}) async {
    final all = await future;
    final targets = all
        .where((t) => t.inTrash)
        .where((t) => before == null || t.deletedAt!.isBefore(before))
        .toList();
    for (final t in targets) {
      await purge(t.id);
    }
    return targets.length;
  }

  /// 记录写入后刷新主题的「最近记录时间」（列表排序依据）
  Future<void> touch(String id) =>
      _mutate(id, (t) => t.copyWith(updatedAt: DateTime.now()));

  Future<void> _mutate(
    String id,
    NoteTopic Function(NoteTopic topic) change,
  ) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read(noteTopicFile(id));
    if (json == null) return;
    final topic = NoteTopic.fromJson(json);
    await store.write(
      noteTopicFile(id),
      change(topic).toJson(),
    );
    ref.invalidateSelf();
  }
}

// ————————————————————————————————————————————————————————————
// 记录
// ————————————————————————————————————————————————————————————

/// 某个主题下的记录列表（family：按主题 id 取）。
class NoteEntryListNotifier extends FamilyAsyncNotifier<List<NoteEntry>, String> {
  String get _topicId => arg;

  @override
  Future<List<NoteEntry>> build(String topicId) async {
    final store = await ref.watch(jsonStoreProvider.future);
    final dir = noteEntriesDir(topicId);
    final files = await store.listFiles(dir);
    final list = <NoteEntry>[];
    for (final f in files) {
      final json = await store.read('$dir/$f');
      if (json == null) continue;
      final e = NoteEntry.fromJson(json);
      // 容错：老数据 / 手改数据可能缺 topicId，按目录归属补齐
      list.add(e.topicId == topicId ? e : e.copyWithTopic(topicId));
    }
    return sortEntriesDesc(list);
  }

  /// 保存一条记录（新增或编辑）
  Future<void> save(NoteEntry entry) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write(
      '${noteEntriesDir(_topicId)}/${entry.id}.json',
      entry.toJson(),
    );
    // 主题的「最近记录」时间跟着更新，列表排序才是「最近记过的在前」
    await ref.read(noteTopicListProvider.notifier).touch(_topicId);
    ref.invalidateSelf();
    ref.invalidate(noteTopicStatsProvider(_topicId));
    ref.invalidate(noteTopicListProvider);
  }

  /// 删除一条记录（连同它的附件目录，避免留下孤立附件）
  Future<void> delete(String entryId) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('${noteEntriesDir(_topicId)}/$entryId.json');
    await store.deleteDirectory(noteMediaDir(_topicId, entryId));
    ref.invalidateSelf();
    ref.invalidate(noteTopicStatsProvider(_topicId));
  }
}

// ————————————————————————————————————————————————————————————
// Provider
// ————————————————————————————————————————————————————————————

final noteGroupListProvider =
    AsyncNotifierProvider<NoteGroupListNotifier, List<NoteGroup>>(
      NoteGroupListNotifier.new,
    );

final noteTopicListProvider =
    AsyncNotifierProvider<NoteTopicListNotifier, List<NoteTopic>>(
      NoteTopicListNotifier.new,
    );

final noteEntryListProvider =
    AsyncNotifierProvider.family<NoteEntryListNotifier, List<NoteEntry>, String>(
      NoteEntryListNotifier.new,
    );

/// 单个主题的统计（列表页每张卡片上那一行摘要）。
///
/// 直接读磁盘而不是依赖已加载的列表：列表页只需要「条数 / 跨度 / 上次」，
/// 不值得把每个主题的全部记录都载入内存。
final noteTopicStatsProvider = FutureProvider.family<NoteTopicStats, String>((
  ref,
  topicId,
) async {
  final store = await ref.watch(jsonStoreProvider.future);
  final dir = noteEntriesDir(topicId);
  final files = await store.listFiles(dir);
  final entries = <NoteEntry>[];
  for (final f in files) {
    final json = await store.read('$dir/$f');
    if (json != null) entries.add(NoteEntry.fromJson(json));
  }
  return NoteTopicStats.of(entries);
});

// ————————————————————————————————————————————————————————————
// 从日记转存
// ————————————————————————————————————————————————————————————

/// 转存日记时携带的数据（由日记模块提供，本模块不反向依赖日记的内部实现）。
class DiaryTransferPayload {
  final String title;
  final String text;
  final List<String> tags;
  final DateTime occurredAt;

  /// 日记的附件列表
  final List<MediaAttachment> media;

  /// 日记附件所在目录（相对 AllOneData；null = 无附件目录）
  final String? mediaDirRelative;

  const DiaryTransferPayload({
    required this.title,
    required this.text,
    required this.occurredAt,
    this.tags = const [],
    this.media = const [],
    this.mediaDirRelative,
  });
}

/// 把一篇日记转存为某主题下的一条记录：正文 / 标签 / 时间照搬，
/// 附件**复制**一份到笔记目录（日记那边保持原样，删除日记不影响笔记）。
///
/// 返回新建的记录；附件复制失败时该附件被跳过（不阻断整条转存）。
Future<NoteEntry> createEntryFromDiary({
  required WidgetRef ref,
  required String topicId,
  required DiaryTransferPayload payload,
}) async {
  final store = await ref.read(jsonStoreProvider.future);
  final entryId = AppPaths.newId();
  final now = DateTime.now();

  final copied = <MediaAttachment>[];
  if (payload.mediaDirRelative != null && payload.media.isNotEmpty) {
    final srcDir = Directory(
      p.join(store.root.path, payload.mediaDirRelative!),
    );
    final destDir = Directory(
      p.join(store.root.path, noteMediaDir(topicId, entryId)),
    );
    await destDir.create(recursive: true);
    for (final m in payload.media) {
      // 外链附件（大视频）不复制，原样带过去
      if (m.file == null || m.file!.isEmpty) {
        copied.add(m);
        continue;
      }
      final src = File(p.join(srcDir.path, m.file!));
      if (!await src.exists()) {
        copied.add(m);
        continue;
      }
      var name = m.file!;
      if (await File(p.join(destDir.path, name)).exists()) {
        name = '${DateTime.now().millisecondsSinceEpoch}_$name';
      }
      try {
        await src.copy(p.join(destDir.path, name));
        copied.add(
          MediaAttachment(type: m.type, file: name, size: m.size, note: m.note),
        );
      } catch (_) {
        // 单个附件复制失败不影响正文转存
        copied.add(m);
      }
    }
  } else {
    copied.addAll(payload.media);
  }

  final entry = NoteEntry(
    id: entryId,
    topicId: topicId,
    title: payload.title,
    plainText: payload.text,
    occurredAt: payload.occurredAt,
    createdAt: now,
    updatedAt: now,
    tags: List.of(payload.tags),
    media: copied,
  );
  await ref.read(noteEntryListProvider(topicId).notifier).save(entry);
  return entry;
}
