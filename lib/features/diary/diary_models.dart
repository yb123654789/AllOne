import '../../core/models/common.dart';

/// 日记正文编辑模式（手机 / 电脑双键盘习惯）。
enum DiaryMode { plain, rich }

/// 日记条目
class DiaryEntry {
  final String id;
  final String? templateId;
  final String title;

  /// 编辑模式：纯文本（类似 txt）或富文本
  final DiaryMode mode;

  /// 富文本正文（Delta JSON 字符串），用于无损还原编辑内容
  final String contentDelta;

  /// 纯文本正文（与富文本同步生成），保证 txt 可读、格式通用
  final String plainText;

  final DateTime createdAt;
  final DateTime updatedAt;
  final TimeStamp timeStamp;
  final LocationStamp locationStamp;
  final List<String> tags;
  final List<MediaAttachment> media;
  final bool pinned; // 时间戳节点置顶

  const DiaryEntry({
    required this.id,
    this.templateId,
    this.title = '',
    this.mode = DiaryMode.rich,
    this.contentDelta = '',
    this.plainText = '',
    required this.createdAt,
    required this.updatedAt,
    this.timeStamp = const TimeStamp(),
    this.locationStamp = const LocationStamp(),
    this.tags = const [],
    this.media = const [],
    this.pinned = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    if (templateId != null) 'templateId': templateId,
    'title': title,
    'mode': mode.name,
    'contentDelta': contentDelta,
    'plainText': plainText,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'timeStamp': timeStamp.toJson(),
    'locationStamp': locationStamp.toJson(),
    'tags': tags,
    'media': media.map((m) => m.toJson()).toList(),
    'pinned': pinned,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as String? ?? '',
    templateId: json['templateId'] as String?,
    title: json['title'] as String? ?? '',
    mode: DiaryMode.values.firstWhere(
      (e) => e.name == json['mode'],
      orElse: () => DiaryMode.rich,
    ),
    contentDelta: json['contentDelta'] as String? ?? '',
    plainText: json['plainText'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    timeStamp: TimeStamp.fromJson(json['timeStamp'] as Map<String, dynamic>?),
    locationStamp: LocationStamp.fromJson(
      json['locationStamp'] as Map<String, dynamic>?,
    ),
    tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    media:
        (json['media'] as List?)
            ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    pinned: json['pinned'] as bool? ?? false,
  );

  DiaryEntry copyWith({
    String? templateId,
    String? title,
    DiaryMode? mode,
    String? contentDelta,
    String? plainText,
    DateTime? updatedAt,
    TimeStamp? timeStamp,
    LocationStamp? locationStamp,
    List<String>? tags,
    List<MediaAttachment>? media,
    bool? pinned,
  }) => DiaryEntry(
    id: id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    contentDelta: contentDelta ?? this.contentDelta,
    plainText: plainText ?? this.plainText,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    timeStamp: timeStamp ?? this.timeStamp,
    locationStamp: locationStamp ?? this.locationStamp,
    tags: tags ?? this.tags,
    media: media ?? this.media,
    pinned: pinned ?? this.pinned,
  );
}

/// 日记模板
class DiaryTemplate {
  final String id;
  final String name;

  /// 模板正文（Delta JSON 或 Markdown 文本）
  final String contentDelta;
  final String plainText;
  final DateTime createdAt;

  const DiaryTemplate({
    required this.id,
    this.name = '',
    this.contentDelta = '',
    this.plainText = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contentDelta': contentDelta,
    'plainText': plainText,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DiaryTemplate.fromJson(Map<String, dynamic> json) => DiaryTemplate(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    contentDelta: json['contentDelta'] as String? ?? '',
    plainText: json['plainText'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
