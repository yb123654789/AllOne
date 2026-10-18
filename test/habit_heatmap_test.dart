import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/core/widgets/heat_map.dart';
import 'package:allone/features/habit/habit_detail_page.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/habit/habit_progress.dart';

import 'support/mem_store.dart';

/// 习惯热力图：用**真实数据形态**（每天打卡 + 失败标记）验证颜色是否真的画出来。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  const green = Color(0xFF30A46C);
  const red = Color(0xFFE5484D);

  /// 与 `AllOneData/habit/habits/20260824224613-18806.json` 同构
  final habitJson = {
    'id': 'h1',
    'title': '禁欲',
    'category': '健康',
    'frequency': 'daily',
    'weekdays': <int>[],
    'intervalDays': 1,
    'weeklyTimes': 1,
    'dailyTarget': 'once',
    'dailyTargetValue': 1,
    'persistence': 'unlimited',
    'persistenceValue': 0,
    'archived': false,
    'description': '',
    'media': <dynamic>[],
    'tags': <String>[],
    'createdAt': '2026-08-24T22:47:01.883176',
    'updatedAt': '2026-08-30T21:37:29.848022',
  };

  /// 与真实 checkins 文件同构（1 = 打卡，-1 = 标记未完成）
  final checkinJson = {
    '2026-08-24': 1,
    '2026-08-30': 1,
    '2026-09-01': 1,
    '2026-09-02': 1,
    '2026-09-04': -1,
    '2026-09-05': 1,
    '2026-09-06': -1,
    '2026-09-30': 1,
    '2026-10-01': -1,
    '2026-10-05': -1,
  };

  final today = '2026-10-18';

  group('纯逻辑：heatCells 的颜色', () {
    test('打卡日 = 绿，失败标记 = 深红，无记录的计划日 = 浅红', () {
      final h = Habit.fromJson(habitJson);
      final cm = CheckinMap.fromJson(checkinJson);
      final cells = HabitProgress.heatCells(
        h,
        cm,
        today: today,
        weeks: 53,
      );
      Map<String, HeatCell> byDate = {
        for (final c in cells) c.date: c,
      };

      expect(byDate['2026-09-01']!.color, green, reason: '打卡日应为绿色');
      expect(byDate['2026-09-04']!.color, red, reason: '标记未完成应为深红');
      expect(
        byDate['2026-09-03']!.color,
        isNot(green),
        reason: '没记录的计划日不该是绿色',
      );
      // 共 53 周 = 371 格
      expect(cells.length, 53 * 7);
    });
  });

  group('界面：详情页热力图', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      await store.write('habit/habits/h1.json', habitJson);
      await store.write('habit/checkins/h1.json', checkinJson);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
          child: const MaterialApp(home: HabitDetailPage(habitId: 'h1')),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    }

    testWidgets('热力图上真的画出了绿色与深红格子', (tester) async {
      await pumpDetail(tester);

      expect(find.byType(HeatMap), findsOneWidget);

      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(HeatMap),
          matching: find.byType(Container),
        ),
      ).toList();
      final colors = <Color?>[
        for (final c in containers)
          if (c.decoration is BoxDecoration)
            (c.decoration as BoxDecoration).color,
      ];

      expect(containers, isNotEmpty, reason: '热力图里应该有格子');
      // 测试数据里 6 天打卡（1）、4 天标记未完成（-1）
      expect(
        colors.where((c) => c == green).length,
        6,
        reason: '打卡日应画成绿色',
      );
      expect(
        colors.where((c) => c == red).length,
        4,
        reason: '标记未完成应画成深红',
      );
      expect(
        colors.any((c) => c == null || c == Colors.transparent),
        isFalse,
        reason: '不应该有没上色的格子',
      );
    });

    testWidgets('周数只铺到习惯创建那周，不再先给一年空白', (tester) async {
      await pumpDetail(tester);

      final map = tester.widget<HeatMap>(find.byType(HeatMap));
      // 习惯建于 2026-08-24，今天 2026-10-18 → 约 8 周
      expect(map.weeks, lessThanOrEqualTo(12));
      expect(map.weeks, greaterThanOrEqualTo(6));
      // 这么短的图不该需要横向滚动：全部格子都在视野里
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byKey(HeatMap.scrollKey),
      );
      expect(scrollView.controller?.position.maxScrollExtent ?? 0, 0);
    });

    testWidgets('长期习惯的大图默认定位到今天（不是停在一年前）', (tester) async {
      final longHabit = {
        ...habitJson,
        'createdAt': '2025-01-01T09:00:00.000',
      };
      await store.write('habit/habits/h1.json', longHabit);
      await store.write('habit/checkins/h1.json', checkinJson);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
          child: const MaterialApp(home: HabitDetailPage(habitId: 'h1')),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      final map = tester.widget<HeatMap>(find.byType(HeatMap));
      expect(map.weeks, 53, reason: '超过一年按一年算');

      final controller = tester
          .widget<SingleChildScrollView>(find.byKey(HeatMap.scrollKey))
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(
        controller.offset,
        controller.position.maxScrollExtent,
        reason: '应滚到最右端（今天那一周）',
      );
    });
  });
}
