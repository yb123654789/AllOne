import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/models/ui_prefs.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/storage/ui_prefs_providers.dart';
import 'quest_models.dart';

/// 任务列表 Notifier。
///
/// ⚠️ **所有写操作都从磁盘读最新值再改**（`_fromDisk` / `_allFromDisk` / `mutate`）。
/// 原因见习惯模块的记录：写完之后会 `invalidateSelf()`，而 rebuild 完成前
/// `state` 仍是旧快照 —— 连点两下就会「后一次覆盖前一次」；
/// 数据没加载完时更会把整份文件覆盖成空的。
///
/// 结构调整（升降级 / 移动）需要**整张表**才能重排同级顺序，
/// 所以这类操作统一走 [_restructure]。
class QuestListNotifier extends AsyncNotifier<List<Quest>> {
  static const _dir = 'quest/quests';

  @override
  Future<List<Quest>> build() async {
    final list = await _allFromDisk();
    return list;
  }

  // ── 读写基础 ────────────────────────────────────────────────────────────

  Future<List<Quest>> _allFromDisk() async {
    final store = await ref.read(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <Quest>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(Quest.fromJson(json));
    }
    return list;
  }

  Future<Quest?> _fromDisk(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read('$_dir/$id.json');
    return json == null ? null : Quest.fromJson(json);
  }

