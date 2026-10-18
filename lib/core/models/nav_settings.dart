import 'package:flutter/material.dart';

/// 主要功能条目元数据（key / 名称 / 图标）。
/// 供底部导航、工具页「功能入口」共用。
/// 页面实例由 app.dart 按 key 组装（core 不依赖 feature）。
class AppFeature {
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const AppFeature({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// 全部主要功能（顺序即底部导航顺序）
const List<AppFeature> kAppFeatures = [
  AppFeature(
    key: 'diary',
    label: '日记',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
  ),
  AppFeature(
    key: 'notes',
    label: '笔记',
    icon: Icons.note_alt_outlined,
    selectedIcon: Icons.note_alt,
  ),
  AppFeature(
    key: 'todo',
    label: '待办',
    icon: Icons.check_circle_outline,
    selectedIcon: Icons.check_circle,
  ),
  AppFeature(
    key: 'quest',
    label: '任务',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag,
  ),
  AppFeature(
    key: 'habit',
    label: '习惯',
    icon: Icons.repeat_outlined,
    selectedIcon: Icons.repeat,
  ),
  AppFeature(
    key: 'schedule',
    label: '课程',
    icon: Icons.calendar_view_week_outlined,
    selectedIcon: Icons.calendar_view_week,
  ),
  AppFeature(
    key: 'ledger',
    label: '记账',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  AppFeature(
    key: 'calendar',
    label: '日历',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
  ),
  AppFeature(
    key: 'tools',
    label: '工具',
    icon: Icons.handyman_outlined,
    selectedIcon: Icons.handyman,
  ),
];

/// 导航与地图等通用设置。
class NavSettings {
  /// 是否显示在底部导航栏（底边栏）
  final Map<String, bool> bottomBarVisible;

  /// 地图底图瓦片源 id（见 core/widgets/tile_sources.dart）。
  /// 空 = 用默认源（Esri）。之所以可配置：OSM 官方瓦片在国内常连不上，
  /// 不同网络环境下可用的源不同。
  final String mapSource;

  const NavSettings({this.bottomBarVisible = const {}, this.mapSource = ''});

  /// 功能是否显示在底部导航栏
  bool isBottomBarVisible(String key) => bottomBarVisible[key] ?? true;

  NavSettings copyWith({
    Map<String, bool>? bottomBarVisible,
    String? mapSource,
  }) => NavSettings(
    bottomBarVisible: bottomBarVisible ?? this.bottomBarVisible,
    mapSource: mapSource ?? this.mapSource,
  );

  factory NavSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const NavSettings();
    final bottom = <String, bool>{};
    (j['bottomBarVisible'] as Map?)?.forEach((k, v) {
      if (v is bool) bottom[k.toString()] = v;
    });
    return NavSettings(
      bottomBarVisible: bottom,
      mapSource: j['mapSource'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'bottomBarVisible': bottomBarVisible,
    'mapSource': mapSource,
  };
}

/// 底部导航栏可见功能列表（按 [NavSettings] 过滤，顺序保持 [kAppFeatures]）。
/// 「工具」恒显示：它是备份 / 模板 / 设置等功能的唯一入口，防止误关后无法进入。
List<AppFeature> bottomBarFeatures(NavSettings nav) {
  final features = kAppFeatures
      .where((f) => nav.isBottomBarVisible(f.key))
      .toList();
  if (!features.any((f) => f.key == 'tools')) {
    features.add(kAppFeatures.firstWhere((f) => f.key == 'tools'));
  }
  return features;
}
