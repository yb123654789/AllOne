import '../../core/models/common.dart';

/// 待办状态
enum TodoStatus { pending, done, archived }

/// 截止时间（带颜色与高亮）
class DeadlineInfo {
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final String color; // hex
  final bool highlight;

  const DeadlineInfo({
    this.date = '',
    this.time = '',
    this.color = '#E5484D',
    this.highlight = false,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'time': time,
    'color': color,
    'highlight': highlight,
  };

  factory DeadlineInfo.fromJson(Map<String, dynamic>? j) => j == null
      ? const DeadlineInfo()
      : DeadlineInfo(
          date: j['date'] as String? ?? '',
          time: j['time'] as String? ?? '',
          color: j['color'] as String? ?? '#E5484D',
          highlight: j['highlight'] as bool? ?? false,
        );
}

/// 地点（带颜色与高亮）
class LocationInfo {
  final String text;
  final String color;
  final bool highlight;
  final double lat;
  final double lng;

  const LocationInfo({
    this.text = '',
    this.color = '#1E88E5',
    this.highlight = false,
    this.lat = 0,
    this.lng = 0,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'color': color,
    'highlight': highlight,
    'lat': lat,
    'lng': lng,
  };

  factory LocationInfo.fromJson(Map<String, dynamic>? j) => j == null
      ? const LocationInfo()
      : LocationInfo(
          text: j['text'] as String? ?? '',
          color: j['color'] as String? ?? '#1E88E5',
          highlight: j['highlight'] as bool? ?? false,
          lat: (j['lat'] as num?)?.toDouble() ?? 0,
          lng: (j['lng'] as num?)?.toDouble() ?? 0,
        );
}

/// 待办条目（树形：可包含子任务，任意层级嵌套）。
/// 普通待办 = 没有子任务的条目；任务链 = 嵌套了子任务的普通待办。
class TodoItem {
  final String id;
  final String title;
  final String contentPlain; // 纯文本
  final DeadlineInfo deadline;
  final LocationInfo location;
  final TodoStatus status;
  final List<MediaAttachment> media;
  final List<String> tags;

  /// 子任务（递归嵌套，任意层级）
  final List<TodoItem> children;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoItem({
    required this.id,
    this.title = '',
    this.contentPlain = '',
    this.deadline = const DeadlineInfo(),
    this.location = const LocationInfo(),
    this.status = TodoStatus.pending,
    this.media = const [],
    this.tags = const [],
    this.children = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasChildren => children.isNotEmpty;

  /// 进度：直接子任务中已完成的占比（无子任务则为 0/1 空）
  double get progress => children.isEmpty
      ? 0
      : children.where((c) => c.status == TodoStatus.done).length /
            children.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'contentPlain': contentPlain,
    'deadline': deadline.toJson(),
    'location': location.toJson(),
    'status': status.name,
    'media': media.map((m) => m.toJson()).toList(),
    'tags': tags,
    'children': children.map((c) => c.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    contentPlain: json['contentPlain'] as String? ?? '',
    deadline: DeadlineInfo.fromJson(json['deadline'] as Map<String, dynamic>?),
    location: LocationInfo.fromJson(json['location'] as Map<String, dynamic>?),
    status: TodoStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => TodoStatus.pending,
    ),
    media:
        (json['media'] as List?)
            ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    children:
        (json['children'] as List?)
            ?.map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  TodoItem copyWith({
    String? title,
    String? contentPlain,
    DeadlineInfo? deadline,
    LocationInfo? location,
    TodoStatus? status,
    List<MediaAttachment>? media,
    List<String>? tags,
    List<TodoItem>? children,
    DateTime? updatedAt,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    contentPlain: contentPlain ?? this.contentPlain,
    deadline: deadline ?? this.deadline,
    location: location ?? this.location,
    status: status ?? this.status,
    media: media ?? this.media,
    tags: tags ?? this.tags,
    children: children ?? this.children,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 待办模板：可整体保存并在新建待办时一键套用。
/// 包含标题预设、内容（纯文本）、截止时间、地点、标签。
class TodoTemplate {
  final String id;
  final String name;
  final String title;
  final String contentPlain;
  final DeadlineInfo deadline;
  final LocationInfo location;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoTemplate({
    required this.id,
    this.name = '',
    this.title = '',
    this.contentPlain = '',
    this.deadline = const DeadlineInfo(),
    this.location = const LocationInfo(),
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'title': title,
    'contentPlain': contentPlain,
    'deadline': deadline.toJson(),
    'location': location.toJson(),
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TodoTemplate.fromJson(Map<String, dynamic> json) => TodoTemplate(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    title: json['title'] as String? ?? '',
    contentPlain: json['contentPlain'] as String? ?? '',
    deadline: DeadlineInfo.fromJson(json['deadline'] as Map<String, dynamic>?),
    location: LocationInfo.fromJson(json['location'] as Map<String, dynamic>?),
    tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
