import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/todo/todo_page.dart';
import 'package:allone/features/todo/todo_repository.dart';

import 'support/mem_store.dart';

/// 子任务完成链路：仓库层（勾选 → 落盘 → 父任务自动完成）与界面层（能点到勾选框）。
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

  TodoItem leaf(String id, {String title = '', TodoStatus status = TodoStatus.pending}) =>
      TodoItem(id: id, title: title, status: status, createdAt: t0, updatedAt: t0);

  Future<void> seed(TodoItem parent) =>
      store.write('todo/items/${parent.id}.json', parent.toJson());

  group('仓库层：子任务完成', () {
    test('勾选子任务 → 子任务落盘为 done', () async {
      await seed(
        leaf('p1', title: '父').copyWith(
          children: [leaf('c1', title: '子 1'), leaf('c2', title: '子 2')],
        ),
      );
      await container.read(todoListProvider.future);
      await container.read(todoListProvider.notifier).setStatus('c1', TodoStatus.done);

      final json = await store.read('todo/items/p1.json');
      final kids = (json!['children'] as List).cast<Map<String, dynamic>>();
      expect(kids[0]['status'], 'done', reason: '子任务 1 应该已完成');
      expect(kids[1]['status'], 'pending', reason: '子任务 2 不应被动到');
      expect(json['status'], 'pending', reason: '还有子任务没做完，父任务不该完成');
    });

    test('全部子任务完成 → 父任务自动完成', () async {
      await seed(
        leaf('p2', title: '父').copyWith(
          children: [leaf('c3'), leaf('c4', status: TodoStatus.done)],
        ),
      );
      await container.read(todoListProvider.future);
      await container.read(todoListProvider.notifier).setStatus('c3', TodoStatus.done);

      final json = await store.read('todo/items/p2.json');
      expect(json!['status'], 'done', reason: '最后一个子任务完成后父任务应自动完成');
    });

    test('取消勾选子任务 → 子任务回到 pending', () async {
      await seed(
        leaf('p3').copyWith(children: [leaf('c5', status: TodoStatus.done)]),
      );
      await container.read(todoListProvider.future);
      await container
          .read(todoListProvider.notifier)
          .setStatus('c5', TodoStatus.pending);

      final json = await store.read('todo/items/p3.json');
      final kids = (json!['children'] as List).cast<Map<String, dynamic>>();
      expect(kids.single['status'], 'pending');
    });
  });

  testWidgets('界面上：展开任务链后能勾选子任务', (tester) async {
    await seed(
      leaf('p4', title: '父任务').copyWith(children: [leaf('c6', title: '子任务甲')]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
        child: const MaterialApp(home: TodoPage()),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    expect(find.text('父任务'), findsOneWidget);
    // 任务链默认收起：先展开
    expect(find.text('子任务甲'), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    expect(find.text('子任务甲'), findsOneWidget);
    // 父 + 子各一个勾选框，点最后一个（子任务）
    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();

    final json = await store.read('todo/items/p4.json');
    final kids = (json!['children'] as List).cast<Map<String, dynamic>>();
    expect(kids.single['status'], 'done', reason: '点勾选框应真的把子任务标成完成');
  });
}
