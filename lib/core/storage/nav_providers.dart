import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nav_settings.dart';
import 'storage_providers.dart';

/// 当前底部导航选中的**功能 key**（全局，供工具页 / 侧边栏跳转使用）。
/// 用 key 而非索引，避免隐藏部分功能后索引错乱。
final homeTabProvider = StateProvider<String>((ref) => 'diary');

/// 导航可见性配置 Notifier：持久化到 `settings/nav.json`。
class NavSettingsNotifier extends AsyncNotifier<NavSettings> {
  static const _path = 'settings/nav.json';

  @override
  Future<NavSettings> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    return NavSettings.fromJson(json);
  }

  /// 从磁盘 JSON 中读取某个可见性 Map（避免 AsyncLoading 时丢失其他项）
  Map<String, bool> _readVisible(Map<String, dynamic>? json, String field) {
    final map = <String, bool>{};
    (json?[field] as Map?)?.forEach((k, v) {
      if (v is bool) map[k.toString()] = v;
    });
    return map;
  }

  /// 设置某个功能是否显示在底部导航栏
  Future<void> setBottomBarVisible(String key, bool visible) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read(_path);
    final map = _readVisible(json, 'bottomBarVisible');
    map[key] = visible;
    final current = state.valueOrNull ?? const NavSettings();
    final nav = NavSettings(
      bottomBarVisible: map,
      sidebarVisible: current.sidebarVisible,
    );
    await store.write(_path, nav.toJson());
    // 立即更新内存 state（而非仅 invalidateSelf），
    // 避免 AsyncLoading 阶段 valueOrNull 为 null 导致导航回退显示全部。
    state = AsyncData(nav);
  }

  /// 设置某个功能是否显示在侧边栏
  Future<void> setSidebarVisible(String key, bool visible) async {
    final store = await ref.read(jsonStoreProvider.future);
    // 直接从磁盘读取当前配置作为基线（避免 AsyncLoading 时丢失其他项）
    final json = await store.read(_path);
    final map = _readVisible(json, 'sidebarVisible');
    map[key] = visible;
    final current = state.valueOrNull ?? const NavSettings();
    final nav = NavSettings(
      bottomBarVisible: current.bottomBarVisible,
      sidebarVisible: map,
    );
    await store.write(_path, nav.toJson());
    // 立即更新内存 state（而非仅 invalidateSelf），
    // 避免 AsyncLoading 阶段 valueOrNull 为 null 导致侧边栏回退显示全部。
    state = AsyncData(nav);
  }
}

final navSettingsProvider =
    AsyncNotifierProvider<NavSettingsNotifier, NavSettings>(
      NavSettingsNotifier.new,
    );
