import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 数据目录路径管理。
///
/// 所有数据保存在一个用户可见、可复制的根目录 `AllOneData/` 下，
/// 方便用 U 盘手动备份。目录结构见 docs/DATA_FORMAT.md。
class AppPaths {
  AppPaths._();

  static const String dataDirName = 'AllOneData';

  /// 数据根目录（AllOneData/）
  static Future<Directory> dataRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, dataDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 某模块的子目录，例如 diary、todo……
  static Future<Directory> moduleDir(String module) async {
    final root = await dataRoot();
    final dir = Directory(p.join(root.path, module));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 进程内自增计数：Windows 上 `DateTime.now()` 精度约 1ms，
  /// 批量创建（如导入）时同一毫秒内多次调用会得到相同的微秒值，
  /// 叠加计数可保证同一进程内生成的 ID 不重复。
  static int _seq = 0;

  /// 生成一个条目 ID：yyyyMMddHHmmss-XXXXX
  static String newId() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts =
        '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final rand =
        ((now.microsecondsSinceEpoch % 100000) + (_seq++ % 100000) * 7919) %
        100000;
    return '$ts-${rand.toString().padLeft(5, '0')}';
  }
}
