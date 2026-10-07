import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ui_prefs.dart';
import '../storage/ui_prefs_providers.dart';
import '../theme.dart';
import 'update_models.dart';
import 'update_service.dart';

/// 应用内更新的界面部分：
/// - [showUpdateDialog]：检查更新 → 展示新版本与说明 → 下载（带进度）
///   →（可选）更新前备份数据 → 覆盖安装；
/// - [checkUpdateOnStartup]：启动时静默检查（每天最多一次），
///   发现新版本时提示，「跳过此版本」会记进偏好。

/// 启动时检查更新（静默失败，不打扰用户）
Future<void> checkUpdateOnStartup(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!UpdateService.canSelfUpdate) return;
  final prefs = ref.read(uiPrefsProvider).valueOrNull;
  if (prefs == null) return;

  // 一天最多查一次：GitHub 匿名接口有次数限制（60 次/小时/IP）
  final last = prefs.str(UiPrefs.lastUpdateCheckKey);
  if (last.isNotEmpty) {
    final t = DateTime.tryParse(last);
    if (t != null && DateTime.now().difference(t).inHours < 24) return;
  }

  final info = await UpdateService.checkForUpdate();
  await ref
      .read(uiPrefsProvider.notifier)
      .set(UiPrefs.lastUpdateCheckKey, DateTime.now().toIso8601String());
  if (info == null || !context.mounted) return;

  // 用户明确跳过过的版本不再打扰
  if (prefs.str(UiPrefs.skippedUpdateKey) == info.version) return;
  if (!context.mounted) return;
  await showUpdateDialog(context, ref, info: info, startup: true);
}

/// 更新对话框。[info] 为 null 时先联网检查。
Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref, {
  UpdateInfo? info,
  bool startup = false,
}) async {
  final current = await UpdateService.currentVersion();
  if (!context.mounted) return;

  var target = info;
  if (target == null) {
    // 手动点击：给一个「正在检查」的提示
    final checking = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在检查更新…'),
          ],
        ),
      ),
    );
    target = await UpdateService.checkForUpdate();
    if (!context.mounted) return;
    Navigator.pop(context); // 关掉「检查中」
    await checking;
    if (!context.mounted) return;
    if (target == null) {
      await _info(
        context,
        '已是最新版本',
        '当前版本：$current\n没有检测到新版本。\n\n'
        '（检查的是 GitHub Releases 上最新一次发布；'
        '网络不通或没有发布时也会走到这里。）',
      );
      return;
    }
  }

  final asset = target.assetFor(UpdateService.target);
  final needBackup = UpdateService.needsBackupBeforeUpdate(current);
  var backup = needBackup; // 从会删数据的旧版本升级时默认备份
  var busy = false;
  var progress = 0.0;
  var status = '';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('发现新版本 ${target!.version}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本 $current → 新版本 ${target.version}'
                  '${target.publishedAt.isEmpty ? '' : '（${target.publishedAt.split('T').first} 发布）'}',
                  style: const TextStyle(fontSize: 13),
                ),
                if (asset != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '安装包：${asset.name}（${asset.sizeText}）',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (target.notes.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Text(
                      target.notes,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                const SizedBox(height: 12),
                // 更新前备份：默认从会删数据的旧版本升级时开启
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: backup,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => backup = v ?? false),
                  title: const Text('更新前备份数据', style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    needBackup
                        ? '检测到你当前版本较旧：它的卸载程序会删除数据目录，'
                              '升级时会自动卸载旧版。强烈建议保持勾选。'
                        : '把 AllOneData 完整复制一份到「文档」目录下（可选）。',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                if (asset == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '当前平台没有对应的安装包产物，请到 Releases 页面手动下载。',
                    style: TextStyle(fontSize: 12, color: AppTheme.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (startup)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await ref
                          .read(uiPrefsProvider.notifier)
                          .set(UiPrefs.skippedUpdateKey, target!.version);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('跳过此版本'),
            ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: Text(startup ? '稍后' : '关闭'),
          ),
          FilledButton(
            onPressed: (busy || asset == null)
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      progress = 0;
                      status = '正在下载…';
                    });
                    final err = await _downloadAndInstall(
                      ctx,
                      target!,
                      asset,
                      backup: backup,
                      onProgress: (v, s) => setState(() {
                        progress = v;
                        status = s;
                      }),
                    );
                    if (!ctx.mounted) return;
                    if (err != null) {
                      setState(() {
                        busy = false;
                        status = err;
                      });
                    }
                  },
            child: const Text('下载并更新'),
          ),
        ],
      ),
    ),
  );
}

/// 下载 → （可选）备份 → 安装。返回错误信息，成功返回 null。
Future<String?> _downloadAndInstall(
  BuildContext context,
  UpdateInfo info,
  UpdateAsset asset, {
  required bool backup,
  required void Function(double progress, String status) onProgress,
}) async {
  try {
    if (backup) {
      onProgress(0, '正在备份数据目录（可能较慢，请勿关闭）…');
      final path = await UpdateService.backupDataDir(
        onProgress: (files, bytes) => onProgress(
          0,
          '正在备份数据：$files 个文件 / ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB',
        ),
      );
      onProgress(0, '数据已备份到 $path');
    }

    onProgress(0, '正在下载安装包…');
    final file = await UpdateService.download(
      asset,
      onProgress: (got, total) {
        final v = total > 0 ? got / total : 0.0;
        onProgress(
          v,
          '正在下载 ${(got / 1024 / 1024).toStringAsFixed(1)}'
          '${total > 0 ? ' / ${(total / 1024 / 1024).toStringAsFixed(1)}' : ''} MB',
        );
      },
    );

    if (Platform.isWindows) {
      onProgress(1, '下载完成，正在启动安装程序（安装完成后会自动打开新版本）…');
      await UpdateService.installWindows(file.path);
      // 尽快退出，让安装程序替换文件（安装包带 /CLOSEAPPLICATIONS）
      await Future<void>.delayed(const Duration(milliseconds: 800));
      exit(0);
    }

    if (Platform.isAndroid) {
      // 安装来自本 App 的 APK 需要「安装未知应用」权限
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        return '需要「安装未知应用」权限才能更新。\n'
            'APK 已下载到：${file.path}\n可手动点击安装。';
      }
      final err = await UpdateService.installAndroid(file.path);
      if (err != null) {
        return '$err\nAPK 已下载到：${file.path}\n可手动点击安装。';
      }
      return null;
    }

    return '当前平台不支持自动更新，已下载：${file.path}';
  } catch (e) {
    return '更新失败：$e';
  }
}

Future<void> _info(BuildContext context, String title, String content) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text(content, style: const TextStyle(fontSize: 13, height: 1.5)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
