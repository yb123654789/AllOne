/// 任务状态。
///
/// 「暂停」与「放弃」是长期事情必须有的两档：很多任务不是做完了，
/// 而是**先放一放**或者**决定不做了**，这两种要能区分开，
/// 否则它们会永远挂在「进行中」里污染你对重心的判断。
enum QuestStatus {
  active, // 进行中
  paused, // 暂停（以后可能继续）
  done, // 已完成
  dropped, // 已放弃（决定不做）
}

/// 里程碑（阶段）：把一个长期任务切成几段，逐段推进。
class Milestone {
  final String id;
  final String title;

  /// 期望完成日期 yyyy-MM-dd（可空）
  final String dueDate;

  /// 可选的具体时间 HH:mm（配合 [dueDate]；填了才进日程表时间轴）
  final String time;
  final bool done;

  /// 完成日期 yyyy-MM-dd（可空）
  final String doneAt;

  const Milestone({
    required this.id,
    this.title = '',
    this.dueDate = '',
    this.time = '',
    this.done = false,
    this.doneAt = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dueDate': dueDate,
    'time': time,
    'done': done,
    'doneAt': doneAt,
  };

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    dueDate: j['dueDate'] as String? ?? '',
    time: j['time'] as String? ?? '',
    done: j['done'] as bool? ?? false,
    doneAt: j['doneAt'] as String? ?? '',
  );

  Milestone copyWith({
    String? title,
    String? dueDate,
    String? time,
    bool? done,
    String? doneAt,
    bool clearDoneAt = false,
  }) => Milestone(
    id: id,
    title: title ?? this.title,
    dueDate: dueDate ?? this.dueDate,
    time: time ?? this.time,
    done: done ?? this.done,
    doneAt: clearDoneAt ? '' : (doneAt ?? this.doneAt),
  );
}

/// 投入记录：这一次在这个任务上花了多久。
///
/// 为什么单独记：长期任务的价值往往体现在「累计投入」上，
/// 而待办的完成与否说明不了投入量。
class InvestLog {
  final String id;
  final DateTime at;
  final int minutes; // 本次投入分钟数
  final String note;

