import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/nav_settings.dart';
import 'core/storage/nav_providers.dart';
import 'core/theme.dart';
import 'features/calendar/calendar_page.dart';
import 'features/diary/diary_page.dart';
import 'features/habit/habit_page.dart';
import 'features/ledger/ledger_page.dart';
import 'features/schedule/schedule_page.dart';
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
    final nav =
        ref.watch(navSettingsProvider).valueOrNull ?? const NavSettings();
    var visible = bottomBarFeatures(nav);
    // 防止全部隐藏导致空导航
    if (visible.isEmpty) visible = List.of(kAppFeatures);
    final currentKey = ref.watch(homeTabProvider);

    // IndexedStack 始终包含全部功能页面，保证工具页「功能导航」能切换到任何功能，
    // 即使该功能已从底部导航栏隐藏（隐藏只影响底边栏自身）。
    final bodyIndex = kAppFeatures.indexWhere((f) => f.key == currentKey);
    final safeBodyIndex = bodyIndex < 0 ? 0 : bodyIndex;
    final children = [
      for (final f in kAppFeatures) _pages[f.key] ?? const SizedBox.shrink(),
    ];

    // 底边栏只展示可见功能；当前功能被隐藏时（通过工具页功能导航切过来），
    // 底边栏没有对应项，选中项回退到第一个可见功能。
    final barIndex = visible.indexWhere((f) => f.key == currentKey);
    final safeBarIndex = barIndex < 0 ? 0 : barIndex;

    return Scaffold(
      body: IndexedStack(index: safeBodyIndex, children: children),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeBarIndex,
        onDestinationSelected: (i) =>
            ref.read(homeTabProvider.notifier).state = visible[i].key,
        destinations: [
          for (final f in visible)
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
