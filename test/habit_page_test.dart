import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/core/widgets/heat_map.dart';
import 'package:allone/features/habit/habit_detail_page.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/habit/habit_page.dart';

import 'support/mem_store.dart';

/// 习惯页 / 详情页的界面接线测试。
///
/// **需求核心回归**：设了「每天累计 8 次」的习惯，打 1 次只能显示进度
/// （打卡 1/8），**绝不能显示「已完成」** —— 以前用 `isDone`（有记录即完成）
/// 所以打一次就变绿勾。
///
/// 用内存存储（[MemStore]）：widget 测试的假时钟不会推进 dart:io，
/// 用真实文件会让页面永远停在 loading。
void main() {
  late MemStore store;
  final today = AppTime.dateOnly(DateTime.now());

  setUp(() => store = MemStore());

  Habit habit({
    String id = 'h1',
    HabitDailyTarget target = HabitDailyTarget.quantity,
    int targetValue = 8,
    HabitFrequency frequency = HabitFrequency.daily,
    int weeklyTimes = 3,
  }) => Habit(
    id: id,
    title: '喝水',
    frequency: frequency,
    weeklyTimes: weeklyTimes,
    dailyTarget: target,
    dailyTargetValue: targetValue,
    createdAt: DateTime.parse('2026-01-01'),
    updatedAt: DateTime.parse('2026-01-01'),
  );

  Future<void> seedHabit(Habit h) =>
      store.write('habit/habits/${h.id}.json', h.toJson());

  Future<void> seedCheckins(String id, Map<String, int> entries) =>
      store.write('habit/checkins/$id.json', entries);

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

  group('习惯卡片 - 完成判定', () {
    testWidgets('「每天累计 8 次」打 1 次：显示打卡 1/8，不显示已完成', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {today: 1});
      await pump(tester, const HabitPage());

      expect(find.text('打卡 1/8'), findsOneWidget);
      expect(find.text('今日 1/8 次'), findsOneWidget);
      // 这一条就是本次需求的核心：没满目标不能说「已完成」
      expect(find.text('已完成'), findsNothing);
    });

    testWidgets('打满 8 次才显示「已完成」', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {today: 8});
      await pump(tester, const HabitPage());

      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('打卡 8/8'), findsNothing);
      expect(find.text('今日 8/8 次·已完成'), findsOneWidget);
    });

    testWidgets('超出目标（12/8）仍算已完成', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {today: 12});
      await pump(tester, const HabitPage());

      expect(find.text('已完成'), findsOneWidget);
    });

    testWidgets('分钟型：20/30 分钟只算未完成', (tester) async {
      await seedHabit(habit(target: HabitDailyTarget.minutes, targetValue: 30));
      await seedCheckins('h1', {today: 20});
      await pump(tester, const HabitPage());

      expect(find.text('打卡 20/30'), findsOneWidget);
      expect(find.text('今日 20/30 分钟'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
    });

    testWidgets('一次即完成型：打卡后就是已完成', (tester) async {
      await seedHabit(habit(target: HabitDailyTarget.once));
      await seedCheckins('h1', {today: 1});
      await pump(tester, const HabitPage());

      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('今天已完成'), findsOneWidget);
    });

    testWidgets('主动标记未完成 → 按钮显示「未完成」', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {today: -1});
      await pump(tester, const HabitPage());

      expect(find.text('未完成'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
    });

    testWidgets('每周 N 次：卡片显示本周进度', (tester) async {
      await seedHabit(
        habit(frequency: HabitFrequency.weeklyTimes, weeklyTimes: 3),
      );
      await seedCheckins('h1', {today: 1});
      await pump(tester, const HabitPage());

      expect(find.textContaining('本周 1/3 次'), findsOneWidget);
    });

    testWidgets('列表保持精简：不内嵌热力图与进度条，靠「详情」入口进详情页', (tester) async {
      await seedHabit(habit());
      await pump(tester, const HabitPage());

      // 进度条与热力图都在详情页（2026-10-11 从列表移走，避免整屏条形图与格子）
      expect(find.byType(HeatMap), findsNothing, reason: '热力图应在详情页');
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: '进度条应在详情页',
      );

      await tester.tap(find.byTooltip('详情与热力图'));
      await tester.pumpAndSettle();

      expect(find.text('打卡热力图（近一年）'), findsOneWidget);
      expect(find.text('近一年统计'), findsOneWidget);
      expect(find.byType(HeatMap), findsOneWidget);
    });
  });

  group('习惯详情页 - 批量补打卡', () {
    testWidgets('选日期 → 必须填原因才能修改，改完写入记录', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {});
      await pump(tester, const HabitDetailPage(habitId: 'h1'));

      // 选一个较早的日期（在大图左侧，初始视口内）
      final target = AppTime.dateOnly(
        DateTime.now().subtract(const Duration(days: 300)),
      );
      final cell = find.byKey(ValueKey('heat-$target'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.text('已选 1 天'), findsOneWidget);

      await tester.tap(find.text('修改选中'));
      await tester.pumpAndSettle();
      expect(find.text('修改 1 天的记录'), findsOneWidget);

      // 不填原因 → 被拦下
      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();
      expect(find.text('请填写原因'), findsOneWidget);

      // 填上原因 → 通过
      await tester.enterText(find.byType(TextField).last, '那几天忘了打卡');
      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已修改 1 天'), findsOneWidget);
      // 数据确实落盘，并留下审计日志
      final json = await store.read('habit/checkins/h1.json');
      expect(json?[target], 1);
      final logs = await store.readList('habit/logs/h1.json');
      expect(logs.length, 1);
      expect(logs.single['reason'], '那几天忘了打卡');
      expect(logs.single['dates'], [target]);
    });

    testWidgets('可以一次选多天（批量）', (tester) async {
      await seedHabit(habit());
      await seedCheckins('h1', {});
      await pump(tester, const HabitDetailPage(habitId: 'h1'));

      for (final offset in [300, 301]) {
        final d = AppTime.dateOnly(
          DateTime.now().subtract(Duration(days: offset)),
        );
        final cell = find.byKey(ValueKey('heat-$d'));
        await tester.ensureVisible(cell);
        await tester.tap(cell);
        await tester.pumpAndSettle();
      }

      expect(find.text('已选 2 天'), findsOneWidget);
    });

    testWidgets('未来的日子不能选（有提示）', (tester) async {
      final now = DateTime.now();
      // 本周内「今天之后」的那一天；今天已经是周日时不存在这样的格子
      if (now.weekday >= DateTime.sunday) {
        markTestSkipped('今天是本周最后一天，热力图本周列内没有未来日期');
        return;
      }
      await seedHabit(habit());
      await pump(tester, const HabitDetailPage(habitId: 'h1'));

      final tomorrow = AppTime.dateOnly(
        now.add(const Duration(days: 1)),
      );
      final cell = find.byKey(ValueKey('heat-$tomorrow'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.text('未来的日子不能修改'), findsOneWidget);
      expect(find.textContaining('已选'), findsNothing);
    });

    testWidgets('图例列出五种状态', (tester) async {
      await seedHabit(habit());
      await pump(tester, const HabitDetailPage(habitId: 'h1'));

      for (final label in ['已完成', '未完全完成', '漏打卡', '标记未完成', '未安排']) {
        expect(find.text(label), findsWidgets, reason: '图例应包含 $label');
      }
    });
  });
}
