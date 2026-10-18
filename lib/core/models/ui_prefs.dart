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

  /// 更新用的网络代理：空 = 自动读系统代理；`direct` = 强制直连；
  /// 其它 = 指定 `host:port`（如 127.0.0.1:7890）。
  /// 国内直连 GitHub 基本不通，所以这个开关很实用。
  static const String updateProxyKey = 'updateProxy';

  /// 任务父进度的加权系数（`{work, invest, milestone}`）。
  ///
  /// 放在通用偏好里而不是任务模型里：它是「用户口味」而非任务数据，
  /// 且 core 不依赖 feature —— 具体解析由任务模块自己做。
  static const String questWeightsKey = 'questWeights';

  /// 任务详情页是否隐藏「已了结」（已完成 / 已放弃）的子项目，默认隐藏。
  static const String hideResolvedSubtasksKey = 'hideResolvedSubtasks';

  /// 待办的排序方式（`manual` / `deadline` / `created` / `title`）。
  /// 默认 `deadline`：保持加这个功能之前的行为不变。
  static const String todoSortModeKey = 'todoSortMode';

  /// 笔记列表视图：`true` = 按分组折叠展示（默认），`false` = 平铺 + 分组筛选。
  static const String notesGroupedViewKey = 'notesGroupedView';

  /// 读取原始值（供各 feature 自己解析，core 不引入业务类型）
  Object? raw(String key) => values[key];

  /// 更新代理解析结果（供界面显示）
  String get updateProxy => str(updateProxyKey);

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
