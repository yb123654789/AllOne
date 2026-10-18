import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/common.dart';
import 'core/models/nav_settings.dart';
import 'core/storage/nav_providers.dart';
import 'core/theme.dart';
import 'core/updater/update_ui.dart';
import 'features/calendar/calendar_page.dart';
import 'features/calendar/calendar_repository.dart';
import 'features/diary/diary_page.dart';
import 'features/habit/habit_page.dart';
import 'features/ledger/ledger_page.dart';
import 'features/notes/notes_page.dart';
import 'features/quest/quest_page.dart';
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
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// 功能 key -> 页面（顺序与 [kAppFeatures] 一致）
  static final Map<String, Widget> _pages = {
    'diary': const DiaryPage(),
    'notes': const NotesPage(),
    'todo': const TodoPage(),
    'quest': const QuestPage(),
    'habit': const HabitPage(),
    'schedule': const SchedulePage(),
    'ledger': const LedgerPage(),
    'calendar': const CalendarPage(),
    'tools': const ToolsPage(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 启动时静默检查更新（每天最多一次；发现新版本才提示，失败不打扰）
      checkUpdateOnStartup(context, ref);
      // 倒数日生命周期：把「每年重复」的日子推进到下一次（生日过了自动滚到明年）。
      // 这里静默执行、不弹窗；过期**单次**项的归档需要用户确认，
      // 只在「特殊日子 · 倒数日」页里询问。
      await ref
          .read(specialDayListProvider.notifier)
          .advanceRecurring(today: AppTime.dateOnly(DateTime.now()));
    });
  }

  @override
  Widget build(BuildContext context) {
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
        // 功能多（加笔记后最多 9 个）时，只给选中项显示文字：
        // 9 个"图标 + 文字"挤在手机宽度里会互相挤压 / 溢出。
        // 想看全部名称可展开选中项，或在「工具 → 底部导航显示设置」里精简。
        labelBehavior: visible.length > 5
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
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
