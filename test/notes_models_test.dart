import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/notes/notes_models.dart';

/// 笔记模型：JSON 往返 + 反序列化容错 + copyWith 的边界行为。
void main() {
  group('NoteGroup', () {
    test('JSON 往返保持全部字段', () {
      final now = DateTime(2026, 10, 18, 20, 15);
      final g = NoteGroup(
        id: 'g1',
        name: '学习',
        color: '#2E9E6B',
        order: 3,
        createdAt: now,
        updatedAt: now,
      );
      final back = NoteGroup.fromJson(g.toJson());
      expect(back.id, 'g1');
      expect(back.name, '学习');
      expect(back.color, '#2E9E6B');
      expect(back.order, 3);
      expect(back.createdAt, now);
      expect(back.updatedAt, now);
    });

    test('缺字段时用默认值（老数据 / 手改数据不崩）', () {
      final g = NoteGroup.fromJson(const {'id': 'g2'});
      expect(g.name, '');
      expect(g.color, kDefaultNoteColor);
      expect(g.order, 0);
    });
  });

  group('NoteTopic', () {
    final now = DateTime(2026, 10, 18, 20, 15);

    test('JSON 往返：未分组时不写 groupIds，读回来是空列表', () {
      final t = NoteTopic(
        id: 't1',
        title: '吉他',
        intro: '练琴记录',
        pinned: true,
        createdAt: now,
        updatedAt: now,
      );
      final json = t.toJson();
      expect(json.containsKey('groupIds'), isFalse);
      final back = NoteTopic.fromJson(json);
      expect(back.id, 't1');
      expect(back.title, '吉他');
      expect(back.groupIds, isEmpty);
      expect(back.ungrouped, isTrue);
      expect(back.pinned, isTrue);
      expect(back.archived, isFalse);
      expect(back.inTrash, isFalse);
    });

    test('一个主题可属于多个分组，且兼容旧的单个 groupId 字段', () {
      final t = NoteTopic(
        id: 't1b',
        groupIds: const ['g1', 'g2'],
        title: '某本书',
        createdAt: now,
        updatedAt: now,
      );
      expect(NoteTopic.fromJson(t.toJson()).groupIds, ['g1', 'g2']);
      // 老数据（只有 groupId）也要能读出来
      final legacy = NoteTopic.fromJson(const {
        'id': 'old',
        'groupId': 'g1',
        'title': '旧主题',
      });
      expect(legacy.groupIds, ['g1']);
      expect(legacy.ungrouped, isFalse);
    });

    test('回收站标记：deletedAt 有值即 inTrash', () {
      final t = NoteTopic(
        id: 't2',
        deletedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      expect(t.inTrash, isTrue);
      final back = NoteTopic.fromJson(t.toJson());
      expect(back.inTrash, isTrue);
      expect(back.deletedAt, now);
    });

    test('copyWith：groupIds 整组替换，withGroup / withoutGroup 增减', () {
      final t = NoteTopic(
        id: 't3',
        groupIds: const ['g1'],
        title: 'A',
        createdAt: now,
        updatedAt: now,
      );
      expect(t.copyWith(title: 'B').groupIds, ['g1']);
      final cleared = t.copyWith(groupIds: const []);
      expect(cleared.groupIds, isEmpty);
      expect(cleared.title, 'A');
      // 增减单个分组
      expect(t.withGroup('g2').groupIds, ['g1', 'g2']);
      expect(t.withGroup('g1').groupIds, ['g1']); // 已存在不重复
      expect(t.withoutGroup('g1').groupIds, isEmpty);
      expect(t.withoutGroup('nope').groupIds, ['g1']);
    });

    test('copyWith：clearDeletedAt 从回收站恢复', () {
      final t = NoteTopic(
        id: 't4',
        deletedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final restored = t.copyWith(clearDeletedAt: true);
      expect(restored.inTrash, isFalse);
      expect(restored.deletedAt, isNull);
    });
  });

  group('NoteEntry', () {
    final occurred = DateTime(2026, 3, 1, 9, 30);
    final created = DateTime(2026, 3, 2, 10, 0);

    test('JSON 往返：正文 / 标签 / 附件 / 位置都在', () {
      final e = NoteEntry(
        id: 'e1',
        topicId: 't1',
        title: '第 3 章',
        plainText: '摘要与感想',
        occurredAt: occurred,
        createdAt: created,
        updatedAt: created,
        tags: const ['读书', '认知'],
        media: const [
          MediaAttachment(type: MediaType.photo, file: '1.jpg', size: 1234),
        ],
        locationStamp: const LocationStamp(
          enabled: true,
          lat: 31.2,
          lng: 121.5,
          name: '图书馆',
        ),
      );
      final back = NoteEntry.fromJson(e.toJson());
      expect(back.id, 'e1');
      expect(back.topicId, 't1');
      expect(back.title, '第 3 章');
      expect(back.plainText, '摘要与感想');
      expect(back.occurredAt, occurred);
      expect(back.tags, ['读书', '认知']);
      expect(back.media.single.file, '1.jpg');
      expect(back.media.single.type, MediaType.photo);
      expect(back.locationStamp.enabled, isTrue);
      expect(back.locationStamp.name, '图书馆');
    });

    test('缺 occurredAt 时退回 createdAt（不让一条坏数据整条丢失）', () {
      final back = NoteEntry.fromJson({
        'id': 'e2',
        'topicId': 't1',
        'createdAt': created.toIso8601String(),
      });
      expect(back.occurredAt, created);
      expect(back.plainText, '');
      expect(back.media, isEmpty);
      expect(back.tags, isEmpty);
      expect(back.locationStamp.enabled, isFalse);
    });

    test('displayTitle：标题优先，其次正文首非空行，最后「无标题」', () {
      NoteEntry make(String title, String text) => NoteEntry(
        id: 'x',
        topicId: 't',
        title: title,
        plainText: text,
        occurredAt: occurred,
        createdAt: created,
        updatedAt: created,
      );
      expect(make('真标题', '正文').displayTitle, '真标题');
      expect(make('  ', '\n\n  第一行内容\n第二行').displayTitle, '第一行内容');
      expect(make('', '   ').displayTitle, '无标题');
    });

    test('copyWithTopic 只改归属，不动内容', () {
      final e = NoteEntry(
        id: 'e3',
        topicId: 'old',
        title: '标题',
        plainText: '正文',
        occurredAt: occurred,
        createdAt: created,
        updatedAt: created,
      );
      final moved = e.copyWithTopic('new');
      expect(moved.topicId, 'new');
      expect(moved.title, '标题');
      expect(moved.plainText, '正文');
      expect(moved.occurredAt, occurred);
    });
  });
}
