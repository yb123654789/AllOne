import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// 离线优先瓦片源。
///
/// 优先从本地目录加载瓦片（离线地图），缺失时回退到在线瓦片。
/// 离线瓦片约定目录结构：`{offlineRoot}/{z}/{x}/{y}.png`
/// （标准 XYZ 瓦片，可用 Mobile Atlas Creator / OSMAnd 等工具导出后复制进数据目录）。
class OfflineFirstTileProvider extends TileProvider {
  final String? offlineRoot;

  OfflineFirstTileProvider({this.offlineRoot});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    if (offlineRoot != null && offlineRoot!.isNotEmpty) {
      final file = File(
        '$offlineRoot/${coordinates.z}/${coordinates.x}/${coordinates.y}.png',
      );
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    // 回退在线瓦片
    return NetworkImage(getTileUrl(coordinates, options));
  }
}
