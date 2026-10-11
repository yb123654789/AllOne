import 'dart:io';

import 'package:allone/core/storage/json_store.dart';

/// 内存版 JsonStore（测试专用）。
///
/// **为什么需要它**：`testWidgets` 用的是假时钟，dart:io 的完成回调
/// 不会被推进 —— 页面会永远停在 loading 指示器上，`pumpAndSettle` 空等。
/// 所以 widget 测试一律用内存存储，不要碰 `Directory.systemTemp`。
class MemStore extends JsonStore {
  MemStore() : super(Directory.systemTemp);

  /// 普通对象文件：路径 -> JSON
  final Map<String, Map<String, dynamic>> objects = {};

  /// 数组文件：路径 -> JSON 数组
  final Map<String, List<Map<String, dynamic>>> lists = {};

  @override
  Future<Map<String, dynamic>?> read(String relativePath) async {
    final v = objects[relativePath];
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  @override
  Future<void> write(String relativePath, Map<String, dynamic> json) async {
    objects[relativePath] = Map<String, dynamic>.from(json);
  }

  @override
  Future<List<Map<String, dynamic>>> readList(String relativePath) async {
    return (lists[relativePath] ?? const <Map<String, dynamic>>[])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> writeList(
    String relativePath,
    List<Map<String, dynamic>> json,
  ) async {
    lists[relativePath] = json
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> delete(String relativePath) async {
    objects.remove(relativePath);
    lists.remove(relativePath);
  }

  @override
  Future<List<String>> listFiles(
    String relativeDir, {
    String extension = '.json',
  }) async {
    final prefix = '$relativeDir/';
    final out = <String>{};
    for (final k in [...objects.keys, ...lists.keys]) {
      if (!k.startsWith(prefix)) continue;
      final rest = k.substring(prefix.length);
      if (rest.contains('/')) continue; // 只列直接子文件
      if (!rest.endsWith(extension)) continue;
      out.add(rest);
    }
    return out.toList();
  }

  @override
  Future<void> deleteDirectory(String relativeDir) async {
    objects.removeWhere((k, _) => k.startsWith('$relativeDir/'));
    lists.removeWhere((k, _) => k.startsWith('$relativeDir/'));
  }
}
