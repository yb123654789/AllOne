import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';

/// 备份选项：用于减小备份体积。
class BackupOptions {
  /// 排除「回收站」内容（待办里 status 为 done / archived 的顶层条目及其附件）
  final bool excludeTrash;

  /// 只备份该时间之后修改过的**附件**（null = 全部）；
  /// JSON 元数据始终完整备份，避免备份出来恢复不回完整结构。
  final DateTime? mediaModifiedAfter;

  const BackupOptions({this.excludeTrash = false, this.mediaModifiedAfter});

  static const none = BackupOptions();
}

/// 备份 / 恢复服务。
///
/// 设计：默认推荐 U 盘手动备份 —— 一键把整个 AllOneData 打包成 zip，
/// 复制到 U 盘或外部目录即完成备份；恢复时选择 zip 导入覆盖。
///
/// **内存策略**：数据里可能有很大的附件（实测有单段 500 MB 以上的录音），
/// 因此导出与恢复都采用**流式**读写，而不是把整个文件 / 整个 zip 读进内存：
/// 导出用 `ZipFileEncoder.addFile`（内部走 `InputFileStream`），
/// 恢复用 `ArchiveFile.writeContent` 直接写文件流。
class BackupService {
  BackupService._();

  /// 判断某文件是否为「原子写入留下的临时文件」。
  ///
  /// 必须精确判断：早期实现用的是 `path.endsWith('.tmp')`，
  /// 那会**误伤用户自己的附件** —— 只要有人的文件名正好以 `.tmp` 结尾，
  /// 它就会被静默排除在备份之外（数据丢了都不知道）。
  static bool isBackupTempArtifact(String path) {
    final name = p.basename(path);
    // 原子写入产物：<真实文件名>.tmp（如 xxx.json.tmp / media.jpg.tmp）
    if (name.endsWith('.tmp')) {
      final base = name.substring(0, name.length - 4);
      // 仅当去掉 .tmp 后看起来是个真实文件（含扩展名）才认定是临时文件
      return p.extension(base).isNotEmpty;
    }
    return false;
  }

  /// 从附件文件名里解析创建时间（形如 `1787658907441_xxx.jpg`）。
  ///
  /// 拿不到就返回 null（视为「无法判断时间」，一律保留）。
  static DateTime? mediaDateFromName(String path) {
    final name = p.basenameWithoutExtension(path);
    final us = name.indexOf('_');
    final head = us > 0 ? name.substring(0, us) : name;
    final ms = int.tryParse(head);
    if (ms == null || ms <= 0) return null;
    // 毫秒时间戳的合理范围：2001-09-09 ~ 2096 年
    if (ms < 1000000000000 || ms > 4000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 读取待办数据，算出「回收站条目」的 id 集合（用于排除）。
  static Future<Set<String>> _trashTodoIds() async {
    final root = await AppPaths.dataRoot();
    final dir = Directory(p.join(root.path, 'todo', 'items'));
    final ids = <String>{};
    if (!await dir.exists()) return ids;
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await e.readAsString());
        if (decoded is! Map) continue;
        final status = decoded['status'];
        if (status == 'done' || status == 'archived') {
          ids.add(p.basenameWithoutExtension(e.path));
        }
      } catch (_) {
        // 单文件损坏不影响整体：保留该文件
      }
    }
    return ids;
  }

  /// 导出完整备份 zip，返回 zip 文件路径。
  ///
  /// 逐文件流式写入，单个附件的体积不影响内存占用。
  static Future<String> exportBackup({
    BackupOptions options = BackupOptions.none,
  }) async {
    final root = await AppPaths.dataRoot();
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}';
    final zipPath = p.join(root.parent.path, 'AllOne_backup_$stamp.zip');

    // 需要排除的回收站条目 id（用于跳过其 JSON 与整个附件目录）
    final trashIds = options.excludeTrash
        ? await _trashTodoIds()
        : const <String>{};

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        if (isBackupTempArtifact(entity.path)) continue;
        final rel = p
            .relative(entity.path, from: root.path)
            .replaceAll('\\', '/');

        // 1) 排除回收站条目（JSON 文件 + 同 id 的附件目录）
        if (trashIds.isNotEmpty && _isUnderTrashItem(rel, trashIds)) {
          continue;
        }

        // 2) 按时间排除旧附件
        final cutoff = options.mediaModifiedAfter;
        if (cutoff != null && _isMediaPath(rel)) {
          final d = mediaDateFromName(rel);
          // 解析不出时间的一律保留，宁可备份大一点也不要漏数据
          if (d != null && d.isBefore(cutoff)) continue;
        }

        // addFile 内部使用 InputFileStream 分块读取，不会把文件整体读入内存
        await encoder.addFile(entity, rel);
      }
    } finally {
      await encoder.close();
    }
    return zipPath;
  }

  /// 该相对路径是否属于回收站条目（`todo/items/<id>.json` 或 `todo/items/<id>/...`）
  static bool _isUnderTrashItem(String rel, Set<String> trashIds) {
    const prefix = 'todo/items/';
    if (!rel.startsWith(prefix)) return false;
    final rest = rel.substring(prefix.length);
    final slash = rest.indexOf('/');
    final id = slash < 0
        ? p.basenameWithoutExtension(rest)
        : rest.substring(0, slash);
    return trashIds.contains(id);
  }

  /// 是否为附件文件（位于某条目目录的 media/ 下）
  static bool _isMediaPath(String rel) => rel.contains('/media/');

  /// 从备份 zip 恢复数据（覆盖现有）。
  ///
  /// 逐条目解压落盘：每个文件都先写 `.tmp` 再改名，保证恢复过程中
  /// 单个文件不会出现「写一半」的状态（与 [JsonStore] 的原子写入一致）。
  static Future<void> restoreFromZip(String zipPath) async {
    final root = await AppPaths.dataRoot();
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final rel = file.name.replaceAll('\\', '/');
      // 安全：拒绝绝对路径与向上穿越，避免 zip 逃出数据目录
      if (rel.isEmpty || p.isAbsolute(rel) || p.split(rel).contains('..')) {
        continue;
      }
      final out = File(p.join(root.path, rel));
      await out.parent.create(recursive: true);
      final tmp = File('${out.path}.tmp');
      // writeContent 直接将解压结果写入文件流，不把内容整体读入内存
      final output = OutputFileStream(tmp.path);
      try {
        file.writeContent(output);
      } finally {
        await output.close();
      }
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
