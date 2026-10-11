import '../../core/models/common.dart';

/// 待办状态
enum TodoStatus { pending, done, archived }

/// 待办的排序方式（**只管顶层列表**）。
///
/// 子任务的顺序始终由父节点的 `children` 数组顺序决定（数组顺序即顺序），
/// 不参与这里的排序 —— 否则你手调过的子任务顺序会被自动排序覆盖。
enum TodoSortMode {
  manual, // 手动（order 字段）
  deadline, // 截止时间
  created, // 创建时间
  title, // 标题
}

extension TodoSortModeX on TodoSortMode {
  String get label {
    switch (this) {
      case TodoSortMode.manual:
        return '手动排序';
      case TodoSortMode.deadline:
        return '按截止时间';
      case TodoSortMode.created:
        return '按创建时间';
      case TodoSortMode.title:
        return '按标题';
    }
  }

  String get hint {
    switch (this) {
      case TodoSortMode.manual:
        return '你自己排的顺序，用每条「⋮」里的「上移 / 下移」调整';
      case TodoSortMode.deadline:
        return '截止时间近的在前；没有截止时间的排最后';
      case TodoSortMode.created:
        return '最近创建的在前';
      case TodoSortMode.title:
        return '按标题升序';
    }
  }
}

/// 从偏好里的字符串解析排序方式（未知值回退「截止时间」）
TodoSortMode todoSortModeFrom(Object? key) => TodoSortMode.values.firstWhere(
  (m) => m.name == key,
  orElse: () => TodoSortMode.deadline,
);

/// 顶层待办排序（纯函数，便于单元测试）。
///
/// 「未完成在前」在除手动之外的模式下都保留：已完成 / 已归档的条目即使
/// 还在列表里，也不会插到你正在处理的待办之间。
List<TodoItem> sortTodos(List<TodoItem> items, TodoSortMode mode) {
  final list = [...items];
  // 除手动模式外，都先把「未完成」抬到前面（状态稳定排序）
  int byStatus(TodoItem a, TodoItem b) {
    if (a.status == b.status) return 0;
    return a.status == TodoStatus.pending ? -1 : 1;
  }

  switch (mode) {
    case TodoSortMode.manual:
      list.sort((a, b) {
        final o = a.order.compareTo(b.order);
        if (o != 0) return o;
        return a.createdAt.compareTo(b.createdAt);
      });
    case TodoSortMode.deadline:
      list.sort((a, b) {
        final s = byStatus(a, b);
        if (s != 0) return s;
        final ad = a.deadline.date;
        final bd = b.deadline.date;
        // 没有截止时间的排最后（以前是空串排最前，这里是刻意改的：
        // 「新建待办按截止时间插位」也遵循同一规则，两处保持一致）
        if (ad.isEmpty != bd.isEmpty) return ad.isEmpty ? 1 : -1;
        final c = (ad + a.deadline.time).compareTo(bd + b.deadline.time);
        if (c != 0) return c;
        return a.createdAt.compareTo(b.createdAt);
      });
    case TodoSortMode.created:
      list.sort((a, b) {
        final s = byStatus(a, b);
        if (s != 0) return s;
        return b.createdAt.compareTo(a.createdAt);
      });
    case TodoSortMode.title:
      list.sort((a, b) {
        final s = byStatus(a, b);
        if (s != 0) return s;
        return a.title.compareTo(b.title);
      });
  }
  return list;
}

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

  /// 子任务（递归嵌套，任意层级）。
  /// **数组顺序就是子任务的显示顺序**，因此子任务排序不需要额外字段。
  final List<TodoItem> children;

  /// 同级排序（**只有顶层条目需要**；子任务看 [children] 数组顺序）。
  /// 越小越靠前；结构调整后由仓库重排为 `0..n-1`。旧数据没有该字段，默认 0。
  final int order;

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
    this.order = 0,
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
    'order': order,
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
    order: (json['order'] as num?)?.toInt() ?? 0,
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
    int? order,
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
    order: order ?? this.order,
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
