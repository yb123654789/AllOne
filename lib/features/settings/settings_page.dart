import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_service.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';

/// 设置页：备份 / 恢复 / 数据目录。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  String _dataDir = '';
  String _sizeText = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
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
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final zipPath = await BackupService.exportBackup();
      await Share.shareXFiles([XFile(zipPath)], text: 'AllOne 数据备份（U 盘手动备份用）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('恢复将覆盖当前所有数据，且不可撤销。确定继续吗？\n\n建议先导出一份当前备份。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('恢复成功，请重启应用以刷新数据')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_outlined, color: AppTheme.primary),
                  title: const Text('数据目录'),
                  subtitle: Text(_dataDir.isEmpty ? '加载中…' : _dataDir),
                ),
                ListTile(
                  leading: const Icon(Icons.data_usage, color: AppTheme.primary),
                  title: const Text('当前数据大小'),
                  subtitle: Text(_sizeText.isEmpty ? '加载中…' : _sizeText),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.green),
                  title: const Text('导出备份'),
                  subtitle: const Text('打包全部数据为 zip，可复制到 U 盘 / 外部存储'),
                  onTap: _busy ? null : _export,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore, color: AppTheme.danger),
                  title: const Text('从备份恢复'),
                  subtitle: const Text('选择之前导出的 zip，覆盖当前数据'),
                  onTap: _busy ? null : _restore,
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined, color: AppTheme.primary),
              title: const Text('关于数据安全'),
              subtitle: const Text('所有数据本地保存，采用通用 JSON 格式。'
                  '备份方式：U 盘手动备份（推荐），导出 zip 保存到 U 盘即可。'
                  '云同步默认关闭，确保信息不被第三方访问。'),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
  }
}
