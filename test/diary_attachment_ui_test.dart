import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/diary/diary_edit_page.dart';
import 'package:allone/features/diary/diary_models.dart';
import 'package:allone/features/diary/diary_page.dart';

import 'support/mem_store.dart';

/// 附件「添加后立刻可见」：
/// ① 编辑页把已添加的附件直接列出来（不必点开「附件(n)」弹层）；
/// ② 列表卡片上有附件数量，保存后一眼能看出这篇带附件。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  final t0 = DateTime(2026, 10, 18, 9);

  const media = [
    MediaAttachment(
      type: MediaType.photo,
      file: '1700000000000_照片.jpg',
      size: 1024,
    ),
    MediaAttachment(
      type: MediaType.audio,
      file: '1700000000001_录音.m4a',
      size: 2048,
    ),
  ];

  DiaryEntry entry() => DiaryEntry(
    id: 'e1',
    title: '带附件的日记',
    plainText: '正文',
    createdAt: t0,
    updatedAt: t0,
    media: media,
  );

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

  testWidgets('编辑页：已添加的附件直接铺开成缩略图（不用点开弹层）', (tester) async {
    await pump(tester, DiaryEditPage(entry: entry()));

    // 每张缩略图都带「文件名（点一下打开）」提示，说明它已经在编辑区里了
    expect(find.byTooltip('照片.jpg（点一下打开）'), findsOneWidget);
    expect(find.byTooltip('录音.m4a（点一下打开）'), findsOneWidget);
    // 缩略图块（照片没真实文件时退化成图标块）仍然占位可点
    expect(find.byIcon(Icons.photo_outlined), findsWidgets);
    expect(find.byIcon(Icons.mic_none_outlined), findsWidgets);
    // 底部计数按钮仍在（点开可看完整列表）
    expect(find.textContaining('附件(2)'), findsOneWidget);
  });

  testWidgets('列表：有附件的日记显示附件图标与数量', (tester) async {
    await store.write('diary/entries/e1.json', entry().toJson());
    await pump(tester, const DiaryPage());

    expect(find.text('带附件的日记'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: '应显示附件数量');
  });
}
