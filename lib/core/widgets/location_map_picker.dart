import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../storage/app_paths.dart';
import '../storage/nav_providers.dart';
import '../theme.dart';
import '../utils/location_service.dart';
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
      builder: (_) =>
          _PickerDialog(initialLat: lat, initialLng: lng, name: name),
    );
  }
}

class _PickerDialog extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? name;

  const _PickerDialog({this.initialLat, this.initialLng, this.name});

  @override
  ConsumerState<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends ConsumerState<_PickerDialog> {
  /// 默认中心（北京）
  static const _defaultLat = 39.9042;
  static const _defaultLng = 116.4074;

  late LatLng _selected;
  String? _offlineRoot;
  bool _online = true;
  bool _locating = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLat ?? _defaultLat,
      widget.initialLng ?? _defaultLng,
    );
    _loadOfflineRoot();
  }

  /// 获取当前位置并把地图移过去。
  ///
  /// 定位靠 GPS，**不需要网络**；取不到时给出明确原因。
  Future<void> _locateMe() async {
    setState(() => _locating = true);
    final pos = await LocationService.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取定位：请在系统设置里允许定位、并确认已开启定位服务')),
      );
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    setState(() => _selected = p);
    _mapController.move(p, 16);
  }

  Future<void> _loadOfflineRoot() async {
    final root = await AppPaths.dataRoot();
    final dir = '${root.path}/map_tiles';
    // 探测当前底图源是否可达：不可达时底图必然空白，需要明确告知用户
    final src = ref.read(tileSourceProvider);
    final online = await canReachTileSource(src.urlTemplate);
    if (mounted) {
      setState(() {
        _offlineRoot = dir;
        _online = online;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(tileSourceProvider);
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _locating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    tooltip: '获取当前位置',
                    onPressed: _locating ? null : _locateMe,
                  ),
                ],
              ),
            ),
            // 地图
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selected,
                      initialZoom: 13,
                      onTap: (tapPosition, point) =>
                          setState(() => _selected = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: source.urlTemplate,
                        subdomains: source.subdomains,
                        userAgentPackageName: 'com.allone.app',
                        tileProvider: OfflineFirstTileProvider(
                          offlineRoot: _offlineRoot,
                          // 没网就别再发请求，否则每块瓦片都要等一次超时
                          allowNetwork: _online,
                        ),
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selected,
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
                  if (!_online)
                    const Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: _NoNetworkBanner(),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '点击地图标记位置 · 离线瓦片存放于 AllOneData/map_tiles 时可离线使用',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
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

/// 「无网络」提示横幅：说明底图空白的原因与离线瓦片用法。
class _NoNetworkBanner extends StatelessWidget {
  const _NoNetworkBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.textSecondary.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: AppTheme.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前无网络，底图无法加载（不是程序故障）。\n'
              '仍可在此点击地图选点；如需看到地图，'
              '请把标准 XYZ 瓦片放到 AllOneData/map_tiles/{z}/{x}/{y}.png。',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
