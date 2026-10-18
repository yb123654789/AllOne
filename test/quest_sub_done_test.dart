import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/quest/quest_detail_page.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/quest/quest_repository.dart';

import 'support/mem_store.dart';

/// 任务模块：子项目能不能被完成（仓库层）。
///
/// 背景：用户反馈「子任务只能创建、无法完成」。
/// 待办模块的子任务是正常的（见 todo_subtask_test.dart），
/// 这里验证「任务」模块的子项目在数据层是否放行。
void main() {
  late MemStore store;
  late ProviderContainer container;

  setUp(() {
    store = MemStore();
    container = ProviderContainer(
      overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
    );
  });

  tearDown(() => container.dispose());

  final t0 = DateTime.parse('2026-10-18T09:00:00');

  Quest q(String id, {String parentId = '', QuestStatus status = QuestStatus.active}) =>
      Quest(
        id: id,
        title: '任务$id',
        parentId: parentId,
        status: status,
        createdAt: t0,
        updatedAt: t0,
      );

  Future<void> seed(List<Quest> list) async {
    for (final x in list) {
      await store.write('quest/quests/${x.id}.json', x.toJson());
    }
  }

  group('子项目完成（仓库层）', () {
    test('没有子项目的子项目可以直接设为已完成', () async {
      await seed([q('p'), q('c', parentId: 'p')]);
      await container.read(questListProvider.future);

      final err = await container
          .read(questListProvider.notifier)
          .setStatus('c', QuestStatus.done);

      expect(err, isNull, reason: '叶子子项目完成不应被拦');
      final json = await store.read('quest/quests/c.json');
      expect(json!['status'], 'done');
    });

    test('子项目也有未了结的下级时，完成会被拒绝（并给出原因）', () async {
      await seed([q('p'), q('c', parentId: 'p'), q('g', parentId: 'c')]);
      await container.read(questListProvider.future);

      final err = await container
          .read(questListProvider.notifier)
          .setStatus('c', QuestStatus.done);

      expect(err, isNotNull);
      expect(err, contains('子项目'));
    });

    test('子项目可以放弃（放弃后算「了结」，不再卡住父任务）', () async {
      await seed([q('p'), q('c', parentId: 'p')]);
      await container.read(questListProvider.future);

      final err = await container
          .read(questListProvider.notifier)
          .setStatus('c', QuestStatus.dropped);
      expect(err, isNull);

      final json = await store.read('quest/quests/c.json');
      expect(json!['status'], 'dropped');
      // 父任务此时应当可以完成
      final parentErr = await container
          .read(questListProvider.notifier)
          .setStatus('p', QuestStatus.done);
      expect(parentErr, isNull);
    });
  });

  // ── 界面层：子项目「完成」必须有直接入口 ──────────────────────────────────
  group('子项目完成（界面）', () {
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

    testWidgets('子项目行上直接点「完成」即可完成（不用进编辑页）', (tester) async {
      await seed([q('p'), q('c', parentId: 'p')]);
      await pumpDetail(tester, 'p');

      expect(find.text('任务c'), findsOneWidget);
      // 行内完成按钮
      expect(find.byTooltip('标记完成'), findsOneWidget);
      await tester.tap(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();

      final json = await store.read('quest/quests/c.json');
      expect(json!['status'], 'done', reason: '点一下就该完成，不该还要绕到编辑页');
    });

    testWidgets('子项目完成后可以再点回来（恢复进行中）', (tester) async {
      await seed([
        q('p'),
        q('c', parentId: 'p', status: QuestStatus.done),
      ]);
      // 默认隐藏已了结的子项目，先显示出来
      await store.write('settings/ui.json', {'hideResolvedSubtasks': false});
      await pumpDetail(tester, 'p');

      expect(find.byTooltip('恢复为进行中'), findsOneWidget);
      await tester.tap(find.byTooltip('恢复为进行中'));
      await tester.pumpAndSettle();

      final json = await store.read('quest/quests/c.json');
      expect(json!['status'], 'active');
    });

    testWidgets('详情页状态菜单可以把任务设为已完成；有未了结子项目时给出原因', (tester) async {
      await seed([q('p'), q('c', parentId: 'p')]);
      await pumpDetail(tester, 'p');

      await tester.tap(find.byIcon(Icons.flag_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设为已完成'));
      await tester.pumpAndSettle();

      final parent = await store.read('quest/quests/p.json');
      expect(parent!['status'], 'active', reason: '子项目没了结时不能完成父任务');
      expect(find.textContaining('子项目没了结'), findsOneWidget, reason: '要说明为什么不行');
    });
  });
}
