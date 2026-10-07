/// 应用内更新：版本号比较与 GitHub Releases 解析（纯逻辑，便于单元测试）。
library;

/// 当前平台需要的发布产物
enum UpdateTarget { windows, android, other }

/// 一个可下载的发布产物
class UpdateAsset {
  final String name;
  final String url;
  final int size; // 字节，未知为 0

  const UpdateAsset({required this.name, required this.url, this.size = 0});

  /// 人类可读体积
  String get sizeText {
    if (size <= 0) return '大小未知';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 一次检测到的更新
class UpdateInfo {
  final String version; // 1.2.3（去掉 v 前缀）
  final String tag; // v1.2.3
  final String notes; // 发布说明
  final UpdateAsset? windows;
  final UpdateAsset? android;
  final String publishedAt;

  const UpdateInfo({
    required this.version,
    required this.tag,
    this.notes = '',
    this.windows,
    this.android,
    this.publishedAt = '',
  });

  /// 当前平台该下载哪个产物
  UpdateAsset? assetFor(UpdateTarget target) => switch (target) {
    UpdateTarget.windows => windows,
    UpdateTarget.android => android,
    UpdateTarget.other => null,
  };
}

/// 去掉 `v` 前缀与 `+build` 后缀，取出 X.Y.Z
String normalizeVersion(String raw) {
  var v = raw.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  if (v.contains('+')) v = v.split('+').first;
  return v;
}

/// 版本号比较：返回 -1 / 0 / 1。
///
/// 按数字逐段比较（`1.2.10 > 1.2.9`，字符串比较会搞错），
/// 段数不同时缺的段按 0 处理（`1.2` == `1.2.0`）。
int compareVersions(String a, String b) {
  final pa = normalizeVersion(a).split('.');
  final pb = normalizeVersion(b).split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? int.tryParse(pa[i].trim()) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i].trim()) ?? 0 : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

/// [candidate] 是否比 [current] 新
bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

/// 从产物文件名判断它属于哪个平台
///
/// 约定（见 release/README.md）：
/// - Windows 安装包 `AllOne_Setup_vX.Y.Z.exe`
/// - Android `AllOne-vX.Y.Z.apk`
UpdateTarget targetOfAsset(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.apk')) return UpdateTarget.android;
  if (n.endsWith('.exe') && n.contains('setup')) return UpdateTarget.windows;
  return UpdateTarget.other;
}

/// 从文件名里取出版本号（`AllOne_Setup_v1.2.3.exe` → `1.2.3`）
String versionFromAssetName(String name) {
  final m = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(name);
  return m == null ? '' : m.group(1)!;
}

/// 解析 GitHub `releases/latest` 的 JSON。
///
/// 找不到 Windows / Android 产物时对应字段为 null（仍然算一次有效更新，
/// 便于提示「有新版本，但当前平台没有对应安装包」）。
UpdateInfo? parseLatestRelease(Map<String, dynamic> json) {
  final tag = (json['tag_name'] ?? json['name'] ?? '') as String;
  if (tag.trim().isEmpty) return null;
  final version = normalizeVersion(tag);
  if (version.isEmpty) return null;

  UpdateAsset? windows;
  UpdateAsset? android;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '') as String;
      final url = (a['browser_download_url'] ?? '') as String;
      if (name.isEmpty || url.isEmpty) continue;
      final size = (a['size'] as num?)?.toInt() ?? 0;
      final asset = UpdateAsset(name: name, url: url, size: size);
      switch (targetOfAsset(name)) {
        case UpdateTarget.windows:
          windows ??= asset;
        case UpdateTarget.android:
          android ??= asset;
        case UpdateTarget.other:
          break;
      }
    }
  }

  return UpdateInfo(
    version: version,
    tag: tag,
    notes: ((json['body'] ?? '') as String).trim(),
    windows: windows,
    android: android,
    publishedAt: (json['published_at'] ?? '') as String,
  );
}
