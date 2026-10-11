import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/quest/quest_repository.dart';

import 'support/mem_store.dart';

/// 任务仓库层测试：落盘、局部修改不互相覆盖、里程碑、钉住、关联待办、
/// 回收站、投入记录。写操作都从磁盘读，这里逐条钉死。
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

  Quest quest({String id = 'q1', String title = '写一本书'}) => Quest(
    id: id,
    title: title,
    vision: '把想法写清楚',
    category: '学习',
    targetDate: '2027-06-30',
    manualProgress: 20,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: DateTime.parse('2026-01-02'),
  );

  QuestListNotifier quests() => container.read(questListProvider.notifier);
  InvestLogNotifier investLogs() =>
      container.read(questLogProvider.notifier);

  Future<void> seed(Quest q) =>
      store.write('quest/quests/${q.id}.json', q.toJson());

  Future<Quest> reload(String id) async {
    final json = await store.read('quest/quests/$id.json');
    return Quest.fromJson(json!);
  }

  Future<List<InvestLog>> logs(String id) async {
    final list = await store.readList('quest/logs/$id.json');
    return list.map(InvestLog.fromJson).toList();
  }

  test('新建保存后能读回', () async {
    await quests().save(quest());
    expect((await reload('q1')).title, '写一本书');
  });

  test('连续两次修改不会互相覆盖（关键回归）', () async {
    await seed(quest());
    // 不先读 provider，直接连续操作 —— 模拟用户连点
    await quests().addMilestone('q1', '阶段一');
    await quests().addMilestone('q1', '阶段二');
    final q = await reload('q1');
    expect(q.milestones.length, 2, reason: '第二次必须看到第一次的结果');
    expect(q.milestones.map((m) => m.title).toList(), ['阶段一', '阶段二']);
    // 其它字段不能被冲掉
    expect(q.category, '学习');
    expect(q.targetDate, '2027-06-30');
  });

  test('局部修改只动目标字段', () async {
    await seed(quest());
    await quests().setStatus('q1', QuestStatus.paused);
    final q = await reload('q1');
    expect(q.status, QuestStatus.paused);
    expect(q.title, '写一本书');
    expect(q.manualProgress, 20);
  });

  test('里程碑：勾选记录完成日期，取消则清空', () async {
    await seed(quest());
    await quests().addMilestone('q1', '第一版', dueDate: '2026-12-31');
    final id = (await reload('q1')).milestones.single.id;

    await quests().toggleMilestone('q1', id);
    var q = await reload('q1');
    expect(q.milestones.single.done, isTrue);
    expect(q.milestones.single.doneAt.isNotEmpty, isTrue);
    expect(q.progress, 1.0, reason: '唯一里程碑完成后进度应为 100%');

    await quests().toggleMilestone('q1', id);
    q = await reload('q1');
    expect(q.milestones.single.done, isFalse);
    expect(q.milestones.single.doneAt, isEmpty);
    // 里程碑还在（只是未完成），所以进度按里程碑算 = 0，
    // 不会回退到手动百分比 —— 这是「有里程碑就以里程碑为准」的口径
    expect(q.usesMilestones, isTrue);
    expect(q.progress, 0.0);
  });

  test('里程碑可改名 / 删改', () async {
    await seed(quest());
    await quests().addMilestone('q1', '草稿');
    final m = (await reload('q1')).milestones.single;
    await quests().updateMilestone('q1', m.copyWith(title: '初稿'));
    expect((await reload('q1')).milestones.single.title, '初稿');
    await quests().removeMilestone('q1', m.id);
    expect((await reload('q1')).milestones, isEmpty);
  });

  test('钉住 / 取消钉住（取消时清掉钉住时间）', () async {
    await seed(quest());
    await quests().togglePin('q1');
    var q = await reload('q1');
    expect(q.pinned, isTrue);
    expect(q.pinnedAt.isNotEmpty, isTrue);

    await quests().togglePin('q1');
    q = await reload('q1');
    expect(q.pinned, isFalse);
    expect(q.pinnedAt, isEmpty);
  });

  test('关联待办：去重、可解除', () async {
    await seed(quest());
    await quests().linkTodo('q1', 't1');
    await quests().linkTodo('q1', 't1'); // 重复关联应被忽略
    await quests().linkTodo('q1', 't2');
    expect((await reload('q1')).todoIds, ['t1', 't2']);

    await quests().unlinkTodo('q1', 't1');
    expect((await reload('q1')).todoIds, ['t2']);
  });

  test('归档：进回收站并取消钉住；恢复后回到正常', () async {
    await seed(quest());
    await quests().togglePin('q1');
    await quests().archive('q1');
    var q = await reload('q1');
    expect(q.archived, isTrue);
    expect(q.archivedAt.isNotEmpty, isTrue);
    expect(q.pinned, isFalse, reason: '进回收站的任务不该再钉在重心上');

    await quests().restore('q1');
    q = await reload('q1');
    expect(q.archived, isFalse);
    expect(q.archivedAt, isEmpty);
  });

  test('彻底删除：任务、投入记录、附件目录一起清掉', () async {
    await seed(quest());
    await investLogs().append('q1', minutes: 30);
    await store.write('quest/quests/q1/media/pic.jpg', {'x': 1});

    await quests().delete('q1');

    expect(await store.read('quest/quests/q1.json'), isNull);
    expect(await store.readList('quest/logs/q1.json'), isEmpty);
    expect(await store.read('quest/quests/q1/media/pic.jpg'), isNull);
  });

  group('投入记录', () {
    test('连续记两笔不会丢（关键回归）', () async {
      await seed(quest());
      await investLogs().append('q1', minutes: 30, note: '写大纲');
      await investLogs().append('q1', minutes: 45, note: '写第一章');
      final list = await logs('q1');
      expect(list.length, 2);
      expect(QuestLogic.totalMinutes(list), 75);
      expect(list.first.note, '写大纲');
    });

    test('可删除单条', () async {
      await seed(quest());
      await investLogs().append('q1', minutes: 30);
      await investLogs().append('q1', minutes: 60);
      final list = await logs('q1');
      await investLogs().remove('q1', list.first.id);
      final after = await logs('q1');
      expect(after.length, 1);
      expect(after.single.minutes, 60);
    });

    test('负数分钟按 0 处理（不污染合计）', () async {
      await seed(quest());
      await investLogs().append('q1', minutes: -10);
      final list = await logs('q1');
      expect(list.single.minutes, 0);
      expect(QuestLogic.totalMinutes(list), 0);
    });

    test('投入会让「停滞」重新计算', () async {
      await seed(quest());
      final q = await reload('q1');
      final before = QuestLogic.stalledDays(q, const [], today: '2026-03-01');
      await investLogs().append(
        'q1',
        minutes: 20,
        at: DateTime.parse('2026-02-28T10:00:00'),
      );
      final after = QuestLogic.stalledDays(q, await logs('q1'), today: '2026-03-01');
      expect(after, lessThan(before));
      expect(after, 1);
    });
  });

  test('数据没加载就写，不会把已有任务覆盖掉', () async {
    await seed(quest());
    await seed(quest(id: 'q2', title: '第二个任务'));
    // 故意不读 provider，直接改 q1
    await quests().setStatus('q1', QuestStatus.done);
    expect(await store.read('quest/quests/q2.json'), isNotNull);
    expect((await reload('q2')).title, '第二个任务');
    expect((await reload('q1')).status, QuestStatus.done);
  });
}
