/// 特殊日子 / 节假日（在日历界面直接创建，不属于待办或习惯）
///
/// 除了「某一天」的标记，这里还承担**倒数日**的计算：
/// 支持「每年重复」（生日 / 纪念日），并提供距今天数与倒计时文案。
///
/// 生命周期（与 `special_day_lifecycle.dart` 配合）：
/// - **单次**（`repeatYearly == false`）：过了那一天就“过期”，由用户在倒数日页
///   确认后移入回收站（`archived = true`，当天不算过期，次日才算）。
/// - **每年重复**：过了那一天就自动把 [date] 推进到**下一次**的发生日期；
///   原始日期记在 [originDate] 里，因此「第 N 周年」不会因为推进而丢失。
class SpecialDay {
  final String id;

  /// yyyy-MM-dd。每年重复时表示**当前有效的那一次**（会自动推进到下一次）。
  final String date;

  /// 原始日期 yyyy-MM-dd：每年重复时用来算「第 N 周年」。
  ///
  /// 旧数据 / 未推进过的数据为 null，此时回退用 [date]。
  final String? originDate;

  final String name;
  final String type; // holiday / custom
  final String color; // hex

  /// 是否每年重复（生日、纪念日等）。旧数据没有这个字段，默认 false。
  final bool repeatYearly;

  /// 是否已移入回收站（只有单次项会归档）。
  final bool archived;

  /// 归档日期 yyyy-MM-dd（仅用于回收站里排序 / 展示）。
  final String? archivedAt;

