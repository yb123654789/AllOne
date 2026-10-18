import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/notes/notes_logic.dart';
import 'package:allone/features/notes/notes_models.dart';

/// 笔记纯逻辑：跨度统计 / 时间线分组 / 搜索 / Markdown 导出。
void main() {
  NoteEntry entry(
    String id,
    String topicId,
    DateTime occurred, {
    String title = '',
    String text = '',
    List<String> tags = const [],
    List<MediaAttachment> media = const [],
    LocationStamp location = const LocationStamp(),
  }) => NoteEntry(
    id: id,
    topicId: topicId,
    title: title,
    plainText: text,
    occurredAt: occurred,
    createdAt: occurred,
    updatedAt: occurred,
    tags: tags,
    media: media,
    locationStamp: location,
  );

  final now = DateTime(2026, 10, 18, 20, 0);

  group('颜色解析', () {
    test('6 位补满不透明，8 位原样，非法返回 null', () {
      expect(parseHexColor('#2F6FED'), 0xFF2F6FED);
      expect(parseHexColor('2F6FED'), 0xFF2F6FED);
      expect(parseHexColor('#802F6FED'), 0x802F6FED);
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('zzzzzz'), isNull);
      expect(parseHexColor(''), isNull);
    });
  });

  group('「上次记录」相对时间', () {
    test('null / 今天 / 昨天 / 天数', () {
      expect(relativeDaysText(null, now: now), '尚无记录');
      expect(relativeDaysText(DateTime(2026, 10, 18, 0, 1), now: now), '今天');
      expect(relativeDaysText(DateTime(2026, 10, 17, 23, 59), now: now), '昨天');
      expect(relativeDaysText(DateTime(2026, 10, 8), now: now), '10 天前');
    });

    test('超过 30 天按月、超过 365 天按年', () {
      expect(relativeDaysText(DateTime(2026, 7, 18), now: now), '3 个月前');
      expect(relativeDaysText(DateTime(2024, 10, 18), now: now), '2 年前');
    });
  });

  group('跨度文本', () {
    test('同一天 / 几天 / 几个月 / 几年', () {
      expect(spanText(DateTime(2026, 10, 1), DateTime(2026, 10, 1)), '同一天');
      expect(spanText(DateTime(2026, 10, 1), DateTime(2026, 10, 3)), '3 天');
      expect(spanText(DateTime(2026, 10, 1), DateTime(2026, 11, 1)), '1 个月');
      expect(spanText(DateTime(2025, 10, 1), DateTime(2026, 10, 1)), '1 年');
      expect(spanText(DateTime(2025, 3, 15), DateTime(2026, 5, 16)), '1 年 2 个月');
    });

    test('两端为空返回空串；顺序反了也能算', () {
      expect(spanText(null, DateTime(2026, 10, 1)), '');
      expect(spanText(DateTime(2026, 10, 1), null), '');
      expect(spanText(DateTime(2026, 10, 3), DateTime(2026, 10, 1)), '3 天');
    });
  });

  group('主题统计', () {
    test('条数按条算、跨度按首尾算、字数不含空白', () {
      final stats = NoteTopicStats.of([
        entry('a', 't', DateTime(2026, 10, 1), text: '一二 三'),
        entry('b', 't', DateTime(2026, 10, 3), text: '四五六\n'),
      ]);
      expect(stats.count, 2);
      expect(stats.firstAt, DateTime(2026, 10, 1));
      expect(stats.lastAt, DateTime(2026, 10, 3));
      expect(stats.wordCount, 6);
      expect(stats.span, '3 天');
      expect(
        stats.line(now: now),
        '共 2 条 · 跨 3 天 · 上次 15 天前 · 约 6 字',
      );
    });

    test('空主题 / 单条记录', () {
      final empty = NoteTopicStats.of(const []);
      expect(empty.count, 0);
      expect(empty.line(now: now), '还没有记录');
      expect(empty.span, '');

      final one = NoteTopicStats.of([
        entry('a', 't', DateTime(2026, 10, 18)),
      ]);
      expect(one.span, '');
      expect(one.line(now: now), '共 1 条 · 上次 今天');
    });
  });

  group('时间线按年月分组', () {
    test('新的月份在前，月内按发生时间倒序', () {
      final groups = groupEntriesByMonth([
        entry('a', 't', DateTime(2026, 9, 5)),
        entry('b', 't', DateTime(2026, 10, 2)),
        entry('c', 't', DateTime(2026, 10, 11)),
        entry('d', 't', DateTime(2025, 12, 31)),
      ]);
      expect(groups.map((g) => g.key).toList(), ['2026-10', '2026-09', '2025-12']);
      expect(groups.first.label, '2026 年 10 月');
      expect(groups.first.entries.map((e) => e.id).toList(), ['c', 'b']);
      expect(groups.first.count, 2);
    });

    test('同一时刻按创建时间 / id 兜底，顺序稳定', () {
      final at = DateTime(2026, 10, 1, 9);
      final groups = groupEntriesByMonth([
        entry('x', 't', at),
        entry('y', 't', at),
      ]);
      expect(groups.single.entries.map((e) => e.id).toList(), ['y', 'x']);
    });
  });

  group('搜索', () {
    final e = entry(
      'a',
      't',
      DateTime(2026, 10, 1),
      title: 'Flutter 布局',
      text: 'Row 与 Column 的区别',
      tags: const ['前端', 'Flutter'],
    );

    test('标题 / 正文 / 标签都能命中，大小写不敏感', () {
      expect(entryMatches(e, 'flutter'), isTrue);
      expect(entryMatches(e, 'Row'), isTrue);
      expect(entryMatches(e, 'column'), isTrue);
      expect(entryMatches(e, '前端'), isTrue);
      expect(entryMatches(e, '不存在的词'), isFalse);
      expect(entryMatches(e, '   '), isTrue);
    });

    test('主题按标题 / 简介命中', () {
      final t = NoteTopic(
        id: 't',
        title: '《人类简史》',
        intro: '认知类，读完写读后感',
        createdAt: now,
        updatedAt: now,
      );
      expect(topicMatches(t, '人类'), isTrue);
      expect(topicMatches(t, '读后感'), isTrue);
      expect(topicMatches(t, '经济学'), isFalse);
    });

    test('searchEntries 空词返回全部', () {
      final list = [e, entry('b', 't', DateTime(2026, 10, 2), text: '别的')];
      expect(searchEntries(list, '').length, 2);
      expect(searchEntries(list, 'row').single.id, 'a');
    });
  });

  group('Markdown 导出', () {
    test('单主题：标题 / 元信息 / 月份 / 记录 / 标签 / 附件', () {
      final topic = NoteTopic(
        id: 't',
        title: '《人类简史》',
        intro: '认知类',
        createdAt: now,
        updatedAt: now,
      );
      final md = topicToMarkdown(
        topic: topic,
        groupName: '读书',
        entries: [
          entry(
            'a',
            't',
            DateTime(2026, 10, 3, 10),
            title: '第 3 章',
            text: '农业革命是史上最大骗局。',
            tags: const ['摘抄'],
            media: const [
              MediaAttachment(type: MediaType.photo, file: 'p1.jpg'),
            ],
          ),
          entry('b', 't', DateTime(2026, 9, 1, 8), text: '开读'),
        ],
        now: now,
      );
      expect(md, startsWith('# 《人类简史》\n'));
      expect(md, contains('- 分组：读书'));
      expect(md, contains('- 简介：认知类'));
      expect(md, contains('- 记录：2 条'));
      expect(md, contains('- 时间范围：2026-09-01 ~ 2026-10-03'));
      expect(md, contains('## 2026 年 10 月'));
      expect(md, contains('## 2026 年 9 月'));
      expect(md, contains('### 2026-10-03 10:00 · 第 3 章'));
      expect(md, contains('- 标签：摘抄'));
      expect(md, contains('- 附件：p1.jpg'));
      expect(md, contains('农业革命是史上最大骗局。'));
      // 顺序：10 月在前
      expect(md.indexOf('## 2026 年 10 月'), lessThan(md.indexOf('## 2026 年 9 月')));
    });

    test('空主题也有一句说明，不会导出空文件', () {
      final topic = NoteTopic(id: 't', title: '', createdAt: now, updatedAt: now);
      final md = topicToMarkdown(topic: topic, entries: const [], now: now);
      expect(md, contains('# 未命名主题'));
      expect(md, contains('（这个主题还没有记录）'));
    });

    test('多主题总览：每个主题一段', () {
      final t1 = NoteTopic(id: 't1', title: 'A', createdAt: now, updatedAt: now);
      final t2 = NoteTopic(id: 't2', title: 'B', createdAt: now, updatedAt: now);
      final md = notesToMarkdown(
        topics: [t1, t2],
        groupNames: const {},
        entriesByTopic: {
          't1': [entry('e1', 't1', DateTime(2026, 10, 1), text: '内容一')],
          't2': const [],
        },
        now: now,
      );
      expect(md, contains('# 笔记总览'));
      expect(md, contains('- 主题：2 个'));
      expect(md, contains('# A'));
      expect(md, contains('# B'));
      expect(md, contains('内容一'));
    });
  });

  group('排序', () {
    test('主题：置顶在前，其余按最近记录时间倒序', () {
      final a = NoteTopic(
        id: 'a',
        title: 'A',
        updatedAt: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      final b = NoteTopic(
        id: 'b',
        title: 'B',
        updatedAt: DateTime(2026, 10, 10),
        createdAt: DateTime(2026, 1, 1),
      );
      final c = NoteTopic(
        id: 'c',
        title: 'C',
        pinned: true,
        updatedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      expect(sortTopics([a, b, c]).map((t) => t.id).toList(), ['c', 'b', 'a']);
    });

    test('记录：发生时间新的在前', () {
      final list = [
        entry('old', 't', DateTime(2026, 1, 1)),
        entry('new', 't', DateTime(2026, 10, 1)),
      ];
      expect(sortEntriesDesc(list).map((e) => e.id).toList(), ['new', 'old']);
    });
  });
}
