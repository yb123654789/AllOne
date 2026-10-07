import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/app_paths.dart';
import 'update_models.dart';

/// 应用内更新服务：检查新版本 → 下载安装包 → 覆盖安装（数据不动）。
///
/// 关键设计：
/// - **数据与程序分离**：安装包只覆盖程序文件，`文档\AllOneData` 完全不碰，
///   所以更新后数据照旧（这也是为什么必须用固定签名：见 android/key.properties）。
/// - **更新前可选自动备份**：老版本（≤1.2.1）的卸载器会删数据，
///   从那些版本升级时默认先复制一份数据目录，兜底。
/// - **绝不在后台偷偷安装**：所有下载与安装都由用户在对话框里点确认。
class UpdateService {
  UpdateService._();

  /// 发布仓库（GitHub Releases）
  static const String repo = 'yb123654789/AllOne';

  static const String _apiLatest =
      'https://api.github.com/repos/$repo/releases/latest';

  /// 首次使用「数据安全安装包」的版本：从此版本起，升级/卸载都不会删数据。
  /// 低于它的旧版本升级时，默认在更新前自动备份数据目录。
  static const String firstSafeInstallerVersion = '1.2.2';

  /// 当前应用版本（来自 pubspec，如 `1.2.2`）
  static Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  /// 当前平台类型
  static UpdateTarget get target {
    if (Platform.isWindows) return UpdateTarget.windows;
    if (Platform.isAndroid) return UpdateTarget.android;
    return UpdateTarget.other;
  }

  /// 检查是否有新版本。网络失败 / 没有发布时返回 null（不抛异常）。
  static Future<UpdateInfo?> checkForUpdate({
    String? currentVersionOverride,
    HttpClient? client,
  }) async {
    final current =
        currentVersionOverride ?? await UpdateService.currentVersion();
    if (current.isEmpty) return null;
    final http = client ?? HttpClient();
    try {
      http.connectionTimeout = const Duration(seconds: 12);
      final req = await http.getUrl(Uri.parse(_apiLatest));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'AllOne-Updater');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final info = parseLatestRelease(json);
      if (info == null) return null;
      return isNewerVersion(info.version, current) ? info : null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 下载产物到临时目录，返回本地文件路径。
  ///
  /// [onProgress] 会收到 (已下载字节, 总字节)，总字节未知时为 0。
  static Future<File> download(
    UpdateAsset asset, {
    void Function(int received, int total)? onProgress,
    HttpClient? client,
  }) async {
    final dir = await _downloadDir();
    final file = File(p.join(dir.path, asset.name));
    if (await file.exists()) await file.delete();

    final http = client ?? HttpClient();
    try {
      http.connectionTimeout = const Duration(seconds: 20);
      final req = await http.getUrl(Uri.parse(asset.url));
      req.headers.set('User-Agent', 'AllOne-Updater');
      req.followRedirects = true;
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('下载失败：HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength > 0 ? resp.contentLength : asset.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      return file;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 下载目录：优先应用私有目录（Android 上 FileProvider 可读），
  /// 桌面端用系统临时目录。
  static Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory(p.join(ext.path, 'update'));
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'allone_update'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // —— 安装 ——

  /// Windows：静默运行安装包覆盖升级。
  ///
  /// 参数含义（Inno Setup）：
  /// - `/SILENT` 只显示进度不显示向导；
  /// - `/SUPPRESSMSGBOXES` 抑制弹窗（卸载旧版时的询问取**默认按钮**，
  ///   而我们的安装包默认是「保留数据」）；
  /// - `/NORESTART` 不自动重启电脑；
  /// - `/CLOSEAPPLICATIONS` 关闭占用文件的程序（即本 App）。
  ///
  /// 返回后调用方应尽快退出应用，让安装程序替换文件。
  static Future<void> installWindows(String installerPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('仅 Windows 支持静默安装安装包');
    }
    await Process.start(installerPath, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
  }

  /// Windows：用系统程序打开安装包（用户手动点下一步）。
  static Future<void> openInstallerManually(String path) async {
    await Process.start('cmd', ['/c', 'start', '', path]);
  }

  /// Android：调起系统安装界面（覆盖安装，保留数据）。
  ///
  /// 需要 `REQUEST_INSTALL_PACKAGES` 权限 —— 调用方应先请求（见 update_ui）。
  /// 注意：覆盖安装要求新旧 APK **签名一致**（见 android/key.properties）。
  /// 返回 null 表示已成功调起安装界面，否则返回错误说明。
  static Future<String?> installAndroid(String apkPath) async {
    if (!Platform.isAndroid) throw UnsupportedError('仅 Android 支持 APK 安装');
    try {
      final result = await OpenFilex.open(apkPath);
      if (result.type == ResultType.done) return null;
      return '无法调起安装界面（${result.type.name}）：${result.message}';
    } catch (e) {
      return '调用安装器失败：$e';
    }
  }

  // —— 数据安全 ——

  /// 更新前把整个数据目录复制一份到 `文档\AllOneData_backup_<时间>`。
  ///
  /// 为什么要这么做：1.2.1 及更早的安装包在卸载（升级时会自动卸载旧版）
  /// 时会删除 `文档\AllOneData`。从这些版本升级时先留一份兜底。
  /// 返回备份目录路径。
  static Future<String> backupDataDir({
    void Function(int files, int bytes)? onProgress,
  }) async {
    final root = await AppPaths.dataRoot();
    final docs = root.parent;
    final stamp = _stamp(DateTime.now());
    final dest = Directory(p.join(docs.path, 'AllOneData_backup_$stamp'));
    var count = 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: root.path);
      final target = p.join(dest.path, rel);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
        count++;
        bytes += await entity.length();
        if (count % 20 == 0) onProgress?.call(count, bytes);
      }
    }
    onProgress?.call(count, bytes);
    return dest.path;
  }

  /// 是否需要「更新前备份」：从会删数据的旧版本升级时必须
  static bool needsBackupBeforeUpdate(String currentVersion) =>
      compareVersions(currentVersion, firstSafeInstallerVersion) < 0;

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  /// 是否运行在支持的平台（Windows / Android）
  static bool get canSelfUpdate =>
      !kIsWeb && (Platform.isWindows || Platform.isAndroid);
}