  Future<void> _write(Quest q) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${q.id}.json', q.toJson());
    ref.invalidateSelf();
  }

  static Quest? _find(List<Quest> all, String id) {
    for (final q in all) {
      if (q.id == id) return q;
    }
    return null;
  }

  static void _update(List<Quest> all, String id, Quest Function(Quest) f) {
    final i = all.indexWhere((q) => q.id == id);
    if (i >= 0) all[i] = f(all[i]);
  }

  /// 结构调整的统一入口：读全表 → 变换 → 只写变化的文件
  Future<String?> _restructure(
    String? Function(List<Quest> all) transform,
  ) async {
    final before = await _allFromDisk();
    final all = [...before];
    final err = transform(all);
    if (err != null) return err;
    final store = await ref.read(jsonStoreProvider.future);
    final oldById = {for (final q in before) q.id: q};
    for (final q in all) {
      final o = oldById[q.id];
      if (o == null ||
          o.parentId != q.parentId ||
          o.order != q.order ||
          o.updatedAt != q.updatedAt) {
        await store.write('$_dir/${q.id}.json', q.toJson());
      }
    }
    ref.invalidateSelf();
    return null;
  }

  /// 把某个父任务下的兄弟重新编号为 0..n-1（顺序按当前 order / 更新时间）
  void _reorder(List<Quest> all, String parentId) {
    final kids = QuestLogic.childrenOf(all, parentId);
    for (var i = 0; i < kids.length; i++) {
      final id = kids[i].id;
      _update(
        all,
        id,
        (q) => q.copyWith(order: i, updatedAt: DateTime.now()),
      );
    }
  }

  // ── 保存 / 局部修改 ─────────────────────────────────────────────────────

  /// 新建或整体保存（编辑页用）。新建的任务排在**同级**末尾
  /// （顶层任务 = 顶层列表末尾，子项目 = 该父任务下的末尾）。
  Future<void> save(Quest q) async {
    var toWrite = q;
    final all = await _allFromDisk();
    final siblings = QuestLogic.childrenOf(all, q.parentId);
    if (!siblings.any((r) => r.id == q.id)) {
      toWrite = q.copyWith(order: siblings.length);
    }
    await _write(toWrite.copyWith(updatedAt: DateTime.now()));
  }

  /// 局部修改：读磁盘 → 变换 → 写回（并自动刷新 updatedAt）
  Future<void> mutate(String id, Quest Function(Quest) f) async {
    final q = await _fromDisk(id);
    if (q == null) return;
    await _write(f(q).copyWith(updatedAt: DateTime.now()));
  }

  /// 新建一个子项目（挂在 [parentId] 下，分类默认继承父任务）
  Future<Quest> createChild(String parentId, {required String title}) async {
    final all = await _allFromDisk();
    final parent = _find(all, parentId);
    final siblings = QuestLogic.childrenOf(all, parentId);
    final now = DateTime.now();
    final child = Quest(
      id: AppPaths.newId(),
      title: title,
      category: parent?.category ?? '未分类',
      parentId: parentId,
      order: siblings.length,
      startDate: AppTime.dateOnly(now),
      createdAt: now,
      updatedAt: now,
    );
    await _write(child);
    return child;
  }

  // ── 层级调整 ────────────────────────────────────────────────────────────

  /// 降一级：成为**上一个同级任务**的子项目。
  ///
  /// 返回 null 表示成功，否则是拒绝原因（无法降级时给出提示）。
  Future<String?> indent(String id) => _restructure((all) {
    final self = _find(all, id);
    if (self == null) return '任务不存在';
    final siblings = QuestLogic.childrenOf(all, self.parentId);
    final i = siblings.indexWhere((s) => s.id == id);
    if (i <= 0) {
      return '它上面没有同级任务了：降级是挂到「上一个同级任务」下面，'
          '先用「上移」把它移到一个任务下面，或改用「移动到…」';
    }
    final newParent = siblings[i - 1];
    final kids = QuestLogic.childrenOf(all, newParent.id);
    _update(
      all,
      id,
      (q) => q.copyWith(
        parentId: newParent.id,
        order: kids.length,
        updatedAt: DateTime.now(),
      ),
    );
    _reorder(all, self.parentId);
    _reorder(all, newParent.id);
    return null;
  });

  /// 升一级：成为父任务的**下一个同级任务**。
  Future<String?> outdent(String id) => _restructure((all) {
    final self = _find(all, id);
    if (self == null) return '任务不存在';
    if (self.parentId.isEmpty) return '它已经是最顶层了';
    final parent = _find(all, self.parentId);
    if (parent == null) return '父任务不存在';
    _update(
      all,
      id,
      (q) => q.copyWith(
        parentId: parent.parentId,
        order: parent.order + 1,
        updatedAt: DateTime.now(),
      ),
    );
    _reorder(all, parent.parentId);
    _reorder(all, parent.id);
    return null;
  });

  /// 同级上移 / 下移（[delta] = -1 / +1）。到边界时静默不做。
  Future<String?> moveSibling(String id, int delta) => _restructure((all) {
    final self = _find(all, id);
    if (self == null) return '任务不存在';
    final siblings = QuestLogic.childrenOf(all, self.parentId);
    final i = siblings.indexWhere((s) => s.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return null;
    final ids = siblings.map((s) => s.id).toList();
    final tmp = ids[i];
    ids[i] = ids[j];
    ids[j] = tmp;
    for (var k = 0; k < ids.length; k++) {
      _update(
        all,
        ids[k],
        (q) => q.copyWith(order: k, updatedAt: DateTime.now()),
      );
    }
    return null;
  });

  /// 移动到任意父任务（[newParentId] 为空 = 移到顶层）。
  ///
  /// 会拒绝「移动到它自己或它的子孙下面」这种会形成环的操作。
  Future<String?> moveTo(String id, String newParentId) => _restructure((all) {
    final self = _find(all, id);
    if (self == null) return '任务不存在';
    if (!QuestLogic.canMoveTo(all, id, newParentId)) {
      return '不能移到它自己或它自己的子项目下面';
    }
    final siblings = QuestLogic.childrenOf(all, newParentId);
    final oldParent = self.parentId;
    _update(
      all,
      id,
      (q) => q.copyWith(
        parentId: newParentId,
        order: siblings.length,
        updatedAt: DateTime.now(),
      ),
    );
    _reorder(all, oldParent);
    _reorder(all, newParentId);
    return null;
  });

  // ── 状态 / 重心 ─────────────────────────────────────────────────────────

  /// 设置状态。返回 null 表示成功，否则是拒绝原因。
  ///
  /// **完成约束**：子项目必须**全部已了结**（已完成或已放弃）才允许把父任务
  /// 设为已完成 —— 否则父任务会在子项目还没做完时「假装完成」。
  /// 已放弃的子项目算了结，不然放弃过的子项目会让父任务永远完不成。
  Future<String?> setStatus(String id, QuestStatus status) async {
    if (status == QuestStatus.done) {
      final all = await _allFromDisk();
      final blockers = QuestLogic.blockersForDone(all, id);
      if (blockers.isNotEmpty) {
        final names = blockers
            .take(3)
            .map((b) => '「${b.title.isEmpty ? '未命名' : b.title}」')
            .join('、');
        return '还有 ${blockers.length} 个子项目没了结（$names'
            '${blockers.length > 3 ? ' 等' : ''}），要先把它们设为已完成或已放弃';
      }
    }
    await mutate(id, (q) => q.copyWith(status: status));
    return null;
  }

  /// 钉住 / 取消钉住（钉住 = 当前重心，排在总览最前）
  Future<void> togglePin(String id) async {
    final q = await _fromDisk(id);
    if (q == null) return;
    final next = q.pinned
        ? q.copyWith(pinned: false, clearPinnedAt: true)
        : q.copyWith(pinned: true, pinnedAt: DateTime.now().toIso8601String());
    await _write(next.copyWith(updatedAt: DateTime.now()));
  }

  Future<void> setManualProgress(String id, int value) =>
      mutate(id, (q) => q.copyWith(manualProgress: value.clamp(0, 100)));

  Future<void> setFields(
    String id, {
    String? title,
    String? vision,
    String? category,
    String? startDate,
    String? targetDate,
    String? time,
    bool clearTargetDate = false,
    bool clearTime = false,
  }) => mutate(
    id,
    (q) => q.copyWith(
      title: title,
      vision: vision,
      category: category,
      startDate: startDate,
      targetDate: targetDate,
      time: time,
      clearTargetDate: clearTargetDate,
      clearTime: clearTime,
    ),
  );

  /// 日程表里给任务**安排一个时间**（只改 time，不动别的字段）
  Future<void> setTime(String id, String time) => mutate(
    id,
    (q) => q.copyWith(time: time, clearTime: time.isEmpty),
  );

  /// 日程表里给里程碑安排时间
  Future<void> setMilestoneTime(String questId, String milestoneId, String time) =>
      mutate(
        questId,
        (q) => q.copyWith(
          milestones: [
            for (final m in q.milestones)
              if (m.id == milestoneId) m.copyWith(time: time) else m,
          ],
        ),
      );

  // ── 里程碑 ──────────────────────────────────────────────────────────────

  Future<void> addMilestone(String id, String title, {String dueDate = ''}) =>
      mutate(
        id,
        (q) => q.copyWith(
          milestones: [
            ...q.milestones,
            Milestone(id: AppPaths.newId(), title: title, dueDate: dueDate),
          ],
        ),
      );

  /// 勾选 / 取消勾选里程碑（勾选时记下完成日期，用于回看节奏）
  Future<void> toggleMilestone(String id, String milestoneId) => mutate(id, (q) {
    final today = AppTime.dateOnly(DateTime.now());
    return q.copyWith(
      milestones: [
        for (final m in q.milestones)
          if (m.id == milestoneId)
            m.done
                ? m.copyWith(done: false, clearDoneAt: true)
                : m.copyWith(done: true, doneAt: today)
          else
            m,
      ],
    );
  });

  Future<void> updateMilestone(String id, Milestone m) => mutate(
    id,
    (q) => q.copyWith(
      milestones: [
        for (final x in q.milestones) if (x.id == m.id) m else x,
      ],
    ),
  );

  Future<void> removeMilestone(String id, String milestoneId) => mutate(
    id,
    (q) => q.copyWith(
      milestones: q.milestones.where((m) => m.id != milestoneId).toList(),
    ),
  );

  // ── 行动项（关联待办） ──────────────────────────────────────────────────

  /// 关联一个待办（去重；只存 id，待办数据仍在待办模块里）
  Future<void> linkTodo(String id, String todoId) => mutate(
    id,
    (q) => q.todoIds.contains(todoId)
        ? q
        : q.copyWith(todoIds: [...q.todoIds, todoId]),
  );

  Future<void> unlinkTodo(String id, String todoId) => mutate(
    id,
    (q) => q.copyWith(todoIds: q.todoIds.where((t) => t != todoId).toList()),
  );

  // ── 回收站 ──────────────────────────────────────────────────────────────

  /// 移入回收站。返回 null 表示成功，否则是拒绝原因。
  ///
  /// **有子项目时禁止归档**：否则子项目会连同父任务一起从界面上消失，
  /// 而它们其实还没做完（用户明确要求「先处理子项目」）。
  Future<String?> archive(String id) async {
    final all = await _allFromDisk();
    final kids = QuestLogic.childrenOf(all, id);
    if (kids.isNotEmpty) {
      return '它还有 ${kids.length} 个子项目，请先把子项目移出（「移动到…」→ 顶层）或删除';
    }
    await mutate(
      id,
      (q) => q.copyWith(
        archived: true,
        archivedAt: AppTime.dateOnly(DateTime.now()),
        pinned: false,
        clearPinnedAt: true,
      ),
    );
    return null;
  }

  Future<void> restore(String id) => mutate(
    id,
    (q) => q.copyWith(archived: false, clearArchivedAt: true),
  );

  /// 彻底删除（含投入记录与附件目录）。返回 null 表示成功，否则是拒绝原因。
  ///
  /// 同样**有子项目时禁止**，避免「一条删除把整棵没做完的子树悄悄带走」。
  Future<String?> delete(String id) async {
    final all = await _allFromDisk();
    final kids = QuestLogic.childrenOf(all, id);
    if (kids.isNotEmpty) {
      return '它还有 ${kids.length} 个子项目，请先处理子项目再删除';
    }
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    await store.delete('quest/logs/$id.json');
    await store.deleteDirectory(questMediaDir(id));
    ref.invalidateSelf();
    return null;
  }
}

