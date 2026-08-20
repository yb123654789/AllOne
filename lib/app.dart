import 'package:flutter/material.dart';

import 'features/calendar/calendar_page.dart';
import 'features/diary/diary_page.dart';
import 'features/habit/habit_page.dart';
import 'features/ledger/ledger_page.dart';
import 'features/schedule/schedule_page.dart';
import 'features/settings/settings_page.dart';
import 'features/todo/todo_page.dart';
import 'core/theme.dart';

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
    LedgerPage(),
    CalendarPage(),
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
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '日记'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: '待办'),
          NavigationDestination(icon: Icon(Icons.repeat_outlined), selectedIcon: Icon(Icons.repeat), label: '习惯'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: '记账'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '日历'),
        ],
      ),
    );
  }
}

/// 侧边栏：课程表、备份与设置等入口。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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
                Text('AllOne',
                    style: TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('日记 · 待办 · 习惯 · 课程 · 记账 · 日历',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: const Text('课程表'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SchedulePage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置 / 备份'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
        ],
      ),
    );
  }
}
