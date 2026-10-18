import '../../core/models/common.dart';

/// 笔记颜色默认值（与日记标签、记账账户等保持一致的主色）
const String kDefaultNoteColor = '#1E88E5';

/// 笔记分组：主题的二级收纳。
///
/// 「学习」「读书」「工作」这类大类别用分组，具体对象（一本书 / 一个技能 /
/// 一个项目）建主题。分组只负责收纳，不参与记录本身。
class NoteGroup {
  final String id;
  final String name;

  /// 颜色 #RRGGBB（列表左侧色条 / 分组标签）
  final String color;

  /// 排序序号（小的在前；相同则按名称）
  final int order;

  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteGroup({
    required this.id,
    this.name = '',
    this.color = kDefaultNoteColor,
    this.order = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'order': order,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteGroup.fromJson(Map<String, dynamic> json) => NoteGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? kDefaultNoteColor,
    order: (json['order'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  NoteGroup copyWith({
    String? name,
    String? color,
    int? order,
    DateTime? updatedAt,
  }) => NoteGroup(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    order: order ?? this.order,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 笔记主题：一个长期记录的对象（一本书 / 一个技能 / 一个项目 / 一件长期的事）。
///
/// 主题本身只有名称、简介、颜色与收纳属性；真正的内容是挂在它下面的
/// 一条条 [NoteEntry]，可以横跨数月甚至数年累积。
class NoteTopic {
  final String id;

  /// 所属分组（可以同时属于多个：一本书既能归到「大航海时代」，
  /// 也能归到「2026 读完的书」；空列表 = 未分组）
  final List<String> groupIds;

  final String title;

  /// 简介 / 当前结论（列表里一行摘要，也可写「为什么记这个」）
  final String intro;

  final String color;

  /// 置顶（列表里优先显示）
  final bool pinned;

  /// 归档（不再活跃，列表里默认收起）
  final bool archived;

  /// 删除时间（非空 = 在回收站）。用软删除而不是直接删文件，
  /// 误删主题时连同一堆记录都能整体恢复。
  final DateTime? deletedAt;

  final DateTime createdAt;

  /// 最近一次「有记录写入」的时间（列表按它排序）
  final DateTime updatedAt;

  const NoteTopic({
    required this.id,
    this.groupIds = const [],
    this.title = '',
    this.intro = '',
    this.color = kDefaultNoteColor,
    this.pinned = false,
    this.archived = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 是否在回收站
  bool get inTrash => deletedAt != null;

  /// 未归入任何分组
  bool get ungrouped => groupIds.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (groupIds.isNotEmpty) 'groupIds': groupIds,
    'title': title,
    'intro': intro,
    'color': color,
    'pinned': pinned,
    'archived': archived,
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteTopic.fromJson(Map<String, dynamic> json) => NoteTopic(
    id: json['id'] as String? ?? '',
    groupIds: _readGroupIds(json),
    title: json['title'] as String? ?? '',
    intro: json['intro'] as String? ?? '',
    color: json['color'] as String? ?? kDefaultNoteColor,
    pinned: json['pinned'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// 注意：[groupIds] 传 null 表示「不改」，要清空分组请传空列表。
  NoteTopic copyWith({
    List<String>? groupIds,
    String? title,
    String? intro,
    String? color,
    bool? pinned,
    bool? archived,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? updatedAt,
  }) => NoteTopic(
    id: id,
    groupIds: groupIds ?? this.groupIds,
    title: title ?? this.title,
    intro: intro ?? this.intro,
    color: color ?? this.color,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// 加入一个分组（已在其中则原样返回）
  NoteTopic withGroup(String gid) =>
      groupIds.contains(gid) ? this : copyWith(groupIds: [...groupIds, gid]);

  /// 移出一个分组
  NoteTopic withoutGroup(String gid) => groupIds.contains(gid)
      ? copyWith(groupIds: groupIds.where((g) => g != gid).toList())
      : this;
}

/// 读分组归属：新格式 `groupIds` 数组；兼容早期的单个 `groupId`。
List<String> _readGroupIds(Map<String, dynamic> json) {
  final list = (json['groupIds'] as List?)?.whereType<String>().toList();
  if (list != null) return list;
  final legacy = json['groupId'] as String?;
  return (legacy == null || legacy.isEmpty) ? const [] : [legacy];
}

/// 主题下的一条记录。
///
/// [occurredAt] 是「这件事发生的时间」，可补记（例如读了 30 页后
/// 补写昨天的想法）；[createdAt] 是落盘时间，仅用于回溯。
class NoteEntry {
  final String id;
  final String topicId;
  final String title;
  final String plainText;

  /// 事情发生的时间（时间线按它排序与分月）
  final DateTime occurredAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  final List<String> tags;
  final List<MediaAttachment> media;
  final LocationStamp locationStamp;

  const NoteEntry({
    required this.id,
    required this.topicId,
    this.title = '',
    this.plainText = '',
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.media = const [],
    this.locationStamp = const LocationStamp(),
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'topicId': topicId,
    'title': title,
    'plainText': plainText,
    'occurredAt': occurredAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tags': tags,
    'media': media.map((m) => m.toJson()).toList(),
    'locationStamp': locationStamp.toJson(),
  };

  factory NoteEntry.fromJson(Map<String, dynamic> json) {
    // 时间容错：老数据 / 手改数据可能缺 occurredAt，退回创建时间而不是报错
    final occurred =
        DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now();
    return NoteEntry(
      id: json['id'] as String? ?? '',
      topicId: json['topicId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      plainText: json['plainText'] as String? ?? '',
      occurredAt: occurred,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      media:
          (json['media'] as List?)
              ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      locationStamp: LocationStamp.fromJson(
        json['locationStamp'] as Map<String, dynamic>?,
      ),
    );
  }

  NoteEntry copyWith({
    String? title,
    String? plainText,
    DateTime? occurredAt,
    DateTime? updatedAt,
    List<String>? tags,
    List<MediaAttachment>? media,
    LocationStamp? locationStamp,
  }) => NoteEntry(
    id: id,
    topicId: topicId,
    title: title ?? this.title,
    plainText: plainText ?? this.plainText,
    occurredAt: occurredAt ?? this.occurredAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tags: tags ?? this.tags,
    media: media ?? this.media,
    locationStamp: locationStamp ?? this.locationStamp,
  );

  /// 修正归属主题（仅在「目录归属与文件内 topicId 不一致」时用于容错迁移）
  NoteEntry copyWithTopic(String topicId) => NoteEntry(
    id: id,
    topicId: topicId,
    title: title,
    plainText: plainText,
    occurredAt: occurredAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    tags: tags,
    media: media,
    locationStamp: locationStamp,
  );

  /// 标题为空时取正文首行，再空则「无标题」，列表与导出统一口径
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final firstLine = plainText
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return firstLine.isEmpty ? '无标题' : firstLine;
  }
}
