import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_service.dart';
import '../../core/models/ui_prefs.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/nav_providers.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import '../../core/updater/update_service.dart';
import '../../core/updater/update_ui.dart';
import '../../core/widgets/tile_sources.dart';
import 'text_exporter.dart';

/// 设置页：备份 / 恢复 / 通用文本导出 / 数据目录 / 检查更新。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  String _dataDir = '';
  String _sizeText = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
    UpdateService.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _loadInfo() async {
    final root = await AppPaths.dataRoot();
    final bytes = await BackupService.dataSizeBytes();
    setState(() {
      _dataDir = root.path;
      _sizeText = _fmtSize(bytes);
    });
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 更新代理当前设置（供界面显示）
  String get _proxyText {
    final v = ref.watch(uiPrefsProvider).valueOrNull?.updateProxy ?? '';
    if (v == 'direct') return '当前：强制直连（不使用代理）';
    if (v.isNotEmpty) return '当前：$v';
    return '当前：自动（读取 Windows 系统代理）\n'
        '国内直连 GitHub 常被重置导致检查更新失败，可在此指定代理（如 127.0.0.1:7890）。';
  }

  Future<void> _editUpdateProxy() async {
    final ctrl = TextEditingController(
      text: ref.read(uiPrefsProvider).valueOrNull?.updateProxy ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新代理'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '代理地址（host:port）',
                hintText: '例如 127.0.0.1:7890',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '留空 = 自动读取 Windows 系统代理；\n'
              '填 direct = 强制直连（不使用代理）。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final value = ctrl.text.trim();
    await ref.read(uiPrefsProvider.notifier).set(UiPrefs.updateProxyKey, value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.isEmpty ? '更新代理：自动' : '更新代理：$value')),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final zipPath = await BackupService.exportBackup();
      await Share.shareXFiles([XFile(zipPath)], text: 'AllOne 数据备份（U 盘手动备份用）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('恢复将覆盖当前所有数据，且不可撤销。确定继续吗？\n\n建议先导出一份当前备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('恢复并覆盖'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.restoreFromZip(path);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('恢复成功，请重启应用以刷新数据')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导出通用文本（Markdown / txt），打包 zip 后分享
  Future<void> _exportText() async {
    setState(() => _busy = true);
    try {
      final zipPath = await TextExporter.exportText(ref);
      await Share.shareXFiles([
        XFile(zipPath),
      ], text: 'AllOne 通用文本导出（Markdown / txt，可用记事本打开）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 打开数据目录（Windows 用资源管理器；其他平台提示手动打开）
  void _openDataDir() {
    if (_dataDir.isEmpty) return;
    if (Platform.isWindows) {
      try {
        Process.start('explorer', [_dataDir]);
      } catch (_) {}
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('数据目录：$_dataDir')));
    }
  }

  /// 选择地图底图源
  Future<void> _pickMapSource() async {
    final current = ref.read(tileSourceProvider);
    final picked = await showDialog<TileSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择地图底图'),
        children: [
          for (final s in TileSources.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Row(
                children: [
                  Icon(
                    s.id == current.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: s.id == current.id
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: const TextStyle(fontSize: 14)),
                        if (s.gcj02)
                          const Text(
                            '坐标有偏移（GCJ-02），仅影响地图显示位置',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await ref.read(navSettingsProvider.notifier).setMapSource(picked.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('底图已切换为：${picked.name}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(tileSourceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('数据目录'),
                  subtitle: Text(_dataDir.isEmpty ? '加载中…' : _dataDir),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: _openDataDir,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.data_usage,
                    color: AppTheme.primary,
                  ),
                  title: const Text('当前数据大小'),
                  subtitle: Text(_sizeText.isEmpty ? '加载中…' : _sizeText),
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined, color: AppTheme.primary),
              title: const Text('地图底图'),
              subtitle: Text(
                '${source.name}\n'
                'OSM 官方瓦片在国内常连不上导致地图空白，可在此换源；'
                '也可把标准 XYZ 瓦片放到 AllOneData/map_tiles 离线使用。',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _pickMapSource,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.shield_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('数据与程序分离'),
              subtitle: const Text(
                '你的所有数据（日记 / 待办 / 记账等）保存在系统「文档」目录的 '
                'AllOneData 文件夹中，与程序文件（.exe）完全分离。\n'
                '传播或拷贝程序不会带走你的数据；数据可手动复制到 U 盘备份。',
              ),
              isThreeLine: true,
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.green),
                  title: const Text('导出备份'),
                  subtitle: const Text('打包全部数据为 zip（含附件），可复制到 U 盘 / 外部存储'),
                  onTap: _busy ? null : _export,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('导出通用文本'),
                  subtitle: const Text(
                    '将日记 / 待办 / 习惯 / 课程 / 记账导出为 Markdown / txt，'
                    '任何设备可用记事本打开',
                  ),
                  onTap: _busy ? null : _exportText,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.settings_backup_restore,
                    color: AppTheme.danger,
                  ),
                  title: const Text('从备份恢复'),
                  subtitle: const Text('选择之前导出的 zip，覆盖当前数据'),
                  onTap: _busy ? null : _restore,
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.shield_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('关于数据安全'),
              subtitle: const Text(
                '所有数据本地保存，采用通用 JSON 格式。'
                '备份方式：U 盘手动备份（推荐），导出 zip 保存到 U 盘即可。'
                '云同步默认关闭，确保信息不被第三方访问。',
              ),
              isThreeLine: true,
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.system_update_alt,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    '检查更新（当前版本 ${_version.isEmpty ? '读取中…' : _version}）',
                  ),
                  subtitle: const Text(
                    '从 GitHub Releases 检查新版本，可在应用内直接下载并覆盖安装；'
                    '更新只替换程序文件，你的数据（文档\\AllOneData）不会被改动。',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showUpdateDialog(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.vpn_lock_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('更新代理'),
                  subtitle: Text(_proxyText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editUpdateProxy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
