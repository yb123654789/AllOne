import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../storage/app_paths.dart';
import '../storage/nav_providers.dart';
import '../theme.dart';
import 'offline_tile_provider.dart';

/// 可复用的地图视图组件（离线优先）。
///
/// - `interactive = true`：点击地图即可选点，位置变化通过 [onChanged] 回调。
/// - `interactive = false`：只读展示，用于日记详情页可视化标记地址。
///
/// 底图来源见 [TileSources]：默认 Esri（OSM 官方瓦片在国内常连不上，
/// 会导致整块地图空白）。本地 `AllOneData/map_tiles/` 里有瓦片时优先用本地。
class LocationMapView extends ConsumerStatefulWidget {
  final LatLng center;
  final bool interactive;
  final ValueChanged<LatLng>? onChanged;
  final double height;

  /// 已知外部环境无网络时传 false，可跳过探测
  final bool showOfflineNotice;

  const LocationMapView({
    super.key,
    required this.center,
    this.interactive = false,
    this.onChanged,
    this.height = 220,
    this.showOfflineNotice = true,
  });

  @override
  ConsumerState<LocationMapView> createState() => _LocationMapViewState();
}

class _LocationMapViewState extends ConsumerState<LocationMapView> {
  String? _offlineRoot;
  bool _hasOfflineTiles = false;
  bool? _online; // null = 探测中

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final root = await AppPaths.dataRoot();
    final dir = Directory('${root.path}/map_tiles');
    final hasTiles = await _containsAnyTile(dir);
    var online = false;
    if (widget.showOfflineNotice) {
      final src = ref.read(tileSourceProvider);
      online = await canReachTileSource(src.urlTemplate);
    }
    if (!mounted) return;
    setState(() {
      _offlineRoot = dir.path;
      _hasOfflineTiles = hasTiles;
      _online = online;
    });
  }

  /// 离线瓦片目录里是否有可用的 `{z}/{x}/{y}.png`
  Future<bool> _containsAnyTile(Directory dir) async {
    try {
      if (!await dir.exists()) return false;
      await for (final z in dir.list()) {
        if (z is! Directory) continue;
        await for (final x in z.list()) {
          if (x is! Directory) continue;
          await for (final f in x.list()) {
            if (f is File && f.path.toLowerCase().endsWith('.png')) return true;
          }
        }
      }
    } catch (_) {
      // 读不了就当作没有
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(tileSourceProvider);
    final noNetwork = _online == false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: 13,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all & ~InteractiveFlag.rotate
                      : InteractiveFlag.none,
                ),
                onTap: widget.interactive
                    ? (tapPosition, point) => widget.onChanged?.call(point)
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: source.urlTemplate,
                  subdomains: source.subdomains,
                  userAgentPackageName: 'com.allone.app',
                  tileProvider: OfflineFirstTileProvider(
                    offlineRoot: _offlineRoot,
                    // 没网就别再发请求，否则每块瓦片都等一次超时
                    allowNetwork: !noNetwork,
                  ),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.center,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_pin,
                        size: 44,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
                // 版权标注（Esri / 高德等要求保留）
                if (source.attribution.isNotEmpty)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      color: Colors.white.withValues(alpha: 0.7),
                      child: Text(
                        source.attribution,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
            // 没网且没有离线瓦片 → 明确说明原因与解决办法
            if (noNetwork && !_hasOfflineTiles)
              const Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: _OfflineNotice(),
              ),
            // 没网但有离线瓦片 → 只提示一句（底图能正常显示）
            if (noNetwork && _hasOfflineTiles)
              const Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: _OfflineChip(),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「底图源连不上」提示：说明原因与两种解决办法。
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.textSecondary.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: AppTheme.danger),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '当前底图源连不上，底图无法加载。\n'
              '可在「设置 → 地图底图」换一个源；也可把标准 XYZ 瓦片放到 '
              'AllOneData/map_tiles/{z}/{x}/{y}.png 离线使用。',
              style: TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('当前使用本地离线瓦片', style: TextStyle(fontSize: 11)),
      ),
    );
  }
}
