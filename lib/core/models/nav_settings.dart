import 'package:flutter/material.dart';

/// 主要功能条目元数据（key / 名称 / 图标）。
/// 供底部导航、侧边栏、工具页「功能入口」共用。
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

/// 导航可见性配置：控制各功能是否显示在**侧边栏**。
/// 未配置的项默认显示（`isSidebarVisible` 返回 true）。
class NavSettings {
  final Map<String, bool> sidebarVisible;

  const NavSettings({this.sidebarVisible = const {}});

  bool isSidebarVisible(String key) => sidebarVisible[key] ?? true;

  factory NavSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const NavSettings();
    final map = <String, bool>{};
    (j['sidebarVisible'] as Map?)?.forEach((k, v) {
      if (v is bool) map[k.toString()] = v;
    });
    return NavSettings(sidebarVisible: map);
  }

  Map<String, dynamic> toJson() => {'sidebarVisible': sidebarVisible};
}
