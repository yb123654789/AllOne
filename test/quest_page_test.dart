import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/quest/quest_detail_page.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/quest/quest_page.dart';

import 'support/mem_store.dart';

/// 任务总览页 / 详情页的界面接线测试。
///
/// 用内存存储（[MemStore]）：widget 测试的假时钟不推进 dart:io。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  Quest quest({
    required String id,
    String title = '写一本书',
    QuestStatus status = QuestStatus.active,
    String targetDate = '',
    int manualProgress = 0,
    bool pinned = false,
    String pinnedAt = '',
    List<Milestone> milestones = const [],
    DateTime? updatedAt,
    String parentId = '',
    int order = 0,
  }) => Quest(
    id: id,
    title: title,
    category: '学习',
    status: status,
    targetDate: targetDate,
    manualProgress: manualProgress,
    pinned: pinned,
    pinnedAt: pinnedAt,
    milestones: milestones,
    parentId: parentId,
    order: order,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: updatedAt ?? DateTime.parse('${AppTime.dateOnly(DateTime.now())}T10:00:00'),
  );

  Future<void> seedQuest(Quest q) =>
      store.write('quest/quests/${q.id}.json', q.toJson());

  Future<void> seedLogs(String id, List<InvestLog> logs) => store.writeList(
    'quest/logs/$id.json',
    logs.map((e) => e.toJson()).toList(),
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

  group('任务总览页', () {
    testWidgets('钉住的任务出现在「当前重心」，其余按状态分组', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '学会钢琴',
          pinned: true,
          pinnedAt: '2026-10-01T10:00:00',
        ),
      );
      await seedQuest(quest(id: 'q2', title: '写一本书'));
      await seedQuest(
        quest(id: 'q3', title: '旧计划', status: QuestStatus.paused),
      );

      await pump(tester, const QuestPage());

      expect(find.textContaining('当前重心'), findsOneWidget);
      expect(find.textContaining('进行中（1）'), findsOneWidget);
      expect(find.textContaining('暂停（1）'), findsOneWidget);
      expect(find.text('学会钢琴'), findsOneWidget);
      expect(find.text('写一本书'), findsOneWidget);
      expect(find.text('旧计划'), findsOneWidget);
    });

    testWidgets('进度文案：有里程碑按里程碑，没有则手动百分比', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '带里程碑',
          milestones: [
            const Milestone(id: 'm1', title: 'a', done: true),
            const Milestone(id: 'm2', title: 'b'),
          ],
        ),
      );
      await seedQuest(quest(id: 'q2', title: '手动进度', manualProgress: 40));

      await pump(tester, const QuestPage());

      expect(find.text('里程碑 1/2'), findsOneWidget);
      expect(find.text('手动 40%'), findsOneWidget);
    });

    testWidgets('目标倒数与超期提示', (tester) async {
      final future = AppTime.dateOnly(
        DateTime.now().add(const Duration(days: 30)),
      );
      final past = AppTime.dateOnly(
        DateTime.now().subtract(const Duration(days: 5)),
      );
      await seedQuest(quest(id: 'q1', title: '有目标', targetDate: future));
      await seedQuest(quest(id: 'q2', title: '已超期', targetDate: past));
      await seedQuest(quest(id: 'q3', title: '长期事'));

      await pump(tester, const QuestPage());

      expect(find.text('距目标 30 天'), findsOneWidget);
      expect(find.text('已超期 5 天'), findsOneWidget);
      expect(find.text('长期 · 无期限'), findsOneWidget);
    });

    testWidgets('停滞任务会标出来（很久没更新且没有投入）', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '停下来的事',
          updatedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await seedQuest(
        quest(
          id: 'q2',
          title: '一直在推进',
          updatedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      // q2 最近有投入 → 不算停滞
      await seedLogs('q2', [
        InvestLog(
          id: 'l1',
          at: DateTime.now().subtract(const Duration(days: 1)),
          minutes: 60,
        ),
      ]);

      await pump(tester, const QuestPage());

      expect(find.textContaining('停滞 40 天'), findsOneWidget);
      expect(find.textContaining('最近活动 1 天前'), findsOneWidget);
    });

    testWidgets('筛选「停滞」只留下停滞任务；「已结束」看完成的', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '停下来的事',
          updatedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await seedQuest(quest(id: 'q2', title: '正常任务'));
      await seedQuest(
        quest(id: 'q3', title: '做完了', status: QuestStatus.done),
      );

      await pump(tester, const QuestPage());

      await tester.tap(find.text('停滞'));
      await tester.pumpAndSettle();
      expect(find.text('停下来的事'), findsOneWidget);
      expect(find.text('正常任务'), findsNothing);
      expect(find.text('做完了'), findsNothing);

      await tester.tap(find.text('已结束'));
      await tester.pumpAndSettle();
      expect(find.text('做完了'), findsOneWidget);
      expect(find.text('停下来的事'), findsNothing);
    });

    testWidgets('点卡片进入详情页', (tester) async {
      await seedQuest(quest(id: 'q1', title: '写一本书'));
      await pump(tester, const QuestPage());

      await tester.tap(find.text('写一本书'));
      await tester.pumpAndSettle();

      expect(find.text('里程碑（阶段）'), findsOneWidget);
      expect(find.text('行动项（关联待办）'), findsOneWidget);
      expect(find.text('投入记录'), findsOneWidget);
    });

    testWidgets('空态有引导文案', (tester) async {
      await pump(tester, const QuestPage());
      expect(find.textContaining('还没有任务'), findsOneWidget);
    });
  });

  group('任务详情页', () {
    testWidgets('勾选里程碑：写盘并更新进度', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '写一本书',
          milestones: [
            const Milestone(id: 'm1', title: '第一版'),
            const Milestone(id: 'm2', title: '上线'),
          ],
        ),
      );
      await pump(tester, const QuestDetailPage(questId: 'q1'));

      expect(find.text('0%'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.text('50%'), findsOneWidget);
      final json = await store.read('quest/quests/q1.json');
      final saved = Quest.fromJson(json!);
      expect(saved.milestones.where((m) => m.done).length, 1);
      expect(saved.milestones.first.doneAt.isNotEmpty, isTrue);
    });

    testWidgets('记一笔投入：合计与记录都更新', (tester) async {
      await seedQuest(quest(id: 'q1', title: '写一本书'));
      await pump(tester, const QuestDetailPage(questId: 'q1'));

      expect(find.textContaining('还没记过投入'), findsOneWidget);

      await tester.tap(find.text('记一笔'));
      await tester.pumpAndSettle();
      // 分钟输入框（默认 30）→ 直接确认
      await tester.tap(find.text('记下'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 次 · 合计 30 分'), findsOneWidget);
      final list = await store.readList('quest/logs/q1.json');
      expect(list.length, 1);
      expect(list.single['minutes'], 30);
    });

    testWidgets('停滞任务在详情页顶部有提醒', (tester) async {
      await seedQuest(
        quest(
          id: 'q1',
          title: '停下来的事',
          updatedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await pump(tester, const QuestDetailPage(questId: 'q1'));
      expect(find.textContaining('天没有推进了'), findsOneWidget);
    });

    testWidgets('没有可关联待办时给出提示', (tester) async {
      await seedQuest(quest(id: 'q1', title: '写一本书'));
      await pump(tester, const QuestDetailPage(questId: 'q1'));

      await tester.tap(find.byTooltip('关联待办'));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有可关联的待办了'), findsOneWidget);
    });

    testWidgets('长期无期限时显示目标为「长期 · 无期限」', (tester) async {
      await seedQuest(quest(id: 'q1', title: '长期事', targetDate: ''));
      await pump(tester, const QuestDetailPage(questId: 'q1'));
      expect(find.text('长期 · 无期限'), findsOneWidget);
      expect(find.text('始于 ${AppTime.dateOnly(DateTime.parse('2026-01-01'))}'), findsNothing);
    });
  });

  group('任务层级（子项目）', () {
    testWidgets('总览只列顶层任务（子项目不出现）', (tester) async {
      await seedQuest(quest(id: 'p', title: '父任务'));
      await seedQuest(quest(id: 'a', title: '子项目A', parentId: 'p'));
      await pump(tester, const QuestPage());

      expect(find.text('父任务'), findsOneWidget);
      expect(find.text('子项目A'), findsNothing);
      // 卡片上会说明子项目情况
      expect(find.textContaining('子项目 0/1 了结'), findsOneWidget);
    });

    testWidgets('详情页展示子项目，父进度按子项目等权加权', (tester) async {
      await seedQuest(quest(id: 'p', title: '父任务'));
      await seedQuest(
        quest(
          id: 'a',
          title: '子项目A',
          parentId: 'p',
          order: 0,
          manualProgress: 100,
        ),
      );
      await seedQuest(
        quest(id: 'b', title: '子项目B', parentId: 'p', order: 1),
      );
      await pump(tester, const QuestDetailPage(questId: 'p'));

      expect(find.text('子项目'), findsOneWidget);
      expect(find.text('子项目A'), findsOneWidget);
      expect(find.text('子项目B'), findsOneWidget);
      expect(find.textContaining('2 个 · 已了结 0'), findsOneWidget);
      // A=100%、B=0%，work 因子相同 → 等权 → 50%
      expect(find.text('50%'), findsWidgets);
      expect(find.textContaining('进度按子项目加权'), findsOneWidget);
    });

    testWidgets('已完成 / 已放弃的子项目默认隐藏，可切换显示', (tester) async {
      await seedQuest(quest(id: 'p', title: '父任务'));
      await seedQuest(
        quest(
          id: 'a',
          title: '已做子项',
          parentId: 'p',
          order: 0,
          status: QuestStatus.done,
        ),
      );
      await seedQuest(quest(id: 'b', title: '待做子项', parentId: 'p', order: 1));

      await pump(tester, const QuestDetailPage(questId: 'p'));
      expect(find.text('待做子项'), findsOneWidget);
      expect(find.text('已做子项'), findsNothing, reason: '默认隐藏已了结');
      expect(find.textContaining('已了结 1'), findsOneWidget);

      await tester.tap(find.text('显示已了结'));
      await tester.pumpAndSettle();
      expect(find.text('已做子项'), findsOneWidget);
    });

    testWidgets('子项目可以降一级（挂到上一个同级下面）', (tester) async {
      await seedQuest(quest(id: 'p', title: '父任务'));
      await seedQuest(
        quest(id: 'a', title: '子项目A', parentId: 'p', order: 0),
      );
      await seedQuest(
        quest(id: 'b', title: '子项目B', parentId: 'p', order: 1),
      );
      await pump(tester, const QuestDetailPage(questId: 'p'));

      // 打开第二行（子项目B）的菜单
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('降一级'));
      await tester.pumpAndSettle();

      final json = await store.read('quest/quests/b.json');
      expect(Quest.fromJson(json!).parentId, 'a');
    });

    testWidgets('已完成约束：有未了结子项目时不能把父任务设为已完成', (tester) async {
      await seedQuest(quest(id: 'p', title: '父任务'));
      await seedQuest(quest(id: 'a', title: '子项目A', parentId: 'p'));
      await pump(tester, const QuestPage());

      // 总览卡片菜单里点「设为已完成」
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设为已完成'));
      await tester.pumpAndSettle();

      expect(find.textContaining('还有 1 个子项目没了结'), findsOneWidget);
      final json = await store.read('quest/quests/p.json');
      expect(Quest.fromJson(json!).status, QuestStatus.active);
    });
  });
}
