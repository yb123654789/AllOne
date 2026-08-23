import 'dart:convert';
import 'dart:io';

/// 通用 JSON 文件存储引擎。
///
/// 设计要点：
/// - 原子写入：先写临时文件再替换，避免写一半损坏导致数据丢失。
/// - 每个条目独立文件，单文件损坏不影响其他条目。
/// - 纯文本 UTF-8，格式通用，可直接用 U 盘复制备份。
class JsonStore {
  final Directory root;

  JsonStore(this.root);

  /// 读取 JSON 文件；不存在或损坏时返回 null。
  Future<Map<String, dynamic>?> read(String relativePath) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      // 单文件损坏不影响整体：返回 null 由调用方处理
      return null;
    }
  }

  /// 读取 JSON 数组文件；不存在或损坏时返回空列表。
  Future<List<Map<String, dynamic>>> readList(String relativePath) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    try {
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 原子写入 JSON 文件（自动创建父目录）。
  Future<void> write(String relativePath, Map<String, dynamic> json) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(json);
    await _writeAtomic(file, content);
  }

  /// 原子写入 JSON 数组文件。
  Future<void> writeList(
    String relativePath,
    List<Map<String, dynamic>> json,
  ) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(json);
    await _writeAtomic(file, content);
  }

  /// 追加/覆盖写入原始文本（用于导出通用格式）。
  Future<void> writeText(String relativePath, String content) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    await file.parent.create(recursive: true);
    await _writeAtomic(file, content);
  }

  Future<String?> readText(String relativePath) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 删除文件（不存在时静默成功）。
  Future<void> delete(String relativePath) async {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 列出某目录下的文件（不含 .tmp）。
  Future<List<String>> listFiles(
    String relativeDir, {
    String extension = '.json',
  }) async {
    final dir = Directory('${root.path}${Platform.pathSeparator}$relativeDir');
    try {
      if (!await dir.exists()) return [];
      return await dir
          .list()
          .where(
            (e) =>
                e is File &&
                e.path.endsWith(extension) &&
                !e.path.endsWith('.tmp'),
          )
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 原子写入：写临时文件 -> 替换目标。
  Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}
