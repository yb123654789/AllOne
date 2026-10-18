/// 笔记模块的**纯逻辑**：统计、时间线分组、搜索、Markdown 导出。
///
/// 全部是不依赖 Flutter / 文件系统的纯函数，便于单元测试；
/// 界面层只负责把结果画出来。
library;

import 'notes_models.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 颜色字符串（#RRGGBB / #AARRGGBB）转 ARGB int；非法返回 null。
int? parseHexColor(String hex) {
  final s = hex.trim().replaceFirst('#', '');
  if (s.length != 6 && s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  // 6 位补满不透明
  return s.length == 6 ? 0xFF000000 | v : v;
}

/// 日期短文本：yyyy-MM-dd
String dateText(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 日期 + 时分：yyyy-MM-dd HH:mm
String dateTimeText(DateTime d) =>
    '${dateText(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// 时间线分组标题：2026 年 10 月
String monthLabel(DateTime d) => '${d.year} 年 ${d.month} 月';

/// 只保留年月，作为分组键（yyyy-MM），便于比较与排序
String monthKey(DateTime d) => '${d.year}-${_two(d.month)}';

/// 「上次记录多久前」：今天 / 昨天 / 12 天前 / 3 个月前 / 1 年前
///
/// 按**日历天**计算，不受时分影响（今天 23:59 与今天 00:01 都算「今天」）。
String relativeDaysText(DateTime? last, {DateTime? now}) {
  if (last == null) return '尚无记录';
  final today = now ?? DateTime.now();
  final a = DateTime(last.year, last.month, last.day);
  final b = DateTime(today.year, today.month, today.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 30) return '$days 天前';
  if (days < 365) return '${days ~/ 30} 个月前';
  return '${days ~/ 365} 年前';
}

/// 首个记录到最近记录的跨度文本：3 天 / 2 个月 / 1 年 2 个月
///
/// 按日历计算（不是简单的天数相除），跨 2 个月时显示「2 个月」而不是「61 天」。
String spanText(DateTime? first, DateTime? last) {
  if (first == null || last == null) return '';
  final f = DateTime(first.year, first.month, first.day);
  final l = DateTime(last.year, last.month, last.day);
  if (l.isBefore(f)) return spanText(last, first);
  final days = l.difference(f).inDays;
  if (days == 0) return '同一天';
  // 不足一个月：按天数（含首尾，显得符合直觉：1 号到 3 号 = 3 天）
  if (days < 31) return '${days + 1} 天';
  var months =
      (l.year - f.year) * 12 +
      (l.month - f.month) -
      (l.day < f.day ? 1 : 0);
  if (months < 12) return '${months < 1 ? 1 : months} 个月';
  final years = months ~/ 12;
  final rest = months % 12;
  return rest == 0 ? '$years 年' : '$years 年 $rest 个月';
}

/// 主题的统计信息（列表页一行摘要、主题页页头都用它）。
class NoteTopicStats {
  /// 记录条数
  final int count;

  /// 最早 / 最近一条记录的「发生时间」
  final DateTime? firstAt;
  final DateTime? lastAt;

  /// 正文总字数（不含空白）
  final int wordCount;

  const NoteTopicStats({
    this.count = 0,
    this.firstAt,
    this.lastAt,
    this.wordCount = 0,
  });

  factory NoteTopicStats.of(Iterable<NoteEntry> entries) {
    var count = 0;
    DateTime? first;
    DateTime? last;
    var words = 0;
    for (final e in entries) {
      count++;
      words += e.plainText.replaceAll(RegExp(r'\s'), '').length;
      if (first == null || e.occurredAt.isBefore(first)) first = e.occurredAt;
      if (last == null || e.occurredAt.isAfter(last)) last = e.occurredAt;
    }
    return NoteTopicStats(
      count: count,
      firstAt: first,
      lastAt: last,
      wordCount: words,
    );
  }

  /// 跨度文本（0/1 条时为空）
  String get span {
    if (count < 2) return '';
    return spanText(firstAt, lastAt);
  }

  /// 列表摘要：共 12 条 · 跨 7 个月 · 上次 3 天前
  String line({DateTime? now}) {
    if (count == 0) return '还没有记录';
    final parts = <String>['共 $count 条'];
    final s = span;
    if (s.isNotEmpty) parts.add('跨 $s');
    parts.add('上次 ${relativeDaysText(lastAt, now: now)}');
    if (wordCount > 0) parts.add('约 $wordCount 字');
    return parts.join(' · ');
  }
}

/// 时间线分组：一个月一组
class NoteMonthGroup {
  /// 分组键 yyyy-MM（用于稳定排序）
  final String key;

  /// 展示标题，如「2026 年 10 月」
  final String label;

  final List<NoteEntry> entries;

  const NoteMonthGroup({
    required this.key,
    required this.label,
    required this.entries,
  });

  int get count => entries.length;
}

/// 把记录按「年-月」分组，新的月份在前；月内按发生时间倒序。
///
/// 同一时刻的多条按创建时间兜底，保证顺序稳定（不会每次刷新跳来跳去）。
List<NoteMonthGroup> groupEntriesByMonth(List<NoteEntry> entries) {
  final sorted = List<NoteEntry>.of(entries)..sort(_compareEntriesDesc);
  final buckets = <String, List<NoteEntry>>{};
  final order = <String>[];
  for (final e in sorted) {
    final k = monthKey(e.occurredAt);
    final list = buckets[k];
    if (list == null) {
      buckets[k] = [e];
      order.add(k);
    } else {
      list.add(e);
    }
  }
  return [
    for (final k in order)
      NoteMonthGroup(
        key: k,
        label: monthLabel(DateTime.parse('$k-01')),
        entries: buckets[k]!,
      ),
  ];
}

/// 记录倒序比较：发生时间新的在前，同刻按创建时间、再按 id（稳定）
int _compareEntriesDesc(NoteEntry a, NoteEntry b) {
  final c = b.occurredAt.compareTo(a.occurredAt);
  if (c != 0) return c;
  final c2 = b.createdAt.compareTo(a.createdAt);
  if (c2 != 0) return c2;
  return b.id.compareTo(a.id);
}

/// 记录列表排序（返回新列表，不改入参）
List<NoteEntry> sortEntriesDesc(List<NoteEntry> entries) =>
    List<NoteEntry>.of(entries)..sort(_compareEntriesDesc);

/// 主题列表排序：置顶在前，其次按最近记录时间倒序，最后按创建时间
List<NoteTopic> sortTopics(List<NoteTopic> topics) {
  return List<NoteTopic>.of(topics)..sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final c = b.updatedAt.compareTo(a.updatedAt);
    if (c != 0) return c;
    return b.createdAt.compareTo(a.createdAt);
  });
}

