import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/ui_prefs.dart';
import 'package:allone/core/storage/json_store.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/core/storage/ui_prefs_providers.dart';

/// UI 偏好（记忆显示方式）测试。
/// 重点：写进 `settings/ui.json` 后，**重启（新建容器重新读盘）仍然记得**。
void main() {
  late Directory temp;

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [jsonStoreProvider.overrideWith((ref) async => JsonStore(temp))],
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('allone_ui_prefs');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('UI 偏好', () {
    test('默认是 auto（没写过任何偏好时）', () async {
      final c = newContainer();
      addTearDown(c.dispose);
      expect(await c.read(uiPrefsProvider.future), isA<UiPrefs>());
      expect(c.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutAuto);
    });

    test('选择「按天」后写入磁盘，重启（新容器）仍然记得', () async {
      final c1 = newContainer();
      await c1.read(uiPrefsProvider.future);
      await c1.read(uiPrefsProvider.notifier).setScheduleLayout(
        UiPrefs.scheduleLayoutList,
      );
      // 写入后内存状态立即生效（界面不会闪回默认）
      expect(c1.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutList);
      expect(
        File('${temp.path}/settings/ui.json').existsSync(),
        isTrue,
        reason: '偏好应落盘到 settings/ui.json',
      );
      c1.dispose();

      // 模拟重启：全新容器重新读盘
      final c2 = newContainer();
      addTearDown(c2.dispose);
      await c2.read(uiPrefsProvider.future);
      expect(c2.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutList);
    });

    test('「恢复自动」会把偏好写回 auto', () async {
      final c = newContainer();
      addTearDown(c.dispose);
      final n = c.read(uiPrefsProvider.notifier);
      await n.setScheduleLayout(UiPrefs.scheduleLayoutGrid);
      expect(c.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutGrid);
      await n.setScheduleLayout(UiPrefs.scheduleLayoutAuto);
      expect(c.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutAuto);
    });

    test('合并写入：不同 key 互不覆盖', () async {
      final c = newContainer();
      addTearDown(c.dispose);
      final n = c.read(uiPrefsProvider.notifier);
      await n.setScheduleLayout(UiPrefs.scheduleLayoutGrid);
      await n.set('somethingElse', true);
      final prefs = await c.read(uiPrefsProvider.future);
      expect(prefs.scheduleLayout, UiPrefs.scheduleLayoutGrid);
      expect(prefs.flag('somethingElse'), isTrue);
    });

    test('文件损坏 / 字段类型不对时回退默认，不抛异常', () async {
      final dir = Directory('${temp.path}/settings')..createSync(recursive: true);
      File('${dir.path}/ui.json').writeAsStringSync('{"scheduleLayout": 123}');
      final c = newContainer();
      addTearDown(c.dispose);
      await c.read(uiPrefsProvider.future);
      expect(c.read(scheduleLayoutPrefProvider), UiPrefs.scheduleLayoutAuto);
    });
  });
}
