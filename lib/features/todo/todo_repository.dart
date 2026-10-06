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

  /// 取当前待办树；**若尚未加载完成则先等待加载**。
  ///
  /// 这个方法是防「整表被清空」的关键：[_persist] 会重写全部顶层文件，
  /// 并把不在列表里的文件**删掉**。如果这里像以前那样退化成
  /// `state.valueOrNull ?? []`，那么只要在数据还没加载好时触发任意一次写操作
  /// （例如刚打开 App 立刻点了保存 / 删除 / 勾选完成），
  /// 拿到的就是空列表，[_persist] 会把**磁盘上所有待办全部删除**。
  ///
  /// 因此这里宁可等待也不猜：拿不到数据就等它加载完。
  Future<List<TodoItem>> _treeOrLoad() async {
    final current = state.valueOrNull;
    if (current != null) return current;
    return await ref.read(todoListProvider.future);
  }

  /// 保存：若 id 已存在则替换（编辑），否则作为新顶层条目追加。
  Future<void> saveItem(TodoItem item) async {
    final tree = await _treeOrLoad();
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
  ///
  /// 注意：只删除**顶层文件**。子任务内嵌在父 JSON 的 `children` 中，
  /// 随父文件一起消失；而附件存放在 `todo/items/<顶层id>/media/`，
  /// 因此删除顶层条目时必须连同该附件目录一起清理，
  /// 否则会留下永远无法访问的孤立附件。
  Future<void> deleteItem(String id) async {
    final tree = await _treeOrLoad();
    final newTree = _removeTree(tree, id);
    // 被移除的顶层条目（含其整棵子树）id
    final kept = newTree.map((e) => e.id).toSet();
    final removed = tree
        .map((e) => e.id)
        .where((e) => !kept.contains(e))
        .toList();
    await _persist(newTree, removedIds: removed);
  }

  /// 设置任意节点状态（顶层 / 子任务递归定位）。
  /// 若标记为完成（done），会向上自动传播：父节点的所有直接子任务均完成时，父节点自动完成。
  Future<void> setStatus(String id, TodoStatus status) async {
    final tree = await _treeOrLoad();
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
    final tree = await _treeOrLoad();
    await _persist(
      _mapTree(tree, id, (e) => _withSubtreeStatus(e, TodoStatus.archived)),
    );
  }

  /// 把 id 节点（含整棵子树）从回收站恢复（pending）
  Future<void> restoreItem(String id) async {
    final tree = await _treeOrLoad();
    await _persist(
      _mapTree(tree, id, (e) => _withSubtreeStatus(e, TodoStatus.pending)),
    );
  }

  /// 给指定父节点添加子任务
  Future<void> addChild(String parentId, TodoItem child) async {
    final tree = await _treeOrLoad();
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
    final allDone =
        newChildren.isNotEmpty &&
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
  ///
  /// [removedIds] 为本次被删除的顶层条目 id：除 JSON 外，
  /// 还会清理其附件目录 `todo/items/<id>/media/`，避免遗留孤立附件。
  Future<void> _persist(
    List<TodoItem> tree, {
    List<String> removedIds = const [],
  }) async {
    final store = await ref.read(jsonStoreProvider.future);
    for (final top in tree) {
      await store.write('$_dir/${top.id}.json', top.toJson());
    }
    // 清理不再存在的顶层文件（含附件目录）
    final files = await store.listFiles(_dir);
    final ids = tree.map((t) => t.id).toSet();
    for (final f in files) {
      final id = f.replaceAll('.json', '');
      if (!ids.contains(id)) {
        await store.delete('$_dir/$f');
        await store.deleteDirectory('$_dir/$id/media');
      }
    }
    // deleteItem 传入的已删除条目：其 JSON 在上一轮已不在文件列表中，
    // 这里同样清理附件目录
    for (final id in removedIds) {
      await store.deleteDirectory('$_dir/$id/media');
    }
    ref.invalidateSelf();
  }

  /// 清理回收站：彻底删除「已完成 / 已归档」且最后更新早于 [before] 的顶层条目。
  ///
  /// [before] 为 null 表示清空整个回收站（不限时间）。
  /// 返回被删除的条数。附件目录一并清理，避免留下孤立附件。
  Future<int> purgeTrash({DateTime? before}) async {
    final tree = await _treeOrLoad();
    final victims = purgedItemIds(tree, before: before);
    if (victims.isEmpty) return 0;
    final victimSet = victims.toSet();
    final kept = tree.where((e) => !victimSet.contains(e.id)).toList();
    await _persist(kept, removedIds: victims);
    return victims.length;
  }
}

/// 算出应被清出回收站的顶层条目 id（纯函数，便于单元测试）。
///
/// 规则：只清理状态为 `done` 或 `archived` 的**顶层**条目；
/// `before` 不为空时还要求 `updatedAt` 早于它。`pending` 的条目永不清理。
List<String> purgedItemIds(List<TodoItem> tree, {DateTime? before}) {
  return [
    for (final e in tree)
      if ((e.status == TodoStatus.done || e.status == TodoStatus.archived) &&
          (before == null || e.updatedAt.isBefore(before)))
        e.id,
  ];
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