/// 是否命中搜索词（标题 / 简介 / 标签，不区分大小写）
bool topicMatches(NoteTopic t, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (t.title.toLowerCase().contains(q)) return true;
  if (t.intro.toLowerCase().contains(q)) return true;
  return false;
}

/// 记录是否命中搜索词（标题 / 正文 / 标签）
bool entryMatches(NoteEntry e, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (e.title.toLowerCase().contains(q)) return true;
  if (e.plainText.toLowerCase().contains(q)) return true;
  for (final t in e.tags) {
    if (t.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// 过滤记录（保持传入顺序）
List<NoteEntry> searchEntries(List<NoteEntry> entries, String query) {
  final q = query.trim();
  if (q.isEmpty) return List<NoteEntry>.of(entries);
  return entries.where((e) => entryMatches(e, q)).toList();
}

/// 单个主题导出为 Markdown（通用格式，任何编辑器可读）。
///
/// 结构：标题 → 元信息 → 按年月分组 → 每条记录（时间 / 标签 / 位置 / 附件 / 正文）。
String topicToMarkdown({
  required NoteTopic topic,
  String? groupName,
  required List<NoteEntry> entries,
  DateTime? now,
}) {
  final stats = NoteTopicStats.of(entries);
  final b = StringBuffer();
  final title = topic.title.trim().isEmpty ? '未命名主题' : topic.title.trim();
  b.write('# $title\n\n');

  final meta = <String>[];
  if (groupName != null && groupName.trim().isNotEmpty) {
    meta.add('- 分组：${groupName.trim()}');
  }
  if (topic.intro.trim().isNotEmpty) {
    meta.add('- 简介：${topic.intro.trim()}');
  }
  meta.add('- 记录：${stats.count} 条');
  if (stats.firstAt != null && stats.lastAt != null) {
    meta.add(
      '- 时间范围：${dateText(stats.firstAt!)} ~ ${dateText(stats.lastAt!)}'
      '${stats.span.isEmpty ? '' : '（跨 ${stats.span}）'}',
    );
  }
  if (stats.wordCount > 0) meta.add('- 正文合计：约 ${stats.wordCount} 字');
  meta.add('- 导出时间：${dateTimeText(now ?? DateTime.now())}');
  b.write(meta.join('\n'));
  b.write('\n\n');

  if (entries.isEmpty) {
    b.write('（这个主题还没有记录）\n');
    return b.toString();
  }

  for (final g in groupEntriesByMonth(entries)) {
    b.write('## ${g.label}\n\n');
    for (final e in g.entries) {
      b.write('### ${dateTimeText(e.occurredAt)} · ${e.displayTitle}\n\n');
      if (e.tags.isNotEmpty) b.write('- 标签：${e.tags.join('、')}\n');
      if (e.locationStamp.enabled) {
        final name = e.locationStamp.name.trim();
        b.write(
          '- 位置：${name.isEmpty ? '地图标记' : name}'
          '（${e.locationStamp.lat}, ${e.locationStamp.lng}）\n',
        );
      }
      if (e.media.isNotEmpty) {
        b.write(
          '- 附件：${e.media.map((m) => m.file ?? m.external ?? m.type.name).join('、')}\n',
        );
      }
      if (e.tags.isNotEmpty || e.media.isNotEmpty || e.locationStamp.enabled) {
        b.write('\n');
      }
      final text = e.plainText.trim();
      b.write(text.isEmpty ? '（无正文）\n\n' : '$text\n\n');
      b.write('---\n\n');
    }
  }
  return b.toString();
}

/// 多个主题导出为一个 Markdown（「导出全部笔记」用）。
String notesToMarkdown({
  required List<NoteTopic> topics,
  required Map<String, String> groupNames,
  required Map<String, List<NoteEntry>> entriesByTopic,
  DateTime? now,
}) {
  final b = StringBuffer('# 笔记总览\n\n');
  b.write('- 主题：${topics.length} 个\n');
  b.write('- 导出时间：${dateTimeText(now ?? DateTime.now())}\n\n');
  if (topics.isEmpty) {
    b.write('（还没有笔记主题）\n');
    return b.toString();
  }
  for (final t in sortTopics(topics)) {
    final entries = entriesByTopic[t.id] ?? const <NoteEntry>[];
    b.write('${topicToMarkdown(topic: t, groupName: groupNames[t.id], entries: entries, now: now)}\n\n');
  }
  return b.toString();
}
