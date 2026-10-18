import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/quest/quest_detail_page.dart';
import 'package:allone/features/quest/quest_edit_page.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/quest/quest_repository.dart';

import 'support/mem_store.dart';

/// 任务 / 子项目的附件与描述：
/// ① 模型层要有 media 且 JSON 往返不丢；
/// ② 新建子项目走完整编辑页（描述 + 四类附件），不是只有一个名称输入框；
/// ③ 子项目保存后挂在父任务下，并排在同级末尾。
void main() {
  late MemStore store;
  late ProviderContainer container;

  final t0 = DateTime.parse('2026-10-18T09:00:00');

  Quest quest(String id, {String parentId = '', int order = 0}) => Quest(
    id: id,
    title: '任务$id',
    parentId: parentId,
    order: order,
    createdAt: t0,
    updatedAt: t0,
  );

  setUp(() {
    store = MemStore();
    container = ProviderContainer(
      overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
    );
  });

  tearDown(() => container.dispose());

  group('模型：附件', () {
    test('media JSON 往返（照片 + 录音 + 外链大文件）', () {
      final q = Quest(
        id: 'q1',
        title: '带附件的任务',
        createdAt: t0,
        updatedAt: t0,
        media: const [
          MediaAttachment(type: MediaType.photo, file: '1.jpg', size: 100),
          MediaAttachment(type: MediaType.audio, file: '1.m4a', size: 2000),
          MediaAttachment(
            type: MediaType.video,
            external: 'D:/v/big.mp4',
            size: 90000000,
            note: '大文件外链',
          ),
        ],
      );
      final back = Quest.fromJson(q.toJson());
      expect(back.media.length, 3);
      expect(back.media[0].type, MediaType.photo);
      expect(back.media[0].file, '1.jpg');
      expect(back.media[1].type, MediaType.audio);
      expect(back.media[1].size, 2000);
      expect(back.media[2].external, 'D:/v/big.mp4');
    });

    test('没有 media 字段的老数据读出来是空列表', () {
      final back = Quest.fromJson({...quest('q2').toJson()}..remove('media'));
      expect(back.media, isEmpty);
    });
  });

  group('仓库：子项目落位', () {
    test('通过 save 新建的子项目挂在父任务下，并排在同级末尾', () async {
      await store.write('quest/quests/p.json', quest('p').toJson());
      await store.write('quest/quests/c1.json', quest('c1', parentId: 'p', order: 0).toJson());
      await container.read(questListProvider.future);

      final n = container.read(questListProvider.notifier);
      await n.save(quest('c2', parentId: 'p'));
      await n.save(quest('c3', parentId: 'p'));

      final c2 = await store.read('quest/quests/c2.json');
      final c3 = await store.read('quest/quests/c3.json');
      expect(c2!['parentId'], 'p');
      expect(c2['order'], 1, reason: '排在已有子项目之后');
      expect(c3!['order'], 2);
    });
  });

  group('界面：新建子项目的完整编辑页', () {
    Future<void> pumpDetail(WidgetTester tester, String questId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
          child: MaterialApp(home: QuestDetailPage(questId: questId)),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    }

    testWidgets('点「添加子项目」打开的是完整编辑页：有描述与四类附件', (tester) async {
      await store.write('quest/quests/p.json', quest('p').toJson());
      await pumpDetail(tester, 'p');

      await tester.tap(find.byTooltip('添加子项目'));
      await tester.pumpAndSettle();

      expect(find.byType(QuestEditPage), findsOneWidget);
      // 描述字段（不再是「只有一个名称」）
      expect(find.text('描述 / 目标（想做成什么样、为什么做）'), findsOneWidget);
      // 四类附件入口都在
      expect(find.text('附件（照片 / 录音 / 视频 / 文件）'), findsOneWidget);
      for (final label in ['照片', '录音', '视频', '文件']) {
        expect(find.text(label), findsOneWidget, reason: '缺少「$label」入口');
      }
    });

    testWidgets('填标题保存后，子项目真的落盘并挂在父任务下', (tester) async {
      await store.write('quest/quests/p.json', quest('p').toJson());
      await pumpDetail(tester, 'p');

      await tester.tap(find.byTooltip('添加子项目'));
      await tester.pumpAndSettle();

      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, '收集资料');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final files = await store.listFiles('quest/quests');
      final childFile = files.firstWhere((f) => f != 'p.json');
      final json = await store.read('quest/quests/$childFile');
      expect(json!['title'], '收集资料');
      expect(json['parentId'], 'p');
      expect(json['order'], 0);
    });
  });
}
