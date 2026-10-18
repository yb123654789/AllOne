import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_service.dart';
import '../../core/models/nav_settings.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/nav_providers.dart';
import '../../core/theme.dart';
import '../diary/diary_import_page.dart';
import '../diary/diary_templates_page.dart';
import '../notes/notes_export.dart';
import '../schedule/course_edit_page.dart';
import '../schedule/course_stats_page.dart';
import '../schedule/term_manage_page.dart';
import '../settings/settings_page.dart';
import '../settings/text_exporter.dart';
import '../todo/todo_templates_page.dart';

/// 工具中心：集中收纳「非直接使用」的辅助功能。
///
/// 与 settings / calendar 类似，属于**聚合视图**：
/// 只读引用各模块的模板管理页 / 导出服务，不修改其他模块内部实现。
/// 汇总以下能力：
/// - 数据备份与迁移（导出 zip / 导入 zip / 导出通用文本）
/// - 数据管理（数据目录 / 数据大小 / 存储说明）
/// - 模板管理（日记模板 / 待办模板 / 任务链）
/// - 关于 AllOne（项目介绍 / 数据安全说明）
class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
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
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 一键导出：打包全部数据为 zip 并分享（可存 U 盘）
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

  /// 从备份 zip 导入并覆盖
  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text('导入将覆盖当前所有数据，且不可撤销。确定继续吗？\n\n建议先导出一份当前备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('导入并覆盖'),
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
            .showSnackBar(const SnackBar(content: Text('导入成功，请重启应用以刷新数据')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
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

  /// 导出全部笔记（合并成一份 Markdown 后分享）
  Future<void> _exportNotes() async {
    setState(() => _busy = true);
    try {
      await NotesExporter.exportAll(ref);
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

  /// 弹出项目介绍对话框
  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于 AllOne'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'AllOne 是一个个人全功能生活管理软件，将六大核心功能整合到一个跨平台应用中：',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              SizedBox(height: 8),
              Text(
                '📔 日记 · ✅ 待办 · 🔁 习惯 · 🏫 课程表 · 💰 记账 · 📅 日历',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              SizedBox(height: 8),
              Text(
                '数据完全本地保存、格式通用（JSON / 纯文本），'
                '支持 U 盘手动备份，信息安全第一、运行稳定、模块化风险隔离。',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '常用入口',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              SizedBox(height: 4),
              Text(
                '· 备份 / 迁移：底部「工具」→ 数据备份与迁移\n'
                '· 模板管理：底部「工具」→ 模板管理\n'
                '· 完整设置：底部「工具」→ 打开完整设置\n'
                '· 功能导航：底部「工具」→ 一键切换任意主功能',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
            ],
          ),
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '关于 AllOne',
            onPressed: _showAbout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _sectionLabel('功能导航（快速切换）'),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < kAppFeatures.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _featureTile(kAppFeatures[i]),
                ],
              ],
            ),
          ),
          _sectionLabel('底部导航显示设置'),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '选择哪些功能显示在底部导航栏中（关闭后仍可从本页「功能导航」进入）\n「工具」为常驻入口，无需也无法关闭',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                for (final f in kAppFeatures)
                  if (f.key != 'tools')
                    SwitchListTile(
                      dense: true,
                      secondary: Icon(f.icon),
                      title: Text(f.label),
                      value: _isBottomBarVisible(f.key),
                      onChanged: (v) => _setBottomBarVisible(f.key, v),
                    ),
              ],
            ),
          ),
          _sectionLabel('数据备份与迁移'),
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
                    '将日记 / 笔记 / 待办 / 习惯 / 课程 / 记账导出为 Markdown / txt，任何设备可用记事本打开',
                  ),
                  onTap: _busy ? null : _exportText,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.note_alt_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('导出全部笔记'),
                  subtitle: const Text(
                    '每个主题一份 Markdown（含年月时间线），方便外发 / 归档',
                  ),
                  onTap: _busy ? null : _exportNotes,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.file_upload_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('导入外部日记'),
                  subtitle: const Text(
                    '把之前在其他软件写的日记（txt / PDF）导入，按日期自动分篇，'
                    '只新增、不覆盖现有日记',
                  ),
                  isThreeLine: true,
                  onTap: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DiaryImportPage(),
                          ),
                        ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.settings_backup_restore,
                    color: AppTheme.danger,
                  ),
                  title: const Text('从备份导入'),
                  subtitle: const Text('选择之前导出的 zip，覆盖当前数据'),
                  onTap: _busy ? null : _restore,
                ),
              ],
            ),
          ),
          _sectionLabel('数据管理'),
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
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.data_usage,
                    color: AppTheme.primary,
                  ),
                  title: const Text('当前数据大小'),
                  subtitle: Text(_sizeText.isEmpty ? '加载中…' : _sizeText),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.shield_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('数据与程序分离'),
                  subtitle: const Text(
                    '所有数据保存在系统「文档」目录的 AllOneData 文件夹，'
                    '与程序文件（.exe）完全分离，传播程序不会带走数据。',
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
          ),
          _sectionLabel('模板管理'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('日记模板'),
                  subtitle: const Text('管理写日记时一键套用的模板'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiaryTemplatesPage(),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.checklist, color: AppTheme.primary),
                  title: const Text('待办模板'),
                  subtitle: const Text('管理「内容 + 截止 + 地点 + 标签」一键套用模板'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TodoTemplatesPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel('课程表'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.school_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('学期管理'),
                  subtitle: const Text('建学期（填起止日期）+ 编辑作息表（第几节几点）'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TermManagePage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.add_box_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('添加课程'),
                  subtitle: const Text('选星期、第几节、上哪些周就行，不用手填时间'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CourseEditPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.list_alt_outlined,
                    color: AppTheme.primary,
                  ),
                  title: const Text('课程统计'),
                  subtitle: const Text('查看全部课程与时段（点进去可修改）'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CourseStatsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel('关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: AppTheme.primary,
                  ),
                  title: const Text('关于 AllOne'),
                  subtitle: const Text('项目介绍、常用入口说明'),
                  onTap: _showAbout,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.tune, color: AppTheme.primary),
                  title: const Text('打开完整设置'),
                  subtitle: const Text('查看更多备份 / 恢复 / 数据说明'),
                  onTap: _openSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    ),
  );

  /// 功能导航入口：点击切换底部导航 tab
  Widget _featureTile(AppFeature f) {
    final current = ref.watch(homeTabProvider);
    final active = current == f.key;
    return ListTile(
      leading: Icon(
        active ? f.selectedIcon : f.icon,
        color: active ? AppTheme.primary : null,
      ),
      title: Text(
        f.label,
        style: active ? const TextStyle(color: AppTheme.primary) : null,
      ),
      subtitle: Text(
        f.key == 'tools' ? '当前页（备份 / 模板 / 设置等）' : '切换到「${f.label}」主界面',
      ),
      trailing: active
          ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
          : null,
      onTap: () => ref.read(homeTabProvider.notifier).state = f.key,
    );
  }

  bool _isBottomBarVisible(String key) {
    final nav =
        ref.watch(navSettingsProvider).valueOrNull ?? const NavSettings();
    return nav.isBottomBarVisible(key);
  }

  void _setBottomBarVisible(String key, bool v) {
    // 底部导航至少保留一个功能，避免空导航
    if (!v) {
      final nav =
          ref.read(navSettingsProvider).valueOrNull ?? const NavSettings();
      final visible = kAppFeatures
          .where((f) => nav.isBottomBarVisible(f.key))
          .toList();
      if (visible.length <= 1 && visible.any((f) => f.key == key)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('底部导航至少需要保留一个功能')));
        return;
      }
    }
    ref.read(navSettingsProvider.notifier).setBottomBarVisible(key, v);
  }
}
