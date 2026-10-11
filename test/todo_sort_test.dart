import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/ui_prefs.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/core/storage/ui_prefs_providers.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/todo/todo_repository.dart';

import 'support/mem_store.dart';

/// 待办排序的测试：
/// ①四种排序方式的规则；②手动模式的 order 固化；③顶层与子任务的上移 / 下移；
/// ④非手动模式点移动会自动切到手动（顺序不突变）；⑤新建按截止时间插位。
void main() {
  TodoItem t(
    String id, {
    String title = '',
    String deadline = '',
    String time = '',
    int order = 0,
    DateTime? created,
    TodoStatus status = TodoStatus.pending,
    List<TodoItem> children = const [],
  }) => TodoItem(
    id: id,
    title: title.isEmpty ? id : title,
    deadline: DeadlineInfo(date: deadline, time: time),
    order: order,
    status: status,
    children: children,
    createdAt: created ?? DateTime.parse('2026-01-01T00:00:00'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00'),
  );

  group('排序规则（纯逻辑）', () {
    test('手动：按 order 升序，order 相同按创建时间', () {
      final list = [
        t('c', order: 3),
        t('a', order: 1),
        t('b', order: 2),
      ];
      expect(
        sortTodos(list, TodoSortMode.manual).map((e) => e.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('截止时间：近的在前，没有截止时间的排最后', () {
      final list = [
        t('none'),
        t('late', deadline: '2026-10-20'),
        t('soon', deadline: '2026-10-01'),
        t('sameDayLater', deadline: '2026-10-01', time: '18:00'),
        t('sameDayEarly', deadline: '2026-10-01', time: '09:00'),
      ];
      // 只写日期没写时间的，视为当天最早（排在同日有具体时间的之前）
      expect(
        sortTodos(list, TodoSortMode.deadline).map((e) => e.id).toList(),
        ['soon', 'sameDayEarly', 'sameDayLater', 'late', 'none'],
      );
    });

    test('创建时间：新的在前', () {
      final list = [
        t('old', created: DateTime.parse('2026-01-01T00:00:00')),
        t('new', created: DateTime.parse('2026-06-01T00:00:00')),
        t('mid', created: DateTime.parse('2026-03-01T00:00:00')),
      ];
      expect(
        sortTodos(list, TodoSortMode.created).map((e) => e.id).toList(),
        ['new', 'mid', 'old'],
      );
    });

    test('标题：升序', () {
      final list = [t('c', title: 'ccc'), t('a', title: 'aaa'), t('b', title: 'bbb')];
      expect(
        sortTodos(list, TodoSortMode.title).map((e) => e.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('除手动外，未完成的都排在已完成 / 已归档之前', () {
      final list = [
        t('done', deadline: '2026-10-01', status: TodoStatus.done),
        t('pending', deadline: '2026-10-20'),
      ];
      expect(
        sortTodos(list, TodoSortMode.deadline).map((e) => e.id).toList(),
        ['pending', 'done'],
      );
      expect(
        sortTodos(list, TodoSortMode.title).map((e) => e.id).toList(),
        ['pending', 'done'],
      );
    });

    test('排序方式解析：未知值回退「截止时间」', () {
      expect(todoSortModeFrom('manual'), TodoSortMode.manual);
      expect(todoSortModeFrom('bogus'), TodoSortMode.deadline);
      expect(todoSortModeFrom(null), TodoSortMode.deadline);
    });
  });

  group('order 字段兼容', () {
    test('JSON 往返带 order', () {
      final back = TodoItem.fromJson(t('a', order: 7).toJson());
      expect(back.order, 7);
    });

    test('旧数据没有 order → 0（不影响原有行为）', () {
      final back = TodoItem.fromJson(const {
        'id': 'x',
        'title': '旧待办',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });
      expect(back.order, 0);
      expect(back.status, TodoStatus.pending);
    });
  });

  group('排序与移动（落盘）', () {
    late MemStore store;
    late ProviderContainer container;

    setUp(() {
      store = MemStore();
      container = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
      );
    });
    tearDown(() => container.dispose());

    TodoListNotifier n() => container.read(todoListProvider.notifier);

    Future<void> seed(List<TodoItem> list) async {
      for (final x in list) {
        await store.write('todo/items/${x.id}.json', x.toJson());
      }
    }

    Future<List<TodoItem>> shown() => container.read(todoListProvider.future);

    Future<TodoSortMode> mode() async => todoSortModeFrom(
      (await container.read(uiPrefsProvider.future)).raw(UiPrefs.todoSortModeKey),
    );

    test('默认仍是「按截止时间」（保持旧行为）', () async {
      await seed([t('a', deadline: '2026-10-05'), t('b', deadline: '2026-10-01')]);
      expect(await mode(), TodoSortMode.deadline);
      expect((await shown()).map((e) => e.id).toList(), ['b', 'a']);
    });

    test('切到手动：把当前显示顺序固化成 order，顺序不变', () async {
      await seed([
        t('a', deadline: '2026-10-05'),
        t('b', deadline: '2026-10-01'),
        t('c', deadline: '2026-10-20'),
      ]);
      final before = (await shown()).map((e) => e.id).toList();
      expect(before, ['b', 'a', 'c']);

      await n().setSortMode(TodoSortMode.manual);

      expect(await mode(), TodoSortMode.manual);
      expect(
        (await shown()).map((e) => e.id).toList(),
        ['b', 'a', 'c'],
        reason: '切过去顺序不能突变',
      );
      // order 被固化成 1..n
      final a = TodoItem.fromJson((await store.read('todo/items/a.json'))!);
      final b = TodoItem.fromJson((await store.read('todo/items/b.json'))!);
      expect(b.order, 1);
      expect(a.order, 2);
    });

    test('手动模式下上移 / 下移顶层条目', () async {
      await seed([
        t('a', order: 1),
        t('b', order: 2),
        t('c', order: 3),
      ]);
      await n().setSortMode(TodoSortMode.manual);

      await n().moveItem('c', -1);
      expect((await shown()).map((e) => e.id).toList(), ['a', 'c', 'b']);

      await n().moveItem('a', 1);
      expect((await shown()).map((e) => e.id).toList(), ['c', 'a', 'b']);

      // 边界：第一个再上移、最后一个再下移都是静默无事
      await n().moveItem('c', -1);
      await n().moveItem('b', 1);
      expect((await shown()).map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('非手动模式下点移动：自动切到手动，顺序不突变后再移动', () async {
      await seed([t('a', deadline: '2026-10-05'), t('b', deadline: '2026-10-01')]);
      expect((await shown()).map((e) => e.id).toList(), ['b', 'a']); // 截止时间顺序

      await n().moveItem('a', -1); // 对第二条「上移」

      expect(await mode(), TodoSortMode.manual, reason: '应自动切到手动');
      expect(
        (await shown()).map((e) => e.id).toList(),
        ['a', 'b'],
        reason: '固化后交换，结果是 a 到了前面',
      );
    });

    test('子任务的上移 / 下移：重排父节点的 children 数组', () async {
      await seed([
        t(
          'p',
          children: [
            t('c1', title: '第一'),
            t('c2', title: '第二'),
            t('c3', title: '第三'),
          ],
        ),
      ]);
      await container.read(todoListProvider.future);

      await n().moveItem('c3', -1);
      var p = TodoItem.fromJson((await store.read('todo/items/p.json'))!);
      expect(p.children.map((e) => e.id).toList(), ['c1', 'c3', 'c2']);

      await n().moveItem('c1', 1);
      p = TodoItem.fromJson((await store.read('todo/items/p.json'))!);
      expect(p.children.map((e) => e.id).toList(), ['c3', 'c1', 'c2']);

      // 子任务移动不受排序方式影响（不会去改偏好）
      expect(await mode(), TodoSortMode.deadline);
    });

    test('手动模式下新建：按截止时间插位', () async {
      await seed([
        t('a', deadline: '2026-10-01', order: 1),
        t('b', deadline: '2026-10-10', order: 2),
        t('c', deadline: '2026-10-20', order: 3),
      ]);
      await n().setSortMode(TodoSortMode.manual);

      await n().saveItem(t('new', deadline: '2026-10-05'));
      expect(
        (await shown()).map((e) => e.id).toList(),
        ['a', 'new', 'b', 'c'],
      );
    });

    test('手动模式下新建无截止时间 → 排最后', () async {
      await seed([t('a', deadline: '2026-10-01', order: 1)]);
      await n().setSortMode(TodoSortMode.manual);

      await n().saveItem(t('new'));
      expect((await shown()).map((e) => e.id).toList(), ['a', 'new']);
    });

    test('数据没加载就操作，不会把已有待办删掉（关键回归）', () async {
      await seed([t('a'), t('b'), t('c')]);
      // 故意不先读 provider，直接写
      await n().moveItem('a', 1);
      await n().deleteItem('b');

      final ids = <String>[];
      for (final f in await store.listFiles('todo/items')) {
        ids.add(f.replaceAll('.json', ''));
      }
      ids.sort();
      expect(ids, ['a', 'c'], reason: '只应删掉 b，a 与 c 必须还在');
    });
  });
}
