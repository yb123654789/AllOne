import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// 定位（手机 GPS / 电脑可用的定位源）。
///
/// 说明：
/// - 定位**不需要网络**（GPS 是卫星定位），因此离线时也能取到坐标；
/// - 但「把坐标翻译成地名」需要联网（走 OSM Nominatim），失败不影响坐标本身；
/// - 权限被拒或设备不支持时返回 null，由调用方给出提示。
class LocationService {
  LocationService._();

  /// 取当前位置；失败返回 null（权限被拒、服务未开、设备不支持等）。
  ///
  /// [timeout] 给 GPS 一个合理的等待上限，避免界面长时间无响应。
  static Future<Position?> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } catch (_) {
      // 不抛给 UI：定位失败是常见情况（权限/服务/设备不支持）
      return null;
    }
  }

  /// 由坐标反查地名（需要联网）。
  ///
  /// 走 OSM 的 Nominatim 服务；网络不可用时返回 null，
  /// 调用方应保留「只有坐标」的可用状态。
  static Future<String?> placeName(
    double lat,
    double lng, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&zoom=16&accept-language=zh-CN'
        '&lat=$lat&lon=$lng',
      );
      final req = await client.getUrl(uri).timeout(timeout);
      // Nominatim 要求带可识别的 User-Agent
      req.headers.set('User-Agent', 'AllOne/1.1 (personal diary app)');
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final map = jsonDecode(body);
      if (map is! Map) return null;
      final name = map['display_name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
