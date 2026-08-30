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
    key: 'todo',
    label: '待办',
    icon: Icons.check_circle_outline,
    selectedIcon: Icons.check_circle,
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

/// 导航可见性配置：控制各功能是否显示在**底部导航栏**。
/// 未配置的项默认显示（`isBottomBarVisible` 返回 true）。
class NavSettings {
  /// 是否显示在底部导航栏（底边栏）
  final Map<String, bool> bottomBarVisible;

  const NavSettings({
    this.bottomBarVisible = const {},
  });

  /// 功能是否显示在底部导航栏
  bool isBottomBarVisible(String key) => bottomBarVisible[key] ?? true;

  factory NavSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const NavSettings();
    final bottom = <String, bool>{};
    (j['bottomBarVisible'] as Map?)?.forEach((k, v) {
      if (v is bool) bottom[k.toString()] = v;
    });
    return NavSettings(bottomBarVisible: bottom);
  }

  Map<String, dynamic> toJson() => {
        'bottomBarVisible': bottomBarVisible,
      };
}

/// 底部导航栏可见功能列表（按 [NavSettings] 过滤，顺序保持 [kAppFeatures]）。
/// 「工具」恒显示：它是备份 / 模板 / 设置等功能的唯一入口，防止误关后无法进入。
List<AppFeature> bottomBarFeatures(NavSettings nav) {
  final features =
      kAppFeatures.where((f) => nav.isBottomBarVisible(f.key)).toList();
  if (!features.any((f) => f.key == 'tools')) {
    features.add(kAppFeatures.firstWhere((f) => f.key == 'tools'));
  }
  return features;
}