  const SpecialDay({
    required this.id,
    required this.date,
    this.originDate,
    this.name = '',
    this.type = 'custom',
    this.color = '#E5484D',
    this.repeatYearly = false,
    this.archived = false,
    this.archivedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    if (originDate != null) 'originDate': originDate,
    'name': name,
    'type': type,
    'color': color,
    'repeatYearly': repeatYearly,
    'archived': archived,
    if (archivedAt != null) 'archivedAt': archivedAt,
  };

  factory SpecialDay.fromJson(Map<String, dynamic> j) => SpecialDay(
    id: j['id'] as String? ?? '',
    date: j['date'] as String? ?? '',
    originDate: j['originDate'] as String?,
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'custom',
    color: j['color'] as String? ?? '#E5484D',
    repeatYearly: j['repeatYearly'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
    archivedAt: j['archivedAt'] as String?,
  );

  /// 是否是用户自己建的日子（内置节假日不可编辑 / 删除 / 参与倒数）
  bool get isCustom => type == 'custom';

  /// 算周年用的基准日期：优先原始日期（旧数据回退到 date）
  String get anniversaryBase => originDate ?? date;

  SpecialDay copyWith({
    String? name,
    String? color,
    bool? repeatYearly,
    String? date,
    String? originDate,
    bool? archived,
    String? archivedAt,
    bool clearArchivedAt = false,
  }) => SpecialDay(
    id: id,
    date: date ?? this.date,
    originDate: originDate ?? this.originDate,
    name: name ?? this.name,
    type: type,
    color: color ?? this.color,
    repeatYearly: repeatYearly ?? this.repeatYearly,
    archived: archived ?? this.archived,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
  );

  /// 是否落在某一天（yyyy-MM-dd）。每年重复时只比较「月-日」。
  bool occursOn(String day) {
    if (day.length < 10) return false;
    if (!repeatYearly) return date == day;
    if (date.length < 10) return false;
    return date.substring(5, 10) == day.substring(5, 10);
  }

  /// 是否落在某个月（yyyy-MM）。每年重复的日子每年都算。
  bool inMonth(String ym) {
    if (date.length < 7 || ym.length < 7) return false;
    if (repeatYearly) return date.substring(5, 7) == ym.substring(5, 7);
    return date.substring(0, 7) == ym;
  }

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  /// 平年里的 2 月 29 日顺延到 2 月 28 日。
  ///
  /// 不这样处理的话 `'2027-02-29'` 是个不存在的日期，解析会失败，
  /// 倒数会退化成「今天」（旧实现的实际表现）。
  static String _clampMonthDay(int year, String md) {
    if (md == '02-29' && !_isLeap(year)) return '$year-02-28';
    return '$year-$md';
  }

  /// 下一次发生的日期（yyyy-MM-dd）。
  ///
  /// - 不重复：就是自身日期（可能已经过去）；
  /// - 每年重复：今年的那一天，已经过了就取明年；平年 2/29 顺延 2/28。
  String nextDate(String today) {
    if (!repeatYearly || date.length < 10 || today.length < 10) return date;
    final year = int.tryParse(today.substring(0, 4));
    if (year == null) return date;
    final md = date.substring(5, 10);
    for (var y = year; y <= year + 1; y++) {
      final candidate = _clampMonthDay(y, md);
      if (candidate.compareTo(today) >= 0) return candidate;
    }
    return _clampMonthDay(year + 1, md);
  }

  /// 距今天数：0 = 今天，正数 = 还有几天，负数 = 已经过去几天。
  /// 每年重复的日子永远取「下一次」，不会变成负数。
  int daysFrom(String today) {
    final target = DateTime.tryParse(nextDate(today));
    final base = DateTime.tryParse(today);
    if (target == null || base == null) return 0;
    return DateTime(target.year, target.month, target.day)
        .difference(DateTime(base.year, base.month, base.day))
        .inDays;
  }

  /// 倒计时文案：今天 / 还有 N 天 / 已过 N 天
  String countdownLabel(String today) {
    final d = daysFrom(today);
    if (d == 0) return '今天';
    if (d > 0) return '还有 $d 天';
    return '已过 ${-d} 天';
  }

  /// 每年重复的纪念日：这是第几周年（明年才到就返回下一个周年数）；
  /// 不重复、或起始日期还没到，返回 null。
  int? anniversaryYears(String today) {
    if (!repeatYearly || date.length < 10 || today.length < 10) return null;
    final origin = int.tryParse(anniversaryBase.substring(0, 4));
    final next = int.tryParse(nextDate(today).substring(0, 4));
    if (origin == null || next == null || next <= origin) return null;
    return next - origin;
  }

  // ── 生命周期 ────────────────────────────────────────────────────────────

  /// 单次项是否已经「过期」（当天不算：只有日期严格早于今天才算过了）。
  ///
  /// 已归档的不再重复计入。
  bool isExpiredOn(String today) {
    if (repeatYearly || archived) return false;
    if (date.length < 10 || today.length < 10) return false;
    return date.compareTo(today) < 0;
  }

  /// 是否已进回收站
  bool get isTrashed => archived;

  /// 每年重复项推进到「下一次」：已经过了就改成下一次的发生日期。
  ///
  /// 原始日期只在第一次推进时写入 [originDate]，保证「第 N 周年」始终正确。
  /// 没有变化时原样返回（便于「无变化就不写盘」）。
  SpecialDay advancedTo(String today) {
    if (!repeatYearly || archived) return this;
    if (date.length < 10 || today.length < 10) return this;
    final next = nextDate(today);
    if (next == date) return this;
    return copyWith(date: next, originDate: originDate ?? date);
  }

  /// 移入回收站
  ///
  /// **每年重复的日子永不归档**：它是常驻的（生日每年都要提醒），
  /// 万一被归档就会从日历和倒数日里彻底消失，且再也不会自动出现。
  /// 因此这里直接忽略这种请求（返回自身 = 未变化）。
  SpecialDay archivedOn(String today) {
    if (archived || repeatYearly) return this;
    return copyWith(archived: true, archivedAt: today);
  }

  /// 从回收站恢复
  SpecialDay restored() => archived
      ? copyWith(archived: false, clearArchivedAt: true)
      : this;
}
