/// 通用 UI 偏好（键值对），持久化到 `AllOneData/settings/ui.json`。
///
/// 做成 Map 而不是一个字段一个字段的模型：以后「记住某页的显示方式」
/// 这类小偏好直接加一个 key 即可，不必再改模型、改备份逻辑。
/// 读取一律容错：文件损坏 / 字段缺失都回退到默认值，不影响启动。
class UiPrefs {
  final Map<String, dynamic> values;

  const UiPrefs({this.values = const {}});

  /// 课程表周视图排布：auto（按窗口宽度自动）/ grid（7 列网格）/ list（按天列表）
  static const String scheduleLayoutKey = 'scheduleLayout';
  static const String scheduleLayoutAuto = 'auto';
  static const String scheduleLayoutGrid = 'grid';
  static const String scheduleLayoutList = 'list';

  /// 上次检查更新的时间（ISO 8601；用于「一天最多查一次」）
  static const String lastUpdateCheckKey = 'lastUpdateCheck';

  /// 用户选择「跳过此版本」的版本号（不再提示该版本）
  static const String skippedUpdateKey = 'skippedUpdateVersion';

  String str(String key, {String fallback = ''}) {
    final v = values[key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  bool flag(String key, {bool fallback = false}) {
    final v = values[key];
    return v is bool ? v : fallback;
  }

  /// 课程表排布偏好（默认 auto）
  String get scheduleLayout =>
      str(scheduleLayoutKey, fallback: scheduleLayoutAuto);

  UiPrefs withValue(String key, Object? value) =>
      UiPrefs(values: {...values, key: value});

  factory UiPrefs.fromJson(Map<String, dynamic>? j) =>
      UiPrefs(values: {...?j});

  Map<String, dynamic> toJson() => values;
}
