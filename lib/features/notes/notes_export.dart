import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 笔记导出为 Markdown（通用文本，任何编辑器都能打开）。
///
/// 之所以单个主题也能导出：长期积累的笔记常常要发给别人 / 归档到别处，
/// 一份完整的 .md 比截图和复制粘贴靠谱。
class NotesExporter {
  NotesExporter._();

  /// 导出单个主题并唤出分享
  static Future<void> exportTopic(
    WidgetRef ref, {
    required NoteTopic topic,
    String? groupName,
  }) async {
    final entries = await ref.read(noteEntryListProvider(topic.id).future);
    final md = topicToMarkdown(
      topic: topic,
      groupName: groupName,
      entries: entries,
    );
    await _share(md, _fileBase(topic.title), text: '笔记导出：${_title(topic)}');
  }

  /// 导出全部主题（一个文件，按主题分段）
  static Future<void> exportAll(WidgetRef ref) async {
    final topics = (ref.read(noteTopicListProvider).valueOrNull ?? [])
        .where((t) => !t.inTrash)
        .toList();
    if (topics.isEmpty) {
      throw StateError('还没有可导出的笔记');
    }
    final groups = ref.read(noteGroupListProvider).valueOrNull ?? const <NoteGroup>[];
    final groupNames = {for (final g in groups) g.id: g.name};
    final entriesByTopic = <String, List<NoteEntry>>{};
    for (final t in topics) {
      entriesByTopic[t.id] = await ref.read(noteEntryListProvider(t.id).future);
    }
    final md = notesToMarkdown(
      topics: topics,
      groupNames: groupNames,
      entriesByTopic: entriesByTopic,
    );
    await _share(md, '笔记总览', text: '笔记导出：全部主题');
  }

  static String _title(NoteTopic t) =>
      t.title.trim().isEmpty ? '未命名主题' : t.title.trim();

  /// 文件名去掉 Windows / Android 不允许的字符
  static String _fileBase(String title) {
    final t = title.trim().isEmpty ? '笔记' : title.trim();
    final safe = t.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_');
    return safe.length > 40 ? safe.substring(0, 40) : safe;
  }

  static Future<void> _share(
    String content,
    String baseName, {
    String? text,
  }) async {
    final tmp = await getTemporaryDirectory();
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}';
    final file = File(p.join(tmp.path, '${baseName}_$stamp.md'));
    await file.writeAsString(content, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: text ?? 'AllOne 笔记导出（Markdown）');
  }
}
