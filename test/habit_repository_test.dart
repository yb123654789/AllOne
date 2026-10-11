import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/habit/habit_repository.dart';

import 'support/mem_store.dart';

/// 习惯仓库层测试：
/// ①打卡累加与「未加载就写」的防护；②批量补打卡 / 标记未完成 / 清除记录
/// 都要**写文件并留审计日志**（含改前值与原因）；③删除习惯要清干净。
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

  Habit habit({
    String id = 'h1',
    HabitDailyTarget target = HabitDailyTarget.quantity,
    int targetValue = 8,
  }) => Habit(
    id: id,
    title: '喝水',
    dailyTarget: target,
    dailyTargetValue: targetValue,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: DateTime.parse('2026-01-01'),
  );

  Future<void> seedHabit(Habit h) =>
      store.write('habit/habits/${h.id}.json', h.toJson());

  Future<Map<String, dynamic>> checkins(String id) async =>
      (await store.read('habit/checkins/$id.json')) ?? <String, dynamic>{};

  Future<List<Map<String, dynamic>>> logs(String id) =>
      store.readList('habit/logs/$id.json');

  HabitCheckinNotifier notifier() =>
      container.read(habitCheckinProvider.notifier);

  test('打卡累加；「数据还没加载就打卡」不会清空历史', () async {
    await seedHabit(habit());
    // 预置历史打卡（模拟上次使用留下的记录）
    await store.write('habit/checkins/h1.json', {
      '2026-10-01': 2,
      '2026-10-02': 3,
    });
    // 故意**不先读 provider**：这正是「刚打开 App 立刻点打卡」的危险场景
    await notifier().checkin('h1', '2026-10-11', amount: 1);

    final json = await checkins('h1');
    expect(json['2026-10-01'], 2, reason: '历史记录不能被覆盖掉');
    expect(json['2026-10-02'], 3);
    expect(json['2026-10-11'], 1);
  });

  test('多次打卡累加（当天 3 + 2 = 5）', () async {
    await seedHabit(habit());
    await notifier().checkin('h1', '2026-10-11', amount: 3);
    await notifier().checkin('h1', '2026-10-11', amount: 2);
    expect((await checkins('h1'))['2026-10-11'], 5);
  });

  test('批量补打卡：写文件 + 留日志（改前值与原因）', () async {
    await seedHabit(habit());
    await store.write('habit/checkins/h1.json', {'2026-10-01': -1});
    await container.read(habitCheckinProvider.future);

    final n = await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-01', '2026-10-02'],
      action: HabitEditAction.checkin,
      reason: '那两天做了但忘了打卡',
      amount: 1,
    );
    expect(n, 2);

    final json = await checkins('h1');
    expect(json['2026-10-01'], 1, reason: '原来标记未完成（-1），补打卡后应为 1');
    expect(json['2026-10-02'], 1);

    final list = await logs('h1');
    expect(list.length, 1);
    expect(list.single['action'], 'checkin');
    expect(list.single['reason'], '那两天做了但忘了打卡');
    expect(list.single['dates'], ['2026-10-01', '2026-10-02']);
    expect(list.single['amount'], 1);
    final before = (list.single['before'] as Map).cast<String, dynamic>();
    expect(before['2026-10-01'], -1);
    expect(before['2026-10-02'], 0, reason: '原本没有记录应记为 0');
  });

  test('标记未完成 / 清除记录：都会留日志', () async {
    await seedHabit(habit());
    await store.write('habit/checkins/h1.json', {'2026-10-01': 5});
    await container.read(habitCheckinProvider.future);

    await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-01'],
      action: HabitEditAction.markUndone,
      reason: '那天其实没做',
    );
    expect((await checkins('h1'))['2026-10-01'], -1);

    await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-01'],
      action: HabitEditAction.clear,
      reason: '记错了，删掉',
    );
    expect((await checkins('h1')).containsKey('2026-10-01'), isFalse);

    final list = await logs('h1');
    expect(list.length, 2);
    expect(list[0]['action'], 'markUndone');
    expect(list[1]['action'], 'clear');
    expect(list[1]['reason'], '记错了，删掉');
  });

  test('幂等：清除本来就没记录的天 → 不改动、不写日志', () async {
    await seedHabit(habit());
    await container.read(habitCheckinProvider.future);
    final n = await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-05'],
      action: HabitEditAction.clear,
      reason: '本来就空',
    );
    expect(n, 0);
    expect(await logs('h1'), isEmpty);
  });

  test('多次批量修改：日志按时间顺序累积（可回看全部改动）', () async {
    await seedHabit(habit());
    await container.read(habitCheckinProvider.future);
    await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-01'],
      action: HabitEditAction.checkin,
      reason: '第一次补',
      amount: 2,
    );
    await notifier().applyEdit(
      habitId: 'h1',
      dates: ['2026-10-02'],
      action: HabitEditAction.checkin,
      reason: '第二次补',
      amount: 3,
    );
    final list = await logs('h1');
    expect(list.length, 2);
    expect(list[0]['reason'], '第一次补');
    expect(list[1]['reason'], '第二次补');
    final json = await checkins('h1');
    expect(json['2026-10-01'], 2);
    expect(json['2026-10-02'], 3);
  });

  test('删除习惯：打卡文件、修改记录、附件目录一并清掉', () async {
    await seedHabit(habit());
    await store.write('habit/checkins/h1.json', {'2026-10-01': 1});
    await store.writeList('habit/logs/h1.json', [
      {
        'id': 'log1',
        'at': '2026-10-02T10:00:00.000',
        'action': 'checkin',
        'dates': ['2026-10-01'],
        'amount': 1,
        'before': {'2026-10-01': 0},
        'reason': '补',
      },
    ]);
    await store.write('habit/habits/h1/media/pic.jpg', {'x': 1});

    await container.read(habitListProvider.notifier).deleteHabit('h1');

    expect(await store.read('habit/habits/h1.json'), isNull);
    expect(await store.read('habit/checkins/h1.json'), isNull);
    expect(await store.readList('habit/logs/h1.json'), isEmpty);
    expect(await store.read('habit/habits/h1/media/pic.jpg'), isNull);
  });
}
