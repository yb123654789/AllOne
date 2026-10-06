import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// 从瓦片 URL 模板里取出主机名（把 {s}/{z}/{x}/{y} 占位符替换掉）。
String hostOfTileTemplate(String template) {
  var s = template;
  // 子域占位符取一个具体值，避免解析失败
  s = s.replaceAll('{s}', 'a');
  s = s.replaceAll('{z}', '13');
  s = s.replaceAll('{x}', '6744');
  s = s.replaceAll('{y}', '3104');
  final uri = Uri.tryParse(s);
  return uri?.host ?? '';
}

/// 在线瓦片服务能否连通。
///
/// 用它来**区分「没网」和「程序坏了」**：连不上时地图会一直空白，
/// 用户会以为是 bug。实测本机 DNS 被污染（tile.openstreetmap.org 解析到
/// 一个不可达地址）且无可用代理，直连必然超时 —— 这种情况下必须明确告知。
///
/// 判定方式：DNS 解析 + 一次极短的 TCP 连接尝试（不下载瓦片，开销很小）。
Future<bool> canReachTileServer({
  String host = 'tile.openstreetmap.org',
  int port = 443,
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (host.isEmpty) return false;
  try {
    final addrs = await InternetAddress.lookup(host).timeout(timeout);
    if (addrs.isEmpty) return false;
    // DNS 能解析不代表能连上（污染会解析到不可达地址），再试一次 TCP
    final socket = await Socket.connect(
      addrs.first,
      port,
      timeout: timeout,
    ).timeout(timeout + const Duration(seconds: 1));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// 按瓦片源 URL 模板探测其主机是否可达
Future<bool> canReachTileSource(String urlTemplate, {int port = 443}) =>
    canReachTileServer(host: hostOfTileTemplate(urlTemplate), port: port);

/// 无网络时的瓦片占位：一张 1×1 的浅灰图，会被拉伸铺满整块瓦片。
///
/// 用它而不是纯白，是为了让「这里本该有地图」这件事看起来更明确。
/// 内嵌字节而不是放资源文件，省得为一张占位图增加 assets 配置。
final ImageProvider offlineTilePlaceholder = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

/// 离线优先瓦片源。
///
/// 优先从本地目录加载瓦片（离线地图），缺失时回退到在线瓦片。
/// 离线瓦片约定目录结构：`{offlineRoot}/{z}/{x}/{y}.png`
/// （标准 XYZ 瓦片，可用 Mobile Atlas Creator / OSMAnd 等工具导出后复制进数据目录）。
///
/// **继承 TileProvider 而不是自己起一个类**，因为 [TileLayer] 会在初始化时
/// 往 `tileProvider.headers` 里塞 `User-Agent`
/// （见 flutter_map 的 `TileLayer`：`headers.putIfAbsent('User-Agent', ...)`）。
/// 只有用 `super(headers: ...)` 接住这个 Map 并在发起网络请求时带上，
/// 在线瓦片才能通过服务端校验。
///
/// 早期实现是 `return NetworkImage(url)` —— 一个**不带任何 header** 的裸请求，
/// OSM 会拒绝；已修正。但必须强调：**没网时任何 header 都救不了**，
/// 那种情况下应由调用方传 `allowNetwork: false` 并给出提示，见 [canReachTileServer]。
class OfflineFirstTileProvider extends TileProvider {
  final String? offlineRoot;

  /// 是否允许回退到在线瓦片。
  ///
  /// 已知没网时设 false：否则每个瓦片都要等一次连接超时，界面会长时间卡顿。
  final bool allowNetwork;

  OfflineFirstTileProvider({
    this.offlineRoot,
    this.allowNetwork = true,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final root = offlineRoot;
    if (root != null && root.isNotEmpty) {
      final file = File(
        '$root/${coordinates.z}/${coordinates.x}/${coordinates.y}.png',
      );
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    if (!allowNetwork) {
      // 明确没网：不再发请求，直接给占位图
      return offlineTilePlaceholder;
    }
    // 回退在线瓦片：必须带上 headers（含 User-Agent），否则会被瓦片服务拒绝
    return NetworkImage(getTileUrl(coordinates, options), headers: headers);
  }
}
