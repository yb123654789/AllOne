import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';

/// 备份 / 恢复服务。
///
/// 设计：默认推荐 U 盘手动备份 —— 一键把整个 AllOneData 打包成 zip，
/// 复制到 U 盘或外部目录即完成备份；恢复时选择 zip 导入覆盖。
class BackupService {
  BackupService._();

  /// 导出完整备份 zip，返回 zip 文件路径。
  static Future<String> exportBackup() async {
    final root = await AppPaths.dataRoot();
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}';
    final zipPath = p.join(root.parent.path, 'AllOne_backup_$stamp.zip');

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    await for (final entity in root.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.tmp')) {
        final rel = p.relative(entity.path, from: root.path).replaceAll('\\', '/');
        final bytes = await entity.readAsBytes();
        encoder.addArchiveFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    encoder.close();
    return zipPath;
  }

  /// 从备份 zip 恢复数据（覆盖现有）。
  static Future<void> restoreFromZip(String zipPath) async {
    final root = await AppPaths.dataRoot();
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final rel = file.name.replaceAll('\\', '/');
      final out = File(p.join(root.path, rel));
      await out.parent.create(recursive: true);
      final data = file.content as List<int>;
      final tmp = File('${out.path}.tmp');
      await tmp.writeAsBytes(data, flush: true);
      if (await out.exists()) await out.delete();
      await tmp.rename(out.path);
    }
  }

  /// 计算数据目录大小（用于展示）。
  static Future<int> dataSizeBytes() async {
    final root = await AppPaths.dataRoot();
    var total = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) {
        total += await e.length();
      }
    }
    return total;
  }
}
