import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nav_settings.dart';
import '../widgets/tile_sources.dart';
import 'storage_providers.dart';

/// 当前底部导航选中的**功能 key**（全局，供工具页跳转使用）。
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
    final nav = NavSettings(
      bottomBarVisible: map,
      mapSource: json?['mapSource'] as String? ?? '',
    );
    await store.write(_path, nav.toJson());
    // 立即更新内存 state（而非仅 invalidateSelf），
    // 避免 AsyncLoading 阶段 valueOrNull 为 null 导致导航回退显示全部。
    state = AsyncData(nav);
  }

  /// 设置地图底图瓦片源 id
  Future<void> setMapSource(String sourceId) async {
    final store = await ref.read(jsonStoreProvider.future);
    final json = await store.read(_path);
    final nav = NavSettings(
      bottomBarVisible: _readVisible(json, 'bottomBarVisible'),
      mapSource: sourceId,
    );
    await store.write(_path, nav.toJson());
    state = AsyncData(nav);
  }
}

final navSettingsProvider =
    AsyncNotifierProvider<NavSettingsNotifier, NavSettings>(
      NavSettingsNotifier.new,
    );

/// 当前使用的地图底图源（供地图组件 watch）。
/// 默认 Esri —— OSM 官方瓦片在国内常连不上。
final tileSourceProvider = Provider<TileSource>((ref) {
  final nav = ref.watch(navSettingsProvider).valueOrNull;
  return TileSources.byId(nav?.mapSource);
});