  const InvestLog({
    required this.id,
    required this.at,
    this.minutes = 0,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'minutes': minutes,
    'note': note,
  };

  factory InvestLog.fromJson(Map<String, dynamic> j) => InvestLog(
    id: j['id'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    note: j['note'] as String? ?? '',
  );
}

/// 任务：需要经年累月推进的事（长期项目 / 领域）。
///
/// 与「待办」的关系是**只引用、不复制**：[todoIds] 里存待办 id，
/// 待办本身仍归待办模块管理（可随时解除关联），
/// 因此删掉一个待办不会破坏任务数据（只会在详情页显示「已失效」）。
class Quest {
  final String id;
  final String title;

  /// 目标 / 愿景：为什么做这个任务、想达成什么
  final String vision;

  /// 领域分类（工作 / 学习 / 健康 / 家庭 …）
  final String category;

  final QuestStatus status;

  /// 起始日期 yyyy-MM-dd（可空）
  final String startDate;

  /// 期望完成日期 yyyy-MM-dd；**空 = 长期、无期限**
  final String targetDate;

  /// 可选的具体时间 HH:mm（配合 [targetDate] 使用）。
  ///
  /// 填了它，任务才会出现在日历「当天」日程表的**时间轴**上；
  /// 不填则只在「无精确时分」区里等着被安排时间。
  final String time;

  /// 手动进度 0~100（仅在**没有里程碑**时使用）
  final int manualProgress;

  /// 是否钉在「当前重心」最前面
  final bool pinned;

  /// 钉住时间（ISO），用于钉住项之间排序
  final String pinnedAt;

  final List<Milestone> milestones;

  /// 关联的待办 id（行动项）
  final List<String> todoIds;

  /// 父任务 id（`''` = 顶层任务）。
  ///
  /// 子项目其实就是**挂在别的任务下的任务**（同类型、可多层），
  /// 因此子项目同样有自己的里程碑、投入记录与子项目。
  final String parentId;

  /// 同级排序（越小越靠前）。结构变化后由仓库重排为 `0..n-1`，保证稳定。
  final int order;

  /// 是否已移入回收站
  final bool archived;
  final String archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Quest({
    required this.id,
    this.title = '',
    this.vision = '',
    this.category = '未分类',
    this.status = QuestStatus.active,
    this.startDate = '',
    this.targetDate = '',
    this.time = '',
    this.manualProgress = 0,
    this.pinned = false,
    this.pinnedAt = '',
    this.milestones = const [],
    this.todoIds = const [],
    this.parentId = '',
    this.order = 0,
    this.archived = false,
    this.archivedAt = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // ── 派生属性（进度口径：有里程碑按里程碑，没有才用手动） ────────────────

  bool get usesMilestones => milestones.isNotEmpty;

  int get milestoneDone => milestones.where((m) => m.done).length;

  int get milestoneTotal => milestones.length;

  /// 进度 0.0~1.0
  double get progress {
    if (usesMilestones) {
      return milestoneDone / milestones.length;
    }
    return manualProgress.clamp(0, 100) / 100;
  }

  /// 进度文案
  String get progressLabel {
    if (usesMilestones) {
      return '里程碑 $milestoneDone/$milestoneTotal';
    }
    return '手动 ${manualProgress.clamp(0, 100)}%';
  }

  /// 状态文案
  String get statusLabel {
    switch (status) {
      case QuestStatus.active:
        return '进行中';
      case QuestStatus.paused:
        return '暂停';
      case QuestStatus.done:
        return '已完成';
      case QuestStatus.dropped:
        return '已放弃';
    }
  }

  /// 是否「还在推进」（用于停滞判定：已完成/放弃的不再提醒）
  bool get isLive =>
      !archived &&
      (status == QuestStatus.active || status == QuestStatus.paused);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'vision': vision,
    'category': category,
    'status': status.name,
    'startDate': startDate,
    'targetDate': targetDate,
    'time': time,
    'manualProgress': manualProgress,
    'pinned': pinned,
    'pinnedAt': pinnedAt,
    'milestones': milestones.map((m) => m.toJson()).toList(),
    'todoIds': todoIds,
    'parentId': parentId,
    'order': order,
    'archived': archived,
    'archivedAt': archivedAt,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    vision: j['vision'] as String? ?? '',
    category: j['category'] as String? ?? '未分类',
    status: QuestStatus.values.firstWhere(
      (e) => e.name == (j['status'] as String?),
      orElse: () => QuestStatus.active,
    ),
    startDate: j['startDate'] as String? ?? '',
    targetDate: j['targetDate'] as String? ?? '',
    time: j['time'] as String? ?? '',
    manualProgress: (j['manualProgress'] as num?)?.toInt() ?? 0,
    pinned: j['pinned'] as bool? ?? false,
    pinnedAt: j['pinnedAt'] as String? ?? '',
    milestones:
        (j['milestones'] as List?)
            ?.map((e) => Milestone.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    todoIds:
        (j['todoIds'] as List?)?.whereType<String>().toList() ?? const [],
    parentId: j['parentId'] as String? ?? '',
    order: (j['order'] as num?)?.toInt() ?? 0,
    archived: j['archived'] as bool? ?? false,
    archivedAt: j['archivedAt'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  Quest copyWith({
    String? title,
    String? vision,
    String? category,
    QuestStatus? status,
    String? startDate,
    String? targetDate,
    String? time,
    int? manualProgress,
    bool? pinned,
    String? pinnedAt,
    List<Milestone>? milestones,
    List<String>? todoIds,
    String? parentId,
    int? order,
    bool? archived,
    String? archivedAt,
    bool clearTargetDate = false,
    bool clearTime = false,
    bool clearPinnedAt = false,
    bool clearArchivedAt = false,
    DateTime? updatedAt,
  }) => Quest(
    id: id,
    title: title ?? this.title,
    vision: vision ?? this.vision,
    category: category ?? this.category,
    status: status ?? this.status,
    startDate: startDate ?? this.startDate,
    targetDate: clearTargetDate ? '' : (targetDate ?? this.targetDate),
    time: clearTime ? '' : (time ?? this.time),
    manualProgress: manualProgress ?? this.manualProgress,
    pinned: pinned ?? this.pinned,
    pinnedAt: clearPinnedAt ? '' : (pinnedAt ?? this.pinnedAt),
    milestones: milestones ?? this.milestones,
    todoIds: todoIds ?? this.todoIds,
    parentId: parentId ?? this.parentId,
    order: order ?? this.order,
    archived: archived ?? this.archived,
    archivedAt: clearArchivedAt ? '' : (archivedAt ?? this.archivedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 任务的派生计算（纯逻辑，便于单元测试）。
class QuestLogic {
  const QuestLogic._();

  /// 停滞判定阈值（天）：超过这么多天没有任何活动就提醒
  static const stallThresholdDays = 14;

  /// 最近活动时间 = max(任务自身更新时间, 最近一次投入时间)。
  ///
  /// 之所以把「投入」也算进去：一个任务可能很久没改字段，
  /// 但你其实一直在往里投时间，那它就不算停滞。
  static DateTime lastActivityAt(Quest q, List<InvestLog> logs) {
    var last = q.updatedAt;
    for (final l in logs) {
      if (l.at.isAfter(last)) last = l.at;
    }
    return last;
  }

  /// 距今多少天没有活动（按自然日计算）
  static int stalledDays(
    Quest q,
    List<InvestLog> logs, {
    required String today,
  }) {
    final base = DateTime.tryParse(today);
    final last = lastActivityAt(q, logs);
    if (base == null) return 0;
    final d0 = DateTime(base.year, base.month, base.day);
    final d1 = DateTime(last.year, last.month, last.day);
    final diff = d0.difference(d1).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// 是否需要提醒「停滞」：只对还在推进（进行中/暂停）的任务提醒
  static bool isStalled(
    Quest q,
    List<InvestLog> logs, {
    required String today,
    int threshold = stallThresholdDays,
  }) {
    if (!q.isLive) return false;
    return stalledDays(q, logs, today: today) >= threshold;
  }

  /// 目标日期的倒计时文案
  static String targetLabel(Quest q, String today) {
    if (q.targetDate.length < 10) return '长期 · 无期限';
    final t = DateTime.tryParse(q.targetDate);
    final base = DateTime.tryParse(today);
    if (t == null || base == null) return q.targetDate;
    final days = DateTime(t.year, t.month, t.day)
        .difference(DateTime(base.year, base.month, base.day))
        .inDays;
    if (days == 0) return '目标日期：今天';
    if (days > 0) return '距目标 $days 天';
    return '已超期 ${-days} 天';
  }

  /// 是否已超期（只对有目标日期、且还在推进的任务有意义）
  static bool isOverdue(Quest q, String today) {
    if (q.targetDate.length < 10 || !q.isLive) return false;
    return q.targetDate.compareTo(today) < 0;
  }

  /// 投入合计（分钟）
  static int totalMinutes(List<InvestLog> logs) =>
      logs.fold(0, (a, b) => a + (b.minutes < 0 ? 0 : b.minutes));

  /// 最近一次投入时间（没有则 null）
  static DateTime? lastInvestAt(List<InvestLog> logs) {
    if (logs.isEmpty) return null;
    var last = logs.first.at;
    for (final l in logs) {
      if (l.at.isAfter(last)) last = l.at;
    }
    return last;
  }

  /// 近 [weeks] 周每周投入分钟数（最后一格是本周），用于简单柱状图
  static List<int> weeklyMinutes(
    List<InvestLog> logs, {
    required String today,
    int weeks = 12,
  }) {
    final base = DateTime.tryParse(today);
    if (base == null) return List.filled(weeks, 0);
    // 本周一
    final monday = DateTime(
      base.year,
      base.month,
      base.day,
    ).subtract(Duration(days: base.weekday - 1));
    final out = List<int>.filled(weeks, 0);
    for (final l in logs) {
      final d = DateTime(l.at.year, l.at.month, l.at.day);
      // 按「该日期所在周的周一」归格，否则周日会算到下一格
      final dMonday = d.subtract(Duration(days: d.weekday - 1));
      final weeksAgo = monday.difference(dMonday).inDays ~/ 7;
      final idx = weeks - 1 - weeksAgo;
      if (idx < 0 || idx >= weeks) continue; // 窗口之外
      out[idx] += l.minutes < 0 ? 0 : l.minutes;
    }
    return out;
  }

  /// 分钟展示：`90` → `1 小时 30 分`
  static String minutesLabel(int minutes) {
    if (minutes <= 0) return '0 分';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m 分';
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分';
  }

  /// 总览排序：**钉住的排最前**（钉住时间倒序），
  /// 然后按状态（进行中 → 暂停 → 已完成 → 放弃），
  /// 再按目标日期（早的在前；无期限的排后面），最后按最近更新。
  static List<Quest> sorted(List<Quest> all) {
    final list = [...all];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.pinned && b.pinned) {
        final c = b.pinnedAt.compareTo(a.pinnedAt);
        if (c != 0) return c;
      }
      final s = a.status.index.compareTo(b.status.index);
      if (s != 0) return s;
      final at = a.targetDate.length < 10 ? '9999-99-99' : a.targetDate;
      final bt = b.targetDate.length < 10 ? '9999-99-99' : b.targetDate;
      final t = at.compareTo(bt);
      if (t != 0) return t;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// 常用的领域分类候选（界面里给快捷选择，也允许自己填）
  static const categoryOptions = [
    '工作',
    '学习',
    '健康',
    '家庭',
    '兴趣',
    '财务',
    '未分类',
  ];

  // ── 层级（子项目） ──────────────────────────────────────────────────────

  /// 未归档的任务（层级计算都在这个集合上做）
  static List<Quest> live(List<Quest> all) =>
      all.where((q) => !q.archived).toList();

  /// 某个任务的直接子项目（按 order，再按更新时间）
  static List<Quest> childrenOf(List<Quest> all, String parentId) {
    final list = all
        .where((q) => !q.archived && q.parentId == parentId)
        .toList();
    list.sort((a, b) {
      final o = a.order.compareTo(b.order);
      if (o != 0) return o;
      return a.updatedAt.compareTo(b.updatedAt);
    });
    return list;
  }

  /// 顶层任务
  static List<Quest> roots(List<Quest> all) => childrenOf(all, '');

  static bool hasChildren(List<Quest> all, String id) =>
      all.any((q) => !q.archived && q.parentId == id);

  /// 递归收集全部后代（不含自身）
  static List<Quest> descendants(List<Quest> all, String id) {
    final out = <Quest>[];
    void walk(String pid) {
      for (final c in childrenOf(all, pid)) {
        out.add(c);
        walk(c.id);
      }
    }

    walk(id);
    return out;
  }

  /// 能否把 [id] 挂到 [newParentId] 下（阻止把父任务塞进自己的子孙里，会形成环）
  static bool canMoveTo(List<Quest> all, String id, String newParentId) {
    if (id == newParentId) return false;
    if (newParentId.isEmpty) return true;
    return !descendants(all, id).any((q) => q.id == newParentId);
  }

  /// 递归深度（顶层 = 0），用于缩进
  static int depthOf(List<Quest> all, String id) {
    var depth = 0;
    var current = id;
    while (depth <= 50) {
      Quest? node;
      for (final q in all) {
        if (q.id == current) node = q;
      }
      if (node == null || node.parentId.isEmpty) break;
      depth++;
      current = node.parentId;
    }
    return depth;
  }

  /// 已了结 = 已完成或已放弃。
  ///
  /// 放弃过的子项目**不该永远卡住父任务**，所以「可完成」判定把它算了结。
  static bool isResolved(Quest q) =>
      q.status == QuestStatus.done || q.status == QuestStatus.dropped;

  /// 阻碍完成 [id] 的子项目（空 = 可以完成）
  static List<Quest> blockersForDone(List<Quest> all, String id) =>
      childrenOf(all, id).where((c) => !isResolved(c)).toList();

  // ── 加权进度 ────────────────────────────────────────────────────────────

  /// 任务**自身**的进度（不考虑子项目）：有里程碑按里程碑，否则手动百分比
  static double baseProgress(Quest q) {
    if (q.usesMilestones) return q.milestoneDone / q.milestoneTotal;
    return q.manualProgress.clamp(0, 100) / 100;
  }

  /// 工作量因子：子树最底层节点数（没有子项目 = 1）
  static int leafCount(List<Quest> all, String id) {
    final kids = childrenOf(all, id);
    if (kids.isEmpty) return 1;
    var sum = 0;
    for (final k in kids) {
      sum += leafCount(all, k.id);
    }
    return sum;
  }

  /// 子树里程碑总数（含自身与全部后代）
  static int subtreeMilestones(List<Quest> all, String id) {
    var sum = 0;
    for (final q in all) {
      if (q.id == id) sum += q.milestones.length;
    }
    for (final d in descendants(all, id)) {
      sum += d.milestones.length;
    }
    return sum;
  }

  /// 子树累计投入分钟（含自身与全部后代）
  static int subtreeInvest(
    List<Quest> all,
    Map<String, List<InvestLog>> logs,
    String id,
  ) {
    var sum = totalMinutes(logs[id] ?? const <InvestLog>[]);
    for (final d in descendants(all, id)) {
      sum += totalMinutes(logs[d.id] ?? const <InvestLog>[]);
    }
    return sum;
  }

  /// 一次算出**全部任务**的进度（递归加权，自底向上）。
  ///
  /// 有子项目 → 子项目进度按权重合成；没有子项目 → [baseProgress]。
  /// 权重 = 三个因子在**同一父节点的兄弟之间归一化**后，按 [weights] 加权求和：
  /// 工作量（子树叶子数）/ 已投入时间（子树累计分钟）/ 里程碑数（子树总数）。
  ///
  /// 归一化是必须的：三个因子量纲完全不同（件数 / 分钟 / 个数），
  /// 不归一化的话「分钟数」会直接碾压其它两项。
  static Map<String, double> progressMap(
    List<Quest> all,
    Map<String, List<InvestLog>> logs, [
    QuestWeights weights = QuestWeights.defaults,
  ]) {
    final pool = live(all);
    final out = <String, double>{};
    final w = weights.normalized();

    double calc(String id) {
      final cached = out[id];
      if (cached != null) return cached;
      Quest? self;
      for (final q in pool) {
        if (q.id == id) self = q;
      }
      if (self == null) return 0;
      final kids = childrenOf(pool, id);
      double value;
      if (kids.isEmpty) {
        value = baseProgress(self);
      } else {
        final work = <String, double>{};
        final invest = <String, double>{};
        final ms = <String, double>{};
        for (final k in kids) {
          work[k.id] = leafCount(pool, k.id).toDouble();
          invest[k.id] = subtreeInvest(pool, logs, k.id).toDouble();
          ms[k.id] = subtreeMilestones(pool, k.id).toDouble();
        }
        double maxOf(Map<String, double> m) =>
            m.values.fold(0.0, (a, b) => b > a ? b : a);
        final maxWork = maxOf(work);
        final maxInvest = maxOf(invest);
        final maxMs = maxOf(ms);
        // 先算每行的权重；某项在兄弟里全为 0 时该项整体失效（不参与）
        final raw = <String, double>{};
        for (final k in kids) {
          final nw = maxWork <= 0 ? 0.0 : work[k.id]! / maxWork;
          final ni = maxInvest <= 0 ? 0.0 : invest[k.id]! / maxInvest;
          final nm = maxMs <= 0 ? 0.0 : ms[k.id]! / maxMs;
          raw[k.id] = w.work * nw + w.invest * ni + w.milestone * nm;
        }
        // 整组权重都为 0（例如用户把比例全给了「投入」但谁都没记投入）
        // → 等权回退。**不能逐行回退**：那会让权重本来就是 0 的子项目凭空获得
        // 权重，把父进度稀释成平均值（有测试锁死这个行为）。
        final totalRaw = raw.values.fold(0.0, (a, b) => a + b);
        final useEqual = totalRaw <= 0;
        var sumW = 0.0, sumP = 0.0;
        for (final k in kids) {
          final weight = useEqual ? 1.0 : raw[k.id]!;
          sumW += weight;
          sumP += calc(k.id) * weight;
        }
        value = sumW <= 0 ? 0 : sumP / sumW;
      }
      out[id] = value;
      return value;
    }

    for (final q in pool) {
      calc(q.id);
    }
    return out;
  }
}

/// 任务的汇总统计（详情页用）
class QuestStats {
  final int investCount;
  final int totalMinutes;
  final int stalledDays;

  const QuestStats({
    required this.investCount,
    required this.totalMinutes,
    required this.stalledDays,
  });

  /// 从一组投入记录算出统计；[today] 为 yyyy-MM-dd
  factory QuestStats.of(Quest q, List<InvestLog> logs, String today) =>
      QuestStats(
        investCount: logs.length,
        totalMinutes: QuestLogic.totalMinutes(logs),
        stalledDays: QuestLogic.stalledDays(q, logs, today: today),
      );

  String get totalLabel => QuestLogic.minutesLabel(totalMinutes);
}

/// 父任务进度的加权系数（三个因子：工作量 / 已投入时间 / 里程碑数）。
///
/// 默认 **0.5 : 0.3 : 0.2**：
/// - **工作量**（子树叶子数）最稳定 —— 件数不会因为「漏记投入」而失真；
/// - **已投入时间**客观，但依赖你是否记得记投入；
/// - **里程碑数**容易被「多拆几个小阶段」灌水，所以占比最低。
///
/// 可在任务总览页调整，存 `settings/ui.json` 的 `questWeights`。
class QuestWeights {
  final double work;
  final double invest;
  final double milestone;

  const QuestWeights({
    this.work = 0.5,
    this.invest = 0.3,
    this.milestone = 0.2,
  });

  static const QuestWeights defaults = QuestWeights();

  double get sum => work + invest + milestone;

  bool get isZero => sum <= 0;

  /// 归一化到「和为 1」（和为 0 时退回默认）
  QuestWeights normalized() {
    if (isZero) return defaults;
    return QuestWeights(
      work: work / sum,
      invest: invest / sum,
      milestone: milestone / sum,
    );
  }

  Map<String, dynamic> toJson() => {
    'work': work,
    'invest': invest,
    'milestone': milestone,
  };

  /// 容错解析：任何异常（缺失 / 类型不对 / 全 0）都回退默认
  factory QuestWeights.fromJson(Object? j) {
    if (j is! Map) return defaults;
    double pick(String key, double fallback) {
      final v = j[key];
      if (v is num) {
        final d = v.toDouble();
        if (d < 0) return 0;
        if (d > 1) return 1;
        return d;
      }
      return fallback;
    }

    final w = QuestWeights(
      work: pick('work', defaults.work),
      invest: pick('invest', defaults.invest),
      milestone: pick('milestone', defaults.milestone),
    );
    return w.isZero ? defaults : w;
  }

  /// 展示成 `0.50 : 0.30 : 0.20`
  String get label =>
      '${work.toStringAsFixed(2)} : ${invest.toStringAsFixed(2)}'
      ' : ${milestone.toStringAsFixed(2)}';
}
