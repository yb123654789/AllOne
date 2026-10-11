import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/quest/quest_models.dart';
import 'package:allone/features/quest/quest_repository.dart';

import 'support/mem_store.dart';

/// 任务层级（子项目）与加权进度的测试。
///
/// 重点锁死三件事：
/// ① 父进度**不是**子项目的简单平均，而是按「工作量 / 已投入 / 里程碑」加权；
/// ② 递归穿透多层；
/// ③ 层级调整（升降级、移动）必须重排同级顺序、拒绝对子孙的移动。
void main() {
  Quest q(
    String id, {
    String parent = '',
    int order = 0,
    int manual = 0,
    List<Milestone> ms = const [],
    QuestStatus status = QuestStatus.active,
    bool archived = false,
  }) => Quest(
    id: id,
    title: id,
    parentId: parent,
    order: order,
    manualProgress: manual,
    milestones: ms,
    status: status,
    archived: archived,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: DateTime.parse('2026-01-02'),
  );

  Milestone m(String id, {bool done = false}) =>
      Milestone(id: id, title: id, done: done);

  InvestLog log(int minutes) => InvestLog(
    id: 'l$minutes',
    at: DateTime.parse('2026-01-05T10:00:00'),
    minutes: minutes,
  );

  group('QuestWeights', () {
    test('默认比例 0.5 : 0.3 : 0.2', () {
      const w = QuestWeights.defaults;
      expect(w.work, 0.5);
      expect(w.invest, 0.3);
      expect(w.milestone, 0.2);
    });

    test('归一化：和不为 1 时按比例缩放', () {
      const w = QuestWeights(work: 2, invest: 1, milestone: 1);
      final n = w.normalized();
      expect(n.work, closeTo(0.5, 1e-9));
      expect(n.invest, closeTo(0.25, 1e-9));
      expect(n.milestone, closeTo(0.25, 1e-9));
    });

    test('全 0 时回退默认（不会除零）', () {
      const w = QuestWeights(work: 0, invest: 0, milestone: 0);
      expect(w.isZero, isTrue);
      expect(w.normalized().work, 0.5);
    });

    test('fromJson 容错：缺失 / 类型不对 / 越界', () {
      expect(QuestWeights.fromJson(null).work, 0.5);
      expect(QuestWeights.fromJson('oops').work, 0.5);
      expect(QuestWeights.fromJson({'work': 'x'}).work, 0.5);
      expect(QuestWeights.fromJson({'work': 5}).work, 1.0);
      expect(QuestWeights.fromJson({'work': -3}).work, 0.0);
      expect(
        QuestWeights.fromJson({'work': 0.7, 'invest': 0.2, 'milestone': 0.1})
            .work,
        0.7,
      );
    });

    test('toJson / fromJson 往返', () {
      const w = QuestWeights(work: 0.4, invest: 0.4, milestone: 0.2);
      final back = QuestWeights.fromJson(w.toJson());
      expect(back.work, 0.4);
      expect(back.invest, 0.4);
      expect(back.milestone, 0.2);
    });
  });

  group('层级结构', () {
    test('childrenOf 按 order 排序，roots 只取顶层', () {
      final all = [
        q('b', order: 1),
        q('a', order: 0),
        q('a1', parent: 'a', order: 0),
        q('a2', parent: 'a', order: 1),
      ];
      expect(QuestLogic.roots(all).map((e) => e.id).toList(), ['a', 'b']);
      expect(
        QuestLogic.childrenOf(all, 'a').map((e) => e.id).toList(),
        ['a1', 'a2'],
      );
    });

    test('归档的任务不参与层级', () {
      final all = [q('a'), q('a1', parent: 'a', archived: true)];
      expect(QuestLogic.childrenOf(all, 'a'), isEmpty);
      expect(QuestLogic.hasChildren(all, 'a'), isFalse);
    });

    test('leafCount：子树最底层节点数（没有子项目 = 1）', () {
      final all = [
        q('a'),
        q('a1', parent: 'a'),
        q('a1x', parent: 'a1'),
        q('a1y', parent: 'a1'),
        q('a2', parent: 'a'),
      ];
      expect(QuestLogic.leafCount(all, 'a1'), 2); // a1x + a1y
      expect(QuestLogic.leafCount(all, 'a'), 3); // 2 + a2
      expect(QuestLogic.leafCount(all, 'a2'), 1);
    });

    test('descendants 递归收集全部后代', () {
      final all = [q('a'), q('a1', parent: 'a'), q('a1x', parent: 'a1')];
      expect(
        QuestLogic.descendants(all, 'a').map((e) => e.id).toSet(),
        {'a1', 'a1x'},
      );
    });

    test('depthOf：顶层 0，逐层 +1', () {
      final all = [q('a'), q('a1', parent: 'a'), q('a1x', parent: 'a1')];
      expect(QuestLogic.depthOf(all, 'a'), 0);
      expect(QuestLogic.depthOf(all, 'a1'), 1);
      expect(QuestLogic.depthOf(all, 'a1x'), 2);
    });

    test('subtreeMilestones / subtreeInvest 含自身与全部后代', () {
      final all = [
        q('a', ms: [m('m1')]),
        q('a1', parent: 'a', ms: [m('m2'), m('m3')]),
        q('a2', parent: 'a'),
      ];
      final logs = {
        'a': [log(30)],
        'a1': [log(60), log(10)],
        'a2': [log(5)],
      };
      expect(QuestLogic.subtreeMilestones(all, 'a'), 3);
      expect(QuestLogic.subtreeInvest(all, logs, 'a'), 105);
      expect(QuestLogic.subtreeInvest(all, logs, 'a1'), 70);
    });
  });

  group('加权进度（关键：不是简单平均）', () {
    test('没有子项目 → 用自身口径（里程碑 / 手动）', () {
      final all = [
        q('a', manual: 40),
        q('b', ms: [m('1', done: true), m('2')]),
      ];
      final p = QuestLogic.progressMap(all, const {});
      expect(p['a'], closeTo(0.4, 1e-9));
      expect(p['b'], closeTo(0.5, 1e-9));
    });

    test('「厚」的分支占比更大（工作量因子）', () {
      // P 下：A 有 3 个底层项目（全完成），B 是单个项目（未完成）
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0),
        q('A1', parent: 'A', manual: 100),
        q('A2', parent: 'A', manual: 100),
        q('A3', parent: 'A', manual: 100),
        q('B', parent: 'P', order: 1, manual: 0),
      ];
      final p = QuestLogic.progressMap(all, const {});
      expect(p['A'], 1.0);
      expect(p['B'], 0.0);
      // 简单平均会是 0.5；按工作量加权：A 权重 1、B 权重 1/3
      expect(p['P'], closeTo(0.75, 1e-9));
      expect(QuestLogic.leafCount(all, 'A'), 3);
    });

    test('已投入时间因子生效', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0, manual: 0),
        q('B', parent: 'P', order: 1, manual: 100),
      ];
      final logs = {
        'B': [log(100)],
      };
      // work 相同（各 1）；投入：A=0、B=100（归一化 0 / 1）
      // w(A)=0.5、w(B)=0.5+0.3=0.8 → P = (0*0.5 + 1*0.8) / 1.3
      final p = QuestLogic.progressMap(all, logs);
      expect(p['P'], closeTo(0.8 / 1.3, 1e-9));
    });

    test('里程碑数因子生效', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0, ms: [m('1', done: true), m('2')]),
        q('B', parent: 'P', order: 1, manual: 0),
      ];
      // work 相同；里程碑：A=2、B=0 → nm(A)=1, nm(B)=0
      // w(A)=0.5+0.2=0.7、w(B)=0.5 → p(A)=0.5 → P = 0.35/1.2
      final p = QuestLogic.progressMap(all, const {});
      expect(p['A'], closeTo(0.5, 1e-9));
      expect(p['P'], closeTo(0.35 / 1.2, 1e-9));
    });

    test('递归穿透多层', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0),
        q('A1', parent: 'A', order: 0, manual: 50),
      ];
      final p = QuestLogic.progressMap(all, const {});
      expect(p['A1'], closeTo(0.5, 1e-9));
      expect(p['A'], closeTo(0.5, 1e-9));
      expect(p['P'], closeTo(0.5, 1e-9));
    });

    test('权重比例可调：把工作量设为 0、投入设为 1 → 只剩投入起作用', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0, manual: 0),
        q('B', parent: 'P', order: 1, manual: 100),
      ];
      final logs = {
        'B': [log(10)],
      };
      const w = QuestWeights(work: 0, invest: 1, milestone: 0);
      // w(A)=0、w(B)=1 → P = 1.0
      expect(QuestLogic.progressMap(all, logs, w)['P'], closeTo(1.0, 1e-9));
    });

    test('三个因子全失效时等权回退（不会算出 NaN / 0）', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0, manual: 100),
        q('B', parent: 'P', order: 1, manual: 0),
      ];
      // work 权重 0；没有投入也没有里程碑 → maxInvest = maxMs = 0 → 权重全 0
      const w = QuestWeights(work: 0, invest: 1, milestone: 0);
      final p = QuestLogic.progressMap(all, const {}, w)['P'];
      expect(p, closeTo(0.5, 1e-9), reason: '回退等权平均');
    });

    test('归档的子项目不参与父进度', () {
      final all = [
        q('P'),
        q('A', parent: 'P', order: 0, manual: 100),
        q('B', parent: 'P', order: 1, manual: 0, archived: true),
      ];
      expect(QuestLogic.progressMap(all, const {})['P'], closeTo(1.0, 1e-9));
    });
  });

  group('移动合法性 / 完成阻碍', () {
    test('canMoveTo 阻止移到自己或自己的子孙下面', () {
      final all = [q('A'), q('A1', parent: 'A'), q('A1x', parent: 'A1')];
      expect(QuestLogic.canMoveTo(all, 'A', 'A'), isFalse);
      expect(QuestLogic.canMoveTo(all, 'A', 'A1'), isFalse);
      expect(QuestLogic.canMoveTo(all, 'A', 'A1x'), isFalse);
      expect(QuestLogic.canMoveTo(all, 'A1', 'A'), isTrue);
      expect(QuestLogic.canMoveTo(all, 'A1x', 'A'), isTrue);
      expect(QuestLogic.canMoveTo(all, 'A', ''), isTrue);
    });

    test('blockersForDone：未了结的子项目才算阻碍（已放弃不算）', () {
      final all = [
        q('P'),
        q('a', parent: 'P', status: QuestStatus.done),
        q('b', parent: 'P'),
        q('c', parent: 'P', status: QuestStatus.dropped),
      ];
      expect(
        QuestLogic.blockersForDone(all, 'P').map((e) => e.id).toList(),
        ['b'],
      );
      final all2 = [
        q('P'),
        q('a', parent: 'P', status: QuestStatus.done),
        q('b', parent: 'P', status: QuestStatus.dropped),
      ];
      expect(QuestLogic.blockersForDone(all2, 'P'), isEmpty);
    });
  });

  group('层级操作（落盘）', () {
    late MemStore store;
    late ProviderContainer container;

    setUp(() {
      store = MemStore();
      container = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
      );
    });
    tearDown(() => container.dispose());

    QuestListNotifier n() => container.read(questListProvider.notifier);

    Future<void> seed(List<Quest> list) async {
      for (final x in list) {
        await store.write('quest/quests/${x.id}.json', x.toJson());
      }
    }

    Future<List<Quest>> loaded() async {
      final files = await store.listFiles('quest/quests');
      final out = <Quest>[];
      for (final f in files) {
        out.add(Quest.fromJson((await store.read('quest/quests/$f'))!));
      }
      return out;
    }

    Future<Quest> one(String id) async =>
        Quest.fromJson((await store.read('quest/quests/$id.json'))!);

    test('降一级：挂到上一个同级任务下，并重排 order', () async {
      await seed([q('a', order: 0), q('b', order: 1), q('c', order: 2)]);
      final err = await n().indent('b');
      expect(err, isNull);
      expect((await one('b')).parentId, 'a');
      final all = await loaded();
      expect(QuestLogic.childrenOf(all, '').map((e) => e.id).toList(), [
        'a',
        'c',
      ]);
      expect(
        QuestLogic.childrenOf(all, 'a').map((e) => e.id).toList(),
        ['b'],
      );
    });

    test('降一级：第一个同级没有上一个兄弟时给出提示', () async {
      await seed([q('a', order: 0), q('b', order: 1)]);
      final err = await n().indent('a');
      expect(err, isNotNull);
      expect((await one('a')).parentId, '');
    });

    test('升一级：成为父任务的下一个同级；再升一次回到顶层', () async {
      await seed([
        q('p', order: 0),
        q('x', parent: 'p', order: 0),
        q('y', parent: 'p', order: 1),
      ]);
      expect(await n().outdent('x'), isNull);
      var all = await loaded();
      expect((await one('x')).parentId, '');
      expect(QuestLogic.childrenOf(all, '').map((e) => e.id).toList(), [
        'p',
        'x',
      ]);

      // 已经在顶层了，再升会被拒绝
      expect(await n().outdent('x'), isNotNull);
      all = await loaded();
      expect((await one('x')).parentId, '');
      expect(QuestLogic.childrenOf(all, '').map((e) => e.id).toList(), [
        'p',
        'x',
      ]);
    });

    test('升一级：已经在顶层时给出提示', () async {
      await seed([q('a')]);
      expect(await n().outdent('a'), isNotNull);
    });

    test('同级上移 / 下移，到边界时静默不做', () async {
      await seed([q('a', order: 0), q('b', order: 1), q('c', order: 2)]);
      expect(await n().moveSibling('c', -1), isNull);
      var all = await loaded();
      expect(QuestLogic.childrenOf(all, '').map((e) => e.id).toList(), [
        'a',
        'c',
        'b',
      ]);

      expect(await n().moveSibling('a', -1), isNull); // 已经在最前
      all = await loaded();
      expect(QuestLogic.childrenOf(all, '').first.id, 'a');
    });

    test('移动到指定父任务 / 移回顶层', () async {
      await seed([q('p1'), q('p2'), q('x', parent: 'p1')]);
      expect(await n().moveTo('x', 'p2'), isNull);
      expect((await one('x')).parentId, 'p2');

      expect(await n().moveTo('x', ''), isNull);
      expect((await one('x')).parentId, '');
    });

    test('移动到自己的子孙下面被拒绝（防止成环）', () async {
      await seed([q('a'), q('a1', parent: 'a')]);
      final err = await n().moveTo('a', 'a1');
      expect(err, isNotNull);
      expect((await one('a')).parentId, '');
    });

    test('新建子项目：继承父分类、order 递增', () async {
      await seed([
        Quest(
          id: 'p',
          title: '父',
          category: '学习',
          createdAt: DateTime.parse('2026-01-01'),
          updatedAt: DateTime.parse('2026-01-02'),
        ),
      ]);
      final c1 = await n().createChild('p', title: '子一');
      final c2 = await n().createChild('p', title: '子二');
      expect(c1.parentId, 'p');
      expect(c1.category, '学习');
      expect(c1.order, 0);
      expect(c2.order, 1);
    });
  });

  group('完成与删除约束', () {
    late MemStore store;
    late ProviderContainer container;

    setUp(() {
      store = MemStore();
      container = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
      );
    });
    tearDown(() => container.dispose());

    QuestListNotifier n() => container.read(questListProvider.notifier);

    Future<void> seed(List<Quest> list) async {
      for (final x in list) {
        await store.write('quest/quests/${x.id}.json', x.toJson());
      }
    }

    Future<Quest> one(String id) async =>
        Quest.fromJson((await store.read('quest/quests/$id.json'))!);

    test('还有未了结的子项目时，不允许把父任务设为已完成', () async {
      await seed([
        q('p'),
        q('a', parent: 'p'),
        q('b', parent: 'p', status: QuestStatus.done),
      ]);
      final err = await n().setStatus('p', QuestStatus.done);
      expect(err, isNotNull);
      expect(err, contains('子项目'));
      expect((await one('p')).status, QuestStatus.active, reason: '状态不能变');
    });

    test('子项目全部完成或放弃后，可以完成父任务', () async {
      await seed([
        q('p'),
        q('a', parent: 'p', status: QuestStatus.done),
        q('b', parent: 'p', status: QuestStatus.dropped),
      ]);
      expect(await n().setStatus('p', QuestStatus.done), isNull);
      expect((await one('p')).status, QuestStatus.done);
    });

    test('没有子项目时可以直接完成', () async {
      await seed([q('p')]);
      expect(await n().setStatus('p', QuestStatus.done), isNull);
    });

    test('暂停 / 放弃 / 恢复进行中不受子项目限制', () async {
      await seed([q('p'), q('a', parent: 'p')]);
      expect(await n().setStatus('p', QuestStatus.paused), isNull);
      expect(await n().setStatus('p', QuestStatus.dropped), isNull);
      expect(await n().setStatus('p', QuestStatus.active), isNull);
    });

    test('有子项目时禁止归档', () async {
      await seed([q('p'), q('a', parent: 'p')]);
      final err = await n().archive('p');
      expect(err, isNotNull);
      expect((await one('p')).archived, isFalse);
    });

    test('有子项目时禁止彻底删除（子项目不会被悄悄带走）', () async {
      await seed([q('p'), q('a', parent: 'p')]);
      expect(await n().delete('p'), isNotNull);
      expect(await store.read('quest/quests/p.json'), isNotNull);
      expect(await store.read('quest/quests/a.json'), isNotNull);
    });

    test('子项目处理掉之后，父任务可以归档与删除', () async {
      await seed([q('p')]);
      expect(await n().archive('p'), isNull);
      expect((await one('p')).archived, isTrue);
      expect(await n().delete('p'), isNull);
      expect(await store.read('quest/quests/p.json'), isNull);
    });
  });
}
