/// 通用数据模型：附件、时间戳、地址戳、标签。
library;

/// 附件类型
enum MediaType { photo, audio, video, file, videoLink }

/// 附件（多媒体）—— 支持内嵌或外链（大视频）
class MediaAttachment {
  final MediaType type;
  final String? file; // 相对 media/ 目录的文件名（内嵌）
  final String? external; // 外部路径（大视频外链）
  final int size;
  final String? note;

  const MediaAttachment({
    required this.type,
    this.file,
    this.external,
    this.size = 0,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (file != null) 'file': file,
    if (external != null) 'external': external,
    'size': size,
    if (note != null) 'note': note,
  };

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      MediaAttachment(
        type: MediaType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MediaType.file,
        ),
        file: json['file'] as String?,
        external: json['external'] as String?,
        size: (json['size'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
      );
}

/// 时间戳（历史纪念）
class TimeStamp {
  final bool enabled;
  final String? nodeDate; // 纪念节点日期，如 2027-02-20（半年/一年）
  final bool pinTop; // 到达节点后置顶

  const TimeStamp({this.enabled = false, this.nodeDate, this.pinTop = false});

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (nodeDate != null) 'nodeDate': nodeDate,
    'pinTop': pinTop,
  };

  factory TimeStamp.fromJson(Map<String, dynamic>? json) => json == null
      ? const TimeStamp()
      : TimeStamp(
          enabled: json['enabled'] as bool? ?? false,
          nodeDate: json['nodeDate'] as String?,
          pinTop: json['pinTop'] as bool? ?? false,
        );
}

/// 地址戳（离线地图标记）
class LocationStamp {
  final bool enabled;
  final double lat;
  final double lng;
  final String name;

  const LocationStamp({
    this.enabled = false,
    this.lat = 0,
    this.lng = 0,
    this.name = '',
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'lat': lat,
    'lng': lng,
    'name': name,
  };

  factory LocationStamp.fromJson(Map<String, dynamic>? json) => json == null
      ? const LocationStamp()
      : LocationStamp(
          enabled: json['enabled'] as bool? ?? false,
          lat: (json['lat'] as num?)?.toDouble() ?? 0,
          lng: (json['lng'] as num?)?.toDouble() ?? 0,
          name: json['name'] as String? ?? '',
        );
}

/// 时间工具
class AppTime {
  AppTime._();

  /// 格式化日期为 yyyy-MM-dd
  static String dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 解析 yyyy-MM-dd
  static DateTime? parseDate(String s) {
    final parts = s.split('-');
    if (parts.length != 3) return null;
    return DateTime.tryParse(s);
  }
}
