import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/notes/note_topic_page.dart';
import 'package:allone/features/notes/notes_models.dart';
import 'package:allone/features/notes/notes_page.dart';

import 'support/mem_store.dart';

/// 笔记界面测试：空状态引导、主题卡片统计、进入时间线、长按移入回收站。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  final now = DateTime.now();

  NoteTopic topic(String id, {String title = '', bool pinned = false}) =>
      NoteTopic(
        id: id,
        title: title,
        pinned: pinned,
        createdAt: now,
        updatedAt: now,
      );

  NoteEntry entry(String id, String topicId, DateTime occurred, String text) =>
      NoteEntry(
        id: id,
        topicId: topicId,
        title: text,
        plainText: text,
        occurredAt: occurred,
        createdAt: occurred,
        updatedAt: occurred,
      );

  Future<void> seedTopic(NoteTopic t, List<NoteEntry> entries) async {
    await store.write('notes/topics/${t.id}.json', t.toJson());
    for (final e in entries) {
      await store.write('notes/topics/${t.id}/entries/${e.id}.json', e.toJson());
    }
  }

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  testWidgets('没有主题时给引导，并提示可以新建', (tester) async {
    await pump(tester, const NotesPage());

    expect(find.text('还没有笔记主题'), findsOneWidget);
    expect(find.text('新建主题'), findsOneWidget);
    expect(find.text('新的主题'), findsOneWidget); // FAB
  });

  testWidgets('主题卡片显示「共 N 条 / 跨 / 上次」统计', (tester) async {
    await seedTopic(topic('t1', title: '《人类简史》'), [
      entry('e1', 't1', now.subtract(const Duration(days: 2)), '开读'),
      entry('e2', 't1', now, '第 3 章'),
    ]);
    await pump(tester, const NotesPage());

    expect(find.text('《人类简史》'), findsOneWidget);
    expect(find.textContaining('共 2 条'), findsOneWidget);
    expect(find.textContaining('跨 3 天'), findsOneWidget);
    expect(find.textContaining('上次 今天'), findsOneWidget);
  });

  testWidgets('点主题进入时间线：年月分组与记录都在', (tester) async {
    await seedTopic(topic('t1', title: '吉他'), [
      NoteEntry(
        id: 'e1',
        topicId: 't1',
        title: '练习 1',
        plainText: '换和弦练习',
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    await pump(tester, const NotesPage());

    await tester.tap(find.text('吉他'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTopicPage), findsOneWidget);
    expect(find.text('${now.year} 年 ${now.month} 月'), findsOneWidget);
    expect(find.text('练习 1'), findsOneWidget, reason: '记录小标题');
    expect(find.text('换和弦练习'), findsOneWidget, reason: '记录正文摘要');
    expect(find.text('记一条'), findsOneWidget);
  });

  testWidgets('长按卡片可把主题移入回收站（软删除，数据仍在）', (tester) async {
    await seedTopic(topic('t1', title: '要删的主题'), []);
    await pump(tester, const NotesPage());

    await tester.longPress(find.text('要删的主题'));
    await tester.pumpAndSettle();
    expect(find.text('删除主题'), findsOneWidget);

    await tester.tap(find.text('删除主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();

    final saved = await store.read('notes/topics/t1.json');
    expect(saved?['deletedAt'], isNotNull, reason: '应该是软删除');
    expect(find.text('要删的主题'), findsNothing, reason: '列表里不再显示');
  });

  testWidgets('置顶的主题排在前面', (tester) async {
    await seedTopic(topic('t1', title: '普通'), []);
    await seedTopic(topic('t2', title: '置顶的', pinned: true), []);
    await pump(tester, const NotesPage());

    final cards = tester.widgetList<Text>(find.byType(Text)).toList();
    final iPin = cards.indexWhere((t) => t.data == '置顶的');
    final iNormal = cards.indexWhere((t) => t.data == '普通');
    expect(iPin, greaterThanOrEqualTo(0));
    expect(iNormal, greaterThanOrEqualTo(0));
    expect(iPin, lessThan(iNormal));
  });
}
