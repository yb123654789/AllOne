import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'core/backup/backup_service.dart';
import 'core/models/nav_settings.dart';
import 'core/storage/nav_providers.dart';
import 'core/theme.dart';
import 'features/calendar/calendar_page.dart';
import 'features/diary/diary_page.dart';
import 'features/habit/habit_page.dart';
import 'features/ledger/ledger_page.dart';
import 'features/schedule/schedule_page.dart';
import 'features/settings/settings_page.dart';
import 'features/todo/todo_page.dart';
import 'features/tools/tools_page.dart';

/// AllOne 根组件：应用主题 + 底部导航壳。
class AllOneApp extends StatelessWidget {
  const AllOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AllOne',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}

/// 主界面：底部导航切换六大功能模块。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  /// 功能 key -> 页面（顺序与 [kAppFeatures] 一致）
  static final Map<String, Widget> _pages = {
    'diary': const DiaryPage(),
    'todo': const TodoPage(),
    'habit': const HabitPage(),
    'schedule': const SchedulePage(),
    'ledger': const LedgerPage(),
    'calendar': const CalendarPage(),
    'tools': const ToolsPage(),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    final children = [
      for (final f in kAppFeatures) _pages[f.key] ?? const SizedBox.shrink(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: children),
      drawer: const AppDrawer(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(homeTabIndexProvider.notifier).state = i,
        destinations: [
          for (final f in kAppFeatures)
            NavigationDestination(
              icon: Icon(f.icon),
              selectedIcon: Icon(f.selectedIcon),
              label: f.label,
            ),
        ],
      ),
    );
  }
}

/// 侧边栏：功能快捷入口（可按配置隐藏）+ 一键导出/导入 + 设置。
class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  bool _busy = false;

  /// 一键导出：打包全部数据为 zip 并分享（可存 U 盘）
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

  /// 一键导入：选择备份 zip 并恢复
  Future<void> _import() async {
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'AllOne',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '日记 · 待办 · 习惯 · 课程 · 记账 · 日历',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('功能',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          ..._sidebarFeatureTiles(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('数据（一键备份 / 迁移）',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt, color: Colors.green),
            title: const Text('一键导出'),
            subtitle: const Text('打包全部数据为 zip，可存 U 盘 / 分享'),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined, color: AppTheme.primary),
            title: const Text('从备份导入'),
            subtitle: const Text('选择之前导出的 zip，恢复数据'),
            enabled: !_busy,
            onTap: _import,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune, color: AppTheme.primary),
            title: const Text('设置 / 侧边栏管理'),
            subtitle: const Text('选择哪些功能显示在侧边栏'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 侧边栏的功能入口（按 [NavSettings] 过滤显示）；点击跳转到对应 tab。
  List<Widget> _sidebarFeatureTiles() {
    final nav = ref.watch(navSettingsProvider).valueOrNull ?? const NavSettings();
    final current = ref.watch(homeTabIndexProvider);
    return [
      for (final f in kAppFeatures)
        if (nav.isSidebarVisible(f.key))
          ListTile(
            leading: Icon(
              current == kAppFeatures.indexOf(f)
                  ? f.selectedIcon
                  : f.icon,
              color: current == kAppFeatures.indexOf(f)
                  ? AppTheme.primary
                  : null,
            ),
            title: Text(
              f.label,
              style: current == kAppFeatures.indexOf(f)
                  ? const TextStyle(color: AppTheme.primary)
                  : null,
            ),
            selected: current == kAppFeatures.indexOf(f),
            onTap: () {
              Navigator.pop(context);
              ref.read(homeTabIndexProvider.notifier).state =
                  kAppFeatures.indexOf(f);
            },
          ),
    ];
  }
}