/// 投入记录 Notifier：一个任务一个文件，存数组，只追加（可删除单条）
class InvestLogNotifier extends AsyncNotifier<Map<String, List<InvestLog>>> {
  static const _dir = 'quest/logs';

  @override
  Future<Map<String, List<InvestLog>>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final map = <String, List<InvestLog>>{};
    for (final f in files) {
      final id = f.replaceAll('.json', '');
      final list = await store.readList('$_dir/$f');
      map[id] = list.map(InvestLog.fromJson).toList();
    }
    return map;
  }

  /// 磁盘上该任务的最新投入记录
  Future<List<InvestLog>> logsOf(String questId) async {
    final store = await ref.read(jsonStoreProvider.future);
    final list = await store.readList('$_dir/$questId.json');
    return list.map(InvestLog.fromJson).toList();
  }

  Future<void> _writeAll(String questId, List<InvestLog> logs) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.writeList(
      '$_dir/$questId.json',
      logs.map((e) => e.toJson()).toList(),
    );
    ref.invalidateSelf();
  }

  /// 记一笔投入
  Future<void> append(
    String questId, {
    required int minutes,
    String note = '',
    DateTime? at,
  }) async {
    final current = await logsOf(questId);
    await _writeAll(questId, [
      ...current,
      InvestLog(
        id: AppPaths.newId(),
        at: at ?? DateTime.now(),
        minutes: minutes < 0 ? 0 : minutes,
        note: note.trim(),
      ),
    ]);
  }

  Future<void> remove(String questId, String logId) async {
    final current = await logsOf(questId);
    await _writeAll(
      questId,
      current.where((l) => l.id != logId).toList(),
    );
  }
}

final questListProvider = AsyncNotifierProvider<QuestListNotifier, List<Quest>>(
  QuestListNotifier.new,
);
final questLogProvider =
    AsyncNotifierProvider<InvestLogNotifier, Map<String, List<InvestLog>>>(
      InvestLogNotifier.new,
    );

/// 任务附件目录（第一版暂未用附件，先保留约定）
String questMediaDir(String questId) => 'quest/quests/$questId/media';

/// 父进度的加权系数（来自 `settings/ui.json`，可在任务总览页调整）
final questWeightsProvider = Provider<QuestWeights>((ref) {
  final prefs = ref.watch(uiPrefsProvider).valueOrNull;
  return QuestWeights.fromJson(prefs?.raw(UiPrefs.questWeightsKey));
});

/// 详情页是否隐藏「已了结」（已完成 / 已放弃）的子项目，**默认隐藏**
final hideResolvedSubtasksProvider = Provider<bool>((ref) {
  final prefs = ref.watch(uiPrefsProvider).valueOrNull;
  if (prefs == null) return true;
  return prefs.flag(UiPrefs.hideResolvedSubtasksKey, fallback: true);
});
