import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/features/quest/quest_models.dart';

/// 任务模块纯逻辑测试：进度口径、停滞判定、目标倒数、投入统计、排序。
void main() {
  // 固定锚点：2026-10-12 是周一
  final monday = DateTime.parse('2026-10-12');
  String day(int offset) => AppTime.dateOnly(monday.add(Duration(days: offset)));
  final today = day(0);

  Quest quest({
    String id = 'q1',
    String title = '写一本书',
    QuestStatus status = QuestStatus.active,
    String targetDate = '',
    int manualProgress = 0,
    bool pinned = false,
    String pinnedAt = '',
    List<Milestone> milestones = const [],
    List<String> todoIds = const [],
    bool archived = false,
    DateTime? updatedAt,
  }) => Quest(
    id: id,
    title: title,
    status: status,
    targetDate: targetDate,
    manualProgress: manualProgress,
    pinned: pinned,
    pinnedAt: pinnedAt,
    milestones: milestones,
    todoIds: todoIds,
    archived: archived,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: updatedAt ?? DateTime.parse('${day(0)}T10:00:00'),
  );

  Milestone ms(String id, {bool done = false}) =>
      Milestone(id: id, title: '阶段$id', done: done, doneAt: done ? day(0) : '');

  InvestLog log(DateTime at, int minutes) =>
      InvestLog(id: 'l${at.millisecondsSinceEpoch}', at: at, minutes: minutes);

  group('任务 - 进度口径', () {
    test('没有里程碑：用手动百分比', () {
      final q = quest(manualProgress: 40);
      expect(q.usesMilestones, isFalse);
      expect(q.progress, closeTo(0.4, 1e-9));
      expect(q.progressLabel, '手动 40%');
    });

    test('有里程碑：进度由里程碑算，手动值被忽略', () {
      final q = quest(
        manualProgress: 100, // 手动给满也没用
        milestones: [ms('a', done: true), ms('b'), ms('c')],
      );
      expect(q.usesMilestones, isTrue);
      expect(q.milestoneDone, 1);
      expect(q.milestoneTotal, 3);
      expect(q.progress, closeTo(1 / 3, 1e-9));
      expect(q.progressLabel, '里程碑 1/3');
    });

    test('手动进度越界（-10 / 150）被夹到 0~100', () {
      expect(quest(manualProgress: -10).progress, 0);
      expect(quest(manualProgress: 150).progress, 1);
    });
  });

  group('任务 - 停滞判定', () {
    test('很久没更新且没有投入 → 停滞', () {
      final q = quest(updatedAt: DateTime.parse('${day(-20)}T09:00:00'));
      expect(QuestLogic.stalledDays(q, const [], today: today), 20);
      expect(QuestLogic.isStalled(q, const [], today: today), isTrue);
    });

    test('最近有投入 → 不算停滞（投入也算活动）', () {
      final q = quest(updatedAt: DateTime.parse('${day(-30)}T09:00:00'));
      final logs = [log(DateTime.parse('${day(-2)}T20:00:00'), 60)];
      expect(QuestLogic.stalledDays(q, logs, today: today), 2);
      expect(QuestLogic.isStalled(q, logs, today: today), isFalse);
    });

    test('阈值边界：13 天不算、14 天算', () {
      final q13 = quest(updatedAt: DateTime.parse('${day(-13)}T09:00:00'));
      final q14 = quest(updatedAt: DateTime.parse('${day(-14)}T09:00:00'));
      expect(QuestLogic.isStalled(q13, const [], today: today), isFalse);
      expect(QuestLogic.isStalled(q14, const [], today: today), isTrue);
    });

    test('已完成 / 已放弃 / 回收站里的任务不再提醒停滞', () {
      final old = DateTime.parse('${day(-60)}T09:00:00');
      expect(
        QuestLogic.isStalled(
          quest(status: QuestStatus.done, updatedAt: old),
          const [],
          today: today,
        ),
        isFalse,
      );
      expect(
        QuestLogic.isStalled(
          quest(status: QuestStatus.dropped, updatedAt: old),
          const [],
          today: today,
        ),
        isFalse,
      );
      expect(
        QuestLogic.isStalled(
          quest(archived: true, updatedAt: old),
          const [],
          today: today,
        ),
        isFalse,
      );
      // 暂停的仍然提醒（暂停只是慢下来，不是不做了）
      expect(
        QuestLogic.isStalled(
          quest(status: QuestStatus.paused, updatedAt: old),
          const [],
          today: today,
        ),
        isTrue,
      );
    });
  });

  group('任务 - 目标日期', () {
    test('无期限', () {
      expect(QuestLogic.targetLabel(quest(), today), '长期 · 无期限');
    });

    test('今天 / 未来 / 已超期', () {
      expect(QuestLogic.targetLabel(quest(targetDate: today), today), '目标日期：今天');
      expect(
        QuestLogic.targetLabel(quest(targetDate: day(30)), today),
        '距目标 30 天',
      );
      expect(
        QuestLogic.targetLabel(quest(targetDate: day(-5)), today),
        '已超期 5 天',
      );
    });

    test('超期只对还在推进的任务告警', () {
      expect(QuestLogic.isOverdue(quest(targetDate: day(-5)), today), isTrue);
      expect(
        QuestLogic.isOverdue(
          quest(targetDate: day(-5), status: QuestStatus.done),
          today,
        ),
        isFalse,
      );
      expect(QuestLogic.isOverdue(quest(targetDate: today), today), isFalse);
    });
  });

  group('任务 - 投入统计', () {
    test('合计与文案', () {
      final logs = [
        log(DateTime.parse('${day(-1)}T10:00:00'), 30),
        log(DateTime.parse('${day(0)}T10:00:00'), 60),
      ];
      expect(QuestLogic.totalMinutes(logs), 90);
      expect(QuestLogic.minutesLabel(90), '1 小时 30 分');
      expect(QuestLogic.minutesLabel(60), '1 小时');
      expect(QuestLogic.minutesLabel(45), '45 分');
      expect(QuestLogic.minutesLabel(0), '0 分');
    });

    test('近 12 周分周统计：本周落最后一格、上周落倒数第二格', () {
      final logs = [
        log(DateTime.parse('${day(0)}T10:00:00'), 60), // 本周一
        log(DateTime.parse('${day(-1)}T10:00:00'), 30), // 上周日 → 上一格
        log(DateTime.parse('${day(-7)}T10:00:00'), 45), // 上周一 → 上一格
      ];
      final weeks = QuestLogic.weeklyMinutes(logs, today: today, weeks: 12);
      expect(weeks.length, 12);
      expect(weeks[11], 60, reason: '本周');
      expect(weeks[10], 75, reason: '上周（周日 30 + 周一 45）');
    });

    test('窗口之外的投入不计数', () {
      final logs = [log(DateTime.parse('${day(-7 * 15)}T10:00:00'), 600)];
      final weeks = QuestLogic.weeklyMinutes(logs, today: today, weeks: 12);
      expect(weeks.every((v) => v == 0), isTrue);
    });

    test('最后一次投入时间', () {
      final logs = [
        log(DateTime.parse('${day(-3)}T10:00:00'), 10),
        log(DateTime.parse('${day(-1)}T10:00:00'), 10),
      ];
      expect(QuestLogic.lastInvestAt(logs)!.day, monday.subtract(const Duration(days: 1)).day);
    });
  });

  group('任务 - 总览排序', () {
    test('钉住的排最前，钉住之间按钉住时间倒序', () {
      final list = [
        quest(id: 'a'),
        quest(id: 'b', pinned: true, pinnedAt: '2026-10-01T10:00:00'),
        quest(id: 'c', pinned: true, pinnedAt: '2026-10-05T10:00:00'),
      ];
      expect(QuestLogic.sorted(list).map((q) => q.id).toList(), ['c', 'b', 'a']);
    });

    test('其余按状态：进行中 → 暂停 → 已完成 → 放弃', () {
      final list = [
        quest(id: 'done', status: QuestStatus.done),
        quest(id: 'active', status: QuestStatus.active),
        quest(id: 'dropped', status: QuestStatus.dropped),
        quest(id: 'paused', status: QuestStatus.paused),
      ];
      expect(
        QuestLogic.sorted(list).map((q) => q.id).toList(),
        ['active', 'paused', 'done', 'dropped'],
      );
    });

    test('同状态按目标日期（无期限的排后面）', () {
      final list = [
        quest(id: 'none'),
        quest(id: 'later', targetDate: day(60)),
        quest(id: 'sooner', targetDate: day(10)),
      ];
      expect(
        QuestLogic.sorted(list).map((q) => q.id).toList(),
        ['sooner', 'later', 'none'],
      );
    });
  });

  group('任务 - JSON', () {
    test('往返（含里程碑、关联待办、钉住）', () {
      final q = quest(
        targetDate: day(30),
        pinned: true,
        pinnedAt: '2026-10-01T10:00:00',
        milestones: [ms('a', done: true), ms('b')],
        todoIds: ['t1', 't2'],
      );
      final back = Quest.fromJson(q.toJson());
      expect(back.id, q.id);
      expect(back.title, q.title);
      expect(back.status, q.status);
      expect(back.targetDate, q.targetDate);
      expect(back.pinned, isTrue);
      expect(back.pinnedAt, q.pinnedAt);
      expect(back.milestones.length, 2);
      expect(back.milestones.first.done, isTrue);
      expect(back.todoIds, ['t1', 't2']);
      expect(back.progress, closeTo(0.5, 1e-9));
    });

    test('旧数据 / 缺字段容错', () {
      final back = Quest.fromJson(const {
        'id': 'x',
        'title': '旧任务',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(back.status, QuestStatus.active);
      expect(back.category, '未分类');
      expect(back.milestones, isEmpty);
      expect(back.todoIds, isEmpty);
      expect(back.pinned, isFalse);
      expect(back.archived, isFalse);
      expect(back.progress, 0);
    });

    test('未知状态名回退为进行中', () {
      final back = Quest.fromJson(const {
        'id': 'x',
        'title': 't',
        'status': 'unknown-status',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(back.status, QuestStatus.active);
    });
  });

  group('任务 - 状态与回收站', () {
    test('isLive：进行中 / 暂停算在推进，完成 / 放弃 / 回收站不算', () {
      expect(quest().isLive, isTrue);
      expect(quest(status: QuestStatus.paused).isLive, isTrue);
      expect(quest(status: QuestStatus.done).isLive, isFalse);
      expect(quest(status: QuestStatus.dropped).isLive, isFalse);
      expect(quest(archived: true).isLive, isFalse);
    });

    test('状态文案', () {
      expect(quest().statusLabel, '进行中');
      expect(quest(status: QuestStatus.paused).statusLabel, '暂停');
      expect(quest(status: QuestStatus.done).statusLabel, '已完成');
      expect(quest(status: QuestStatus.dropped).statusLabel, '已放弃');
    });
  });
}
