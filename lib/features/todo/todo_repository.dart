import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'todo_models.dart';

/// 待办列表 Notifier
class TodoListNotifier extends AsyncNotifier<List<TodoItem>> {
  static const _dir = 'todo/items';

  @override
  Future<List<TodoItem>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <TodoItem>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(TodoItem.fromJson(json));
    }
    list.sort((a, b) {
      // 未完成在前，再按截止时间
      if (a.status != b.status) return a.status == TodoStatus.pending ? -1 : 1;
      return (a.deadline.date + a.deadline.time).compareTo(
        b.deadline.date + b.deadline.time,
      );
    });
    return list;
  }

  Future<void> saveItem(TodoItem item) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${item.id}.json', item.toJson());
    ref.invalidateSelf();
  }

  Future<void> deleteItem(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }

  Future<void> setStatus(String id, TodoStatus status) async {
    final items = state.valueOrNull ?? [];
    final idx = items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    await saveItem(
      items[idx].copyWith(status: status, updatedAt: DateTime.now()),
    );
  }
}

/// 任务链列表 Notifier
class TaskChainListNotifier extends AsyncNotifier<List<TaskChain>> {
  static const _dir = 'todo/chains';

  @override
  Future<List<TaskChain>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <TaskChain>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(TaskChain.fromJson(json));
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> saveChain(TaskChain chain) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${chain.id}.json', chain.toJson());
    ref.invalidateSelf();
  }

  Future<void> deleteChain(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }

  Future<void> toggleSubTask(
    String chainId,
    String subTaskId,
    bool done,
  ) async {
    final chains = state.valueOrNull ?? [];
    final idx = chains.indexWhere((c) => c.id == chainId);
    if (idx < 0) return;
    final chain = chains[idx];
    final updated = chain.copyWith(
      subTasks: [
        for (final s in chain.subTasks)
          s.id == subTaskId ? s.copyWith(done: done) : s,
      ],
      updatedAt: DateTime.now(),
    );
    await saveChain(updated);
  }
}

final todoListProvider =
    AsyncNotifierProvider<TodoListNotifier, List<TodoItem>>(
      TodoListNotifier.new,
    );
final taskChainListProvider =
    AsyncNotifierProvider<TaskChainListNotifier, List<TaskChain>>(
      TaskChainListNotifier.new,
    );

/// 待办模板列表 Notifier
class TodoTemplateListNotifier extends AsyncNotifier<List<TodoTemplate>> {
  static const _dir = 'todo/templates';

  @override
  Future<List<TodoTemplate>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <TodoTemplate>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(TodoTemplate.fromJson(json));
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> save(TodoTemplate t) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${t.id}.json', t.toJson());
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }
}

final todoTemplateListProvider =
    AsyncNotifierProvider<TodoTemplateListNotifier, List<TodoTemplate>>(
      TodoTemplateListNotifier.new,
    );

/// 待办附件目录
String todoMediaDir(String itemId) => 'todo/items/$itemId/media';
