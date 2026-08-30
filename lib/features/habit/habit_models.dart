import '../../core/models/common.dart';

/// 习惯频率：决定该在何时打卡
enum HabitFrequency {
  daily, // 每天
  weekly, // 每周固定几天
  interval, // 每 N 天一次
  weeklyTimes, // 每周累计 N 次
}

/// 当天目标：一天完成多少才算完成当天打卡
enum HabitDailyTarget {
  once, // 一次即完成
  quantity, // 当天累计 N 次/量达标
  minutes, // 当天累计 N 分钟达标
}

/// 坚持周期：习惯存在的窗口
enum HabitPersistence {
  unlimited, // 不限（一直存在）
  days, // 坚持 N 天
  times, // 累计打卡 N 次
  cycles, // N 天一轮，多轮循环
}

/// 习惯（一种特殊的长期任务）
///
/// 三个维度共同决定一个习惯的节奏与存在：
/// - [frequency]  ：该在何时打卡
/// - [dailyTarget]：一天完成多少算完成当天打卡
/// - [persistence]：习惯存在的窗口 / 坚持周期
///
/// 兼容旧数据：旧版只有 `target`（按次数或按天数）。读取旧 JSON 时，
/// 若缺少新增字段，会按「目标天数→坚持 days、目标次数→坚持 times」迁移，
/// 并给频率 / 当天目标赋默认值，保证旧的已创建习惯不失效。
class Habit {
  final String id;
  final String title;
  final String category;
  final HabitFrequency frequency;
  final List<int> weekdays; // 每周哪几天（1=周一 ... 7=周日），仅 frequency==weekly
  final int intervalDays; // 每 N 天，仅 frequency==interval
  final int weeklyTimes; // 每周 N 次，仅 frequency==weeklyTimes
  final HabitDailyTarget dailyTarget;
  final int dailyTargetValue; // 当天目标数值（quantity 次数 / minutes 分钟）
  final HabitPersistence persistence;
  final int persistenceValue; // 坚持周期数值（days 天数 / times 次数 / cycles 天数一轮）
  final bool archived; // 是否已移到回收站（达成目标自动归档或手动归档）
  final String description; // 描述（纯文本）
  final List<MediaAttachment> media;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Habit({
    required this.id,
    this.title = '',
    this.category = '通用',
    this.frequency = HabitFrequency.daily,
    this.weekdays = const [],
    this.intervalDays = 1,
    this.weeklyTimes = 1,
    this.dailyTarget = HabitDailyTarget.once,
    this.dailyTargetValue = 1,
    this.persistence = HabitPersistence.unlimited,
    this.persistenceValue = 0,
    this.archived = false,
    this.description = '',
    this.media = const [],
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'frequency': frequency.name,
    'weekdays': weekdays,
    'intervalDays': intervalDays,
    'weeklyTimes': weeklyTimes,
    'dailyTarget': dailyTarget.name,
    'dailyTargetValue': dailyTargetValue,
    'persistence': persistence.name,
    'persistenceValue': persistenceValue,
    'archived': archived,
    'description': description,
    'media': media.map((m) => m.toJson()).toList(),
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Habit.fromJson(Map<String, dynamic> json) {
    // —— 旧数据兼容迁移 ——
    // 旧版只有 target.type（count/duration）+ target.value。
    var persistence = HabitPersistence.unlimited;
    var persistenceValue = 0;
    final oldTarget = json['target'] as Map<String, dynamic>?;
    if (oldTarget != null) {
      final type = oldTarget['type'] as String? ?? 'count';
      final value = (oldTarget['value'] as num?)?.toInt() ?? 0;
      if (type == 'duration') {
        persistence = HabitPersistence.days;
        persistenceValue = value;
      } else {
        persistence = HabitPersistence.times;
        persistenceValue = value;
      }
    }
    // 新增字段：若 JSON 无此字段则用默认值（或从 legacy 迁移）
    persistence = HabitPersistence.values.firstWhere(
      (e) => e.name == (json['persistence'] as String?),
      orElse: () => persistence,
    );
    persistenceValue = (json['persistenceValue'] as num?)?.toInt() ??
        persistenceValue;

    return Habit(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '通用',
      frequency: HabitFrequency.values.firstWhere(
        (e) => e.name == (json['frequency'] as String?),
        orElse: () => HabitFrequency.daily,
      ),
      weekdays: (json['weekdays'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const [],
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 1,
      weeklyTimes: (json['weeklyTimes'] as num?)?.toInt() ?? 1,
      dailyTarget: HabitDailyTarget.values.firstWhere(
        (e) => e.name == (json['dailyTarget'] as String?),
        orElse: () => HabitDailyTarget.once,
      ),
      dailyTargetValue: (json['dailyTargetValue'] as num?)?.toInt() ?? 1,
      persistence: persistence,
      persistenceValue: persistenceValue,
      archived: json['archived'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      media:
          (json['media'] as List?)
              ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Habit copyWith({
    String? title,
    String? category,
    HabitFrequency? frequency,
    List<int>? weekdays,
    int? intervalDays,
    int? weeklyTimes,
    HabitDailyTarget? dailyTarget,
    int? dailyTargetValue,
    HabitPersistence? persistence,
    int? persistenceValue,
    bool? archived,
    String? description,
    List<MediaAttachment>? media,
    List<String>? tags,
    DateTime? updatedAt,
  }) => Habit(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    frequency: frequency ?? this.frequency,
    weekdays: weekdays ?? this.weekdays,
    intervalDays: intervalDays ?? this.intervalDays,
    weeklyTimes: weeklyTimes ?? this.weeklyTimes,
    dailyTarget: dailyTarget ?? this.dailyTarget,
    dailyTargetValue: dailyTargetValue ?? this.dailyTargetValue,
    persistence: persistence ?? this.persistence,
    persistenceValue: persistenceValue ?? this.persistenceValue,
    archived: archived ?? this.archived,
    description: description ?? this.description,
    media: media ?? this.media,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 打卡记录：某习惯在某天的状态。
/// entries: date(yyyy-MM-dd) -> 数值
///   - 正数：当天完成打卡的次数（次数型习惯可能一天多次，记为累加值）
///   - -1  : 当天标记为「失败」
///   - 无记录：当天未操作
class CheckinMap {
  final Map<String, int> entries; // date(yyyy-MM-dd) -> 数值

  const CheckinMap({this.entries = const {}});

  /// 完成打卡总次数（只统计正数，排除失败）
  int get totalCount =>
      entries.values.where((v) => v > 0).fold(0, (a, b) => a + b);

  /// 完成打卡的天数（只统计正数，排除失败）
  int get totalDays => entries.values.where((v) => v > 0).length;

  /// 标记为失败的天数
  int get failedDays => entries.values.where((v) => v < 0).length;

  /// 某天是否完成（正数）
  bool isDone(String date) => (entries[date] ?? 0) > 0;

  /// 某天是否失败（负数）
  bool isFailed(String date) => (entries[date] ?? 0) < 0;

  /// 某天是否有记录（完成或失败）
  bool hasRecord(String date) => entries.containsKey(date);

  /// 某天累积值（非负数，失败/无记录返回 0）
  int dayValue(String date) {
    final v = entries[date] ?? 0;
    return v < 0 ? 0 : v;
  }

  /// 某天是否达到「当天目标」。
  /// [target] 当天目标类型，[targetValue] 目标数值（once 时忽略）。
  bool dayMet(String date, HabitDailyTarget target, int targetValue) {
    final v = dayValue(date);
    switch (target) {
      case HabitDailyTarget.once:
        return v >= 1;
      case HabitDailyTarget.quantity:
        return v >= (targetValue <= 0 ? 1 : targetValue);
      case HabitDailyTarget.minutes:
        return v >= (targetValue <= 0 ? 1 : targetValue);
    }
  }

  /// 连续打卡天数（从今天往前，按「达标」计）。
  /// [isMet] 判断某天是否达标；失败 / 未达标 / 未记录则不连续；
  /// 今天尚未打卡时允许从昨天开始算。
  int streakDays(DateTime today, {bool Function(String date)? isMet}) {
    final met = isMet ?? (d) => (entries[d] ?? 0) > 0;
    var streak = 0;
    var d = today;
    while (true) {
      final key = AppTime.dateOnly(d);
      if (!met(key)) {
        // 允许今天还没打卡时从昨天开始算
        if (streak == 0 && key == AppTime.dateOnly(today)) {
          d = d.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Map<String, dynamic> toJson() => entries;

  factory CheckinMap.fromJson(Map<String, dynamic>? j) => CheckinMap(
    entries: (j ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
  );
}
