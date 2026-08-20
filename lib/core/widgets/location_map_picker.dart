import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../storage/app_paths.dart';
import '../theme.dart';
import 'offline_tile_provider.dart';

/// 地图选点工具：弹出地图让用户点选位置（离线优先）。
///
/// 返回选中的 [LatLng]；取消返回 null。
class LocationMapPicker {
  LocationMapPicker._();

  static Future<LatLng?> show(
    BuildContext context, {
    double? lat,
    double? lng,
    String? name,
  }) {
    return showDialog<LatLng>(
      context: context,
      builder: (_) => _PickerDialog(initialLat: lat, initialLng: lng, name: name),
    );
  }
}

class _PickerDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? name;

  const _PickerDialog({this.initialLat, this.initialLng, this.name});

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  /// 默认中心（北京）
  static const _defaultLat = 39.9042;
  static const _defaultLng = 116.4074;

  late LatLng _selected;
  String? _offlineRoot;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLat ?? _defaultLat,
      widget.initialLng ?? _defaultLng,
    );
    _loadOfflineRoot();
  }

  Future<void> _loadOfflineRoot() async {
    final root = await AppPaths.dataRoot();
    final dir = '${root.path}/map_tiles';
    if (mounted) {
      setState(() => _offlineRoot = dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.name == null ? '地图选点' : '地图选点 · ${widget.name}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: '回到默认位置',
                    onPressed: () => setState(() {
                      _selected = const LatLng(_defaultLat, _defaultLng);
                    }),
                  ),
                ],
              ),
            ),
            // 地图
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _selected,
                  initialZoom: 13,
                  onTap: (tapPosition, point) => setState(() => _selected = point),
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
                        point: _selected,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.location_pin,
                            size: 44, color: AppTheme.danger),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 底部：坐标显示 + 操作
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '经度 ${_selected.longitude.toStringAsFixed(6)}　'
                    '纬度 ${_selected.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '点击地图标记位置 · 离线瓦片存放于 AllOneData/map_tiles 时可离线使用',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, _selected),
                        child: const Text('确定选点'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
