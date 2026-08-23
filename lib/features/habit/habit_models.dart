import '../../core/models/common.dart';

/// 习惯统计类型
enum HabitType { duration, count }

/// 习惯目标
class HabitTarget {
  final HabitType type;
  final int value; // 目标天数 / 目标次数

  const HabitTarget({this.type = HabitType.count, this.value = 30});

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory HabitTarget.fromJson(Map<String, dynamic>? j) => j == null
      ? const HabitTarget()
      : HabitTarget(
          type: HabitType.values.firstWhere(
            (e) => e.name == j['type'],
            orElse: () => HabitType.count,
          ),
          value: (j['value'] as num?)?.toInt() ?? 30,
        );
}

/// 习惯（一种特殊的长期任务）
class Habit {
  final String id;
  final String title;
  final String category;
  final HabitTarget target;
  final String description; // 描述（纯文本）
  final List<MediaAttachment> media;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Habit({
    required this.id,
    this.title = '',
    this.category = '通用',
    this.target = const HabitTarget(),
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
    'target': target.toJson(),
    'description': description,
    'media': media.map((m) => m.toJson()).toList(),
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    category: json['category'] as String? ?? '通用',
    target: HabitTarget.fromJson(json['target'] as Map<String, dynamic>?),
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

  Habit copyWith({
    String? title,
    String? category,
    HabitTarget? target,
    String? description,
    List<MediaAttachment>? media,
    List<String>? tags,
    DateTime? updatedAt,
  }) => Habit(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    target: target ?? this.target,
    description: description ?? this.description,
    media: media ?? this.media,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 打卡记录：某习惯在某天的完成状态
class CheckinMap {
  final Map<String, int> entries; // date(yyyy-MM-dd) -> 次数

  const CheckinMap({this.entries = const {}});

  int get totalCount => entries.values.fold(0, (a, b) => a + b);

  int get totalDays => entries.length;

  /// 连续打卡天数（从今天往前）
  int streakDays(DateTime today) {
    var streak = 0;
    var d = today;
    while (true) {
      final key = AppTime.dateOnly(d);
      final v = entries[key];
      if (v == null || v == 0) {
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
