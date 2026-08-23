import '../../core/models/common.dart';

/// 待办状态
enum TodoStatus { pending, done, archived }

/// 文本模式
enum TodoMode { plain, rich }

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

/// 待办条目
class TodoItem {
  final String id;
  final String title;
  final TodoMode mode;
  final String contentPlain; // 纯文本
  final String contentRich; // 富文本 Delta JSON
  final DeadlineInfo deadline;
  final LocationInfo location;
  final TodoStatus status;
  final String? taskChainId;
  final List<MediaAttachment> media;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoItem({
    required this.id,
    this.title = '',
    this.mode = TodoMode.plain,
    this.contentPlain = '',
    this.contentRich = '',
    this.deadline = const DeadlineInfo(),
    this.location = const LocationInfo(),
    this.status = TodoStatus.pending,
    this.taskChainId,
    this.media = const [],
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mode': mode.name,
    'contentPlain': contentPlain,
    'contentRich': contentRich,
    'deadline': deadline.toJson(),
    'location': location.toJson(),
    'status': status.name,
    if (taskChainId != null) 'taskChainId': taskChainId,
    'media': media.map((m) => m.toJson()).toList(),
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    mode: TodoMode.values.firstWhere(
      (e) => e.name == json['mode'],
      orElse: () => TodoMode.plain,
    ),
    contentPlain: json['contentPlain'] as String? ?? '',
    contentRich: json['contentRich'] as String? ?? '',
    deadline: DeadlineInfo.fromJson(json['deadline'] as Map<String, dynamic>?),
    location: LocationInfo.fromJson(json['location'] as Map<String, dynamic>?),
    status: TodoStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => TodoStatus.pending,
    ),
    taskChainId: json['taskChainId'] as String?,
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

  TodoItem copyWith({
    String? title,
    TodoMode? mode,
    String? contentPlain,
    String? contentRich,
    DeadlineInfo? deadline,
    LocationInfo? location,
    TodoStatus? status,
    String? taskChainId,
    List<MediaAttachment>? media,
    List<String>? tags,
    DateTime? updatedAt,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    contentPlain: contentPlain ?? this.contentPlain,
    contentRich: contentRich ?? this.contentRich,
    deadline: deadline ?? this.deadline,
    location: location ?? this.location,
    status: status ?? this.status,
    taskChainId: taskChainId ?? this.taskChainId,
    media: media ?? this.media,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 任务链子任务
class ChainSubTask {
  final String id;
  final String title;
  final bool done;

  const ChainSubTask({required this.id, this.title = '', this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory ChainSubTask.fromJson(Map<String, dynamic> j) => ChainSubTask(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    done: j['done'] as bool? ?? false,
  );

  ChainSubTask copyWith({String? title, bool? done}) =>
      ChainSubTask(id: id, title: title ?? this.title, done: done ?? this.done);
}

/// 任务链（抽箱式长期任务）
class TaskChain {
  final String id;
  final String title;
  final String goal;
  final List<ChainSubTask> subTasks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskChain({
    required this.id,
    this.title = '',
    this.goal = '',
    this.subTasks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  double get progress => subTasks.isEmpty
      ? 0
      : subTasks.where((s) => s.done).length / subTasks.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'goal': goal,
    'subTasks': subTasks.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TaskChain.fromJson(Map<String, dynamic> json) => TaskChain(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    goal: json['goal'] as String? ?? '',
    subTasks:
        (json['subTasks'] as List?)
            ?.map((e) => ChainSubTask.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  TaskChain copyWith({
    String? title,
    String? goal,
    List<ChainSubTask>? subTasks,
    DateTime? updatedAt,
  }) => TaskChain(
    id: id,
    title: title ?? this.title,
    goal: goal ?? this.goal,
    subTasks: subTasks ?? this.subTasks,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 待办模板：可整体保存并在新建待办时一键套用。
/// 包含标题预设、内容（纯文本 / 富文本）、截止时间、地点、标签。
class TodoTemplate {
  final String id;
  final String name;
  final String title;
  final TodoMode mode;
  final String contentPlain;
  final String contentRich;
  final DeadlineInfo deadline;
  final LocationInfo location;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoTemplate({
    required this.id,
    this.name = '',
    this.title = '',
    this.mode = TodoMode.plain,
    this.contentPlain = '',
    this.contentRich = '',
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
    'mode': mode.name,
    'contentPlain': contentPlain,
    'contentRich': contentRich,
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
    mode: TodoMode.values.firstWhere(
      (e) => e.name == json['mode'],
      orElse: () => TodoMode.plain,
    ),
    contentPlain: json['contentPlain'] as String? ?? '',
    contentRich: json['contentRich'] as String? ?? '',
    deadline: DeadlineInfo.fromJson(json['deadline'] as Map<String, dynamic>?),
    location: LocationInfo.fromJson(json['location'] as Map<String, dynamic>?),
    tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
