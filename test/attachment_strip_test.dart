import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/core/widgets/attachment_view.dart';
import 'package:allone/features/notes/note_entry_edit_page.dart';
import 'package:allone/features/notes/notes_models.dart';
import 'package:allone/features/quest/quest_edit_page.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/todo/todo_edit_page.dart';
import 'package:allone/features/todo/todo_models.dart';

import 'support/mem_store.dart';

/// 附件缩略图条在待办 / 任务 / 笔记编辑页也要生效（与日记一致）：
/// 打开就看得见已有附件，不用再点「附件(n)」弹层。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  final t0 = DateTime(2026, 10, 18, 9);

  const media = [
    MediaAttachment(
      type: MediaType.photo,
      file: '1700000000000_参考图.jpg',
      size: 1024,
    ),
    MediaAttachment(
      type: MediaType.audio,
      file: '1700000000001_备忘.m4a',
      size: 2048,
    ),
  ];

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

  void expectStrip() {
    expect(find.byType(MediaThumbStrip), findsOneWidget);
    expect(find.byTooltip('参考图.jpg（点一下打开）'), findsOneWidget);
    expect(find.byTooltip('备忘.m4a（点一下打开）'), findsOneWidget);
  }

  testWidgets('待办编辑页：已有附件直接铺成缩略图', (tester) async {
    await pump(
      tester,
      TodoEditPage(
        item: TodoItem(
          id: 'i1',
          title: '待办',
          media: media,
          createdAt: t0,
          updatedAt: t0,
        ),
      ),
    );
    expectStrip();
  });

  testWidgets('任务编辑页：已有附件直接铺成缩略图', (tester) async {
    await pump(
      tester,
      QuestEditPage(
        quest: Quest(
          id: 'q1',
          title: '任务',
          media: media,
          createdAt: t0,
          updatedAt: t0,
        ),
      ),
    );
    expectStrip();
  });

  testWidgets('笔记记录编辑页：已有附件直接铺成缩略图', (tester) async {
    await pump(
      tester,
      NoteEntryEditPage(
        topicId: 't1',
        entry: NoteEntry(
          id: 'e1',
          topicId: 't1',
          title: '记录',
          occurredAt: t0,
          createdAt: t0,
          updatedAt: t0,
          media: media,
        ),
      ),
    );
    expectStrip();
  });
}
