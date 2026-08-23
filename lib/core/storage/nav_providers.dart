import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nav_settings.dart';
import 'storage_providers.dart';

/// 当前底部导航选中的 tab 索引（全局，供工具页 / 侧边栏跳转使用）。
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// 导航可见性配置 Notifier：持久化到 `settings/nav.json`。
class NavSettingsNotifier extends AsyncNotifier<NavSettings> {
  static const _path = 'settings/nav.json';

  @override
  Future<NavSettings> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    return NavSettings.fromJson(json);
  }

  /// 设置某个功能是否显示在侧边栏
  Future<void> setSidebarVisible(String key, bool visible) async {
    final store = await ref.read(jsonStoreProvider.future);
    // 直接从磁盘读取当前配置作为基线（避免 AsyncLoading 时丢失其他项）
    final json = await store.read(_path);
    final map = <String, bool>{};
    (json?['sidebarVisible'] as Map?)?.forEach((k, v) {
      if (v is bool) map[k.toString()] = v;
    });
    map[key] = visible;
    final nav = NavSettings(sidebarVisible: map);
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
