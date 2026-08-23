import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'todo_models.dart';

/// 待办列表 Notifier（树形：每条目一个文件，子任务内嵌于父 JSON）。
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

  /// 保存：若 id 已存在则替换（编辑），否则作为新顶层条目追加。
  Future<void> saveItem(TodoItem item) async {
    final tree = state.valueOrNull ?? [];
    final exists = _findInTree(tree, item.id);
    final newTree = <TodoItem>[...tree];
    if (exists != null) {
      newTree
        ..clear()
        ..addAll(_mapTree(tree, item.id, (_) => item));
    } else {
      newTree.add(item);
    }
    await _persist(newTree);
  }

  /// 删除任意节点（顶层或子任务）；删除顶层时同时移除其文件。
  Future<void> deleteItem(String id) async {
    final tree = state.valueOrNull ?? [];
    await _persist(_removeTree(tree, id));
  }

  /// 设置任意节点状态（顶层 / 子任务递归定位）。
  /// 若标记为完成（done），会向上自动传播：父节点的所有直接子任务均完成时，父节点自动完成。
  Future<void> setStatus(String id, TodoStatus status) async {
    final tree = state.valueOrNull ?? [];
    var newTree = _mapTree(
      tree,
      id,
      (e) => e.copyWith(status: status, updatedAt: DateTime.now()),
    );
    if (status == TodoStatus.done) {
      newTree = _autoCompleteParents(newTree, id);
    }
    await _persist(newTree);
  }

  /// 把 id 节点（含整棵子树）移入回收站（archived）
  Future<void> archiveItem(String id) async {
    final tree = state.valueOrNull ?? [];
    await _persist(
      _mapTree(tree, id, (e) => _withSubtreeStatus(e, TodoStatus.archived)),
    );
  }

  /// 把 id 节点（含整棵子树）从回收站恢复（pending）
  Future<void> restoreItem(String id) async {
    final tree = state.valueOrNull ?? [];
    await _persist(
      _mapTree(tree, id, (e) => _withSubtreeStatus(e, TodoStatus.pending)),
    );
  }

  /// 给指定父节点添加子任务
  Future<void> addChild(String parentId, TodoItem child) async {
    final tree = state.valueOrNull ?? [];
    await _persist(
      _mapTree(
        tree,
        parentId,
        (e) => e.copyWith(
          children: [...e.children, child],
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  // —— 树操作辅助 ——

  /// 在树中查找指定 id 的节点
  TodoItem? _findInTree(List<TodoItem> items, String id) {
    for (final i in items) {
      if (i.id == id) return i;
      final found = _findInTree(i.children, id);
      if (found != null) return found;
    }
    return null;
  }

  /// 树中把 id 节点替换为 [f] 的结果（其余不变）
  List<TodoItem> _mapTree(
    List<TodoItem> items,
    String id,
    TodoItem Function(TodoItem) f,
  ) {
    return [
      for (final i in items)
        if (i.id == id)
          f(i)
        else
          i.copyWith(children: _mapTree(i.children, id, f)),
    ];
  }

  /// 从树中移除 id 节点（含其子树）
  List<TodoItem> _removeTree(List<TodoItem> items, String id) {
    final out = <TodoItem>[];
    for (final i in items) {
      if (i.id == id) continue; // 跳过被删节点
      out.add(i.copyWith(children: _removeTree(i.children, id)));
    }
    return out;
  }

  /// 递归设置整棵子树状态（用于归档 / 恢复）
  TodoItem _withSubtreeStatus(TodoItem node, TodoStatus status) {
    return node.copyWith(
      status: status,
      children: node.children
          .map((c) => _withSubtreeStatus(c, status))
          .toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// 向上传播「子任务全部完成 → 父节点自动完成」。
  /// 仅沿包含 [id] 的分支回溯；沿途若某父节点的所有直接子任务均完成，
  /// 则把该父节点自动置为 done（已归档的节点不改变）。
  List<TodoItem> _autoCompleteParents(List<TodoItem> items, String id) {
    return [
      for (final i in items)
        if (i.id == id)
          i
        else
          _maybeCompleteParent(i, _autoCompleteParents(i.children, id)),
    ];
  }

  TodoItem _maybeCompleteParent(TodoItem node, List<TodoItem> newChildren) {
    if (node.status == TodoStatus.archived) {
      return node.copyWith(children: newChildren);
    }
    final allDone = newChildren.isNotEmpty &&
        newChildren.every((c) => c.status == TodoStatus.done);
    if (allDone && node.status != TodoStatus.done) {
      return node.copyWith(
        children: newChildren,
        status: TodoStatus.done,
        updatedAt: DateTime.now(),
      );
    }
    return node.copyWith(children: newChildren);
  }

  /// 持久化：重写所有顶层文件，并删除已不存在的顶层文件。
  Future<void> _persist(List<TodoItem> tree) async {
    final store = await ref.read(jsonStoreProvider.future);
    for (final top in tree) {
      await store.write('$_dir/${top.id}.json', top.toJson());
    }
    // 清理不再存在的顶层文件
    final files = await store.listFiles(_dir);
    final ids = tree.map((t) => t.id).toSet();
    for (final f in files) {
      final id = f.replaceAll('.json', '');
      if (!ids.contains(id)) await store.delete('$_dir/$f');
    }
    ref.invalidateSelf();
  }
}

final todoListProvider =
    AsyncNotifierProvider<TodoListNotifier, List<TodoItem>>(
      TodoListNotifier.new,
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
