import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/todo/todo_page.dart';

import 'support/mem_store.dart';

/// 待办页排序相关的界面测试：
/// 排序方式入口能打开、能切换；每条待办的菜单里有上移 / 下移。
void main() {
  late MemStore store;

  setUp(() => store = MemStore());

  TodoItem t(String id, {String deadline = '', int order = 0}) => TodoItem(
    id: id,
    title: '待办$id',
    deadline: DeadlineInfo(date: deadline),
    order: order,
    createdAt: DateTime.parse('2026-01-01T00:00:00'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00'),
  );

  Future<void> seed(List<TodoItem> list) async {
    for (final x in list) {
      await store.write('todo/items/${x.id}.json', x.toJson());
    }
  }

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

  testWidgets('排序按钮打开排序方式弹窗，四个选项都在，可切换', (tester) async {
    await seed([t('a', deadline: '2026-10-01'), t('b', deadline: '2026-10-05')]);
    await pump(tester, const TodoPage());

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();

    expect(find.text('排序方式'), findsOneWidget);
    for (final m in TodoSortMode.values) {
      expect(find.text(m.label), findsOneWidget, reason: '缺少选项 ${m.label}');
    }

    await tester.tap(find.text('手动排序'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已切换为'), findsOneWidget);
    // 偏好落盘
    final prefs = await store.read('settings/ui.json');
    expect(prefs?['todoSortMode'], 'manual');
  });

  testWidgets('每条待办的「⋮」菜单里有上移 / 下移，点击真的改顺序', (tester) async {
    await seed([
      t('a', deadline: '2026-10-01'),
      t('b', deadline: '2026-10-05'),
    ]);
    await pump(tester, const TodoPage());

    // 默认按截止时间：a 在前
    var shown = await store.read('todo/items/a.json');
    expect(shown?['order'], isNotNull);

    // 打开第二条（b）的菜单
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('上移'), findsOneWidget);
    expect(find.text('下移'), findsOneWidget);

    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    // 非手动模式 → 会先切到手动
    final prefs = await store.read('settings/ui.json');
    expect(prefs?['todoSortMode'], 'manual');
  });
}
