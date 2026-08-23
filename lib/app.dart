import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'core/backup/backup_service.dart';
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
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    DiaryPage(),
    TodoPage(),
    HabitPage(),
    SchedulePage(),
    LedgerPage(),
    CalendarPage(),
    ToolsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      drawer: const AppDrawer(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '日记',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: '待办',
          ),
          NavigationDestination(
            icon: Icon(Icons.repeat_outlined),
            selectedIcon: Icon(Icons.repeat),
            label: '习惯',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: '课程',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '记账',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman),
            label: '工具',
          ),
        ],
      ),
    );
  }
}

/// 侧边栏：一键导出/导入 + 设置等入口。
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
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
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置 / 更多'),
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
}
