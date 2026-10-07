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

  /// 进程内自增计数。
  ///
  /// Windows 上 `DateTime.now()` 精度约 1ms，同一毫秒内多次调用会拿到相同的微秒值，
  /// 所以不能只靠时间戳区分。这里改成「秒级时间戳 + 每秒内保证唯一的序号」：
  /// - 同一秒内：序号自增，并记录已发出的后缀，回绕（超过 10 万个）时顺延；
  /// - 跨秒 / 重启：时间戳部分必然不同，且序号起点取自微秒时钟，
  ///   避免本次运行与上次运行在同一秒内撞号。
  ///
  /// 旧写法 `(微秒 % 100000 + 序号 * 7919) % 100000` 会撞号：
  /// 实测连续生成 3000 个 ID 出现 3 个重复（重复 ID 会互相覆盖同一条数据）。
  static int _seq = DateTime.now().microsecondsSinceEpoch % 100000;
  static String _seqSecond = '';
  static final Set<String> _issued = <String>{};

  /// 生成一个条目 ID：yyyyMMddHHmmss-XXXXX
  static String newId() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts =
        '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    if (ts != _seqSecond) {
      // 进入新的一秒：前缀已经不同，已发后缀集合可以清空（避免无限增长）
      _seqSecond = ts;
      _issued.clear();
    }
    var n = _seq++ % 100000;
    var id = '$ts-${n.toString().padLeft(5, '0')}';
    // 同一秒内序号回绕时顺延，保证进程内生成的 ID 绝不重复
    while (!_issued.add(id)) {
      n = (n + 1) % 100000;
      id = '$ts-${n.toString().padLeft(5, '0')}';
    }
    return id;
  }
}
