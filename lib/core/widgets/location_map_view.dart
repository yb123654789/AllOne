import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../storage/app_paths.dart';
import '../theme.dart';
import 'offline_tile_provider.dart';

/// 可复用的地图视图组件（离线优先）。
///
/// - `interactive = true`：点击地图即可选点，位置变化通过 [onChanged] 回调。
/// - `interactive = false`：只读展示，用于日记详情页可视化标记地址。
class LocationMapView extends StatefulWidget {
  final LatLng center;
  final bool interactive;
  final ValueChanged<LatLng>? onChanged;
  final double height;

  const LocationMapView({
    super.key,
    required this.center,
    this.interactive = false,
    this.onChanged,
    this.height = 220,
  });

  @override
  State<LocationMapView> createState() => _LocationMapViewState();
}

class _LocationMapViewState extends State<LocationMapView> {
  String? _offlineRoot;

  @override
  void initState() {
    super.initState();
    _loadOfflineRoot();
  }

  Future<void> _loadOfflineRoot() async {
    final root = await AppPaths.dataRoot();
    final dir = '${root.path}/map_tiles';
    if (mounted) setState(() => _offlineRoot = dir);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: FlutterMap(
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.allone.app',
              tileProvider: OfflineFirstTileProvider(offlineRoot: _offlineRoot),
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
          ],
        ),
      ),
    );
  }
}
