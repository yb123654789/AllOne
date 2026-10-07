import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_prefs.dart';
import 'storage_providers.dart';

/// UI 偏好 Notifier：持久化到 `settings/ui.json`。
///
/// 与 [NavSettingsNotifier] 同样地，写入后**立即更新内存 state**
/// （而不是只 invalidateSelf），这样界面上刚点完的选择马上生效，
/// 不会因为重新加载而闪回默认值。
class UiPrefsNotifier extends AsyncNotifier<UiPrefs> {
  static const _path = 'settings/ui.json';

  @override
  Future<UiPrefs> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    return UiPrefs.fromJson(await store.read(_path));
  }

  /// 写入一个偏好项（不是整体覆盖：先读出当前值再合并）
  Future<void> set(String key, Object? value) async {
    final store = await ref.read(jsonStoreProvider.future);
    final current = state.valueOrNull ?? const UiPrefs();
    final next = current.withValue(key, value);
    await store.write(_path, next.toJson());
    state = AsyncData(next);
  }

  /// 课程表周视图排布：auto / grid / list
  Future<void> setScheduleLayout(String value) =>
      set(UiPrefs.scheduleLayoutKey, value);
}

final uiPrefsProvider = AsyncNotifierProvider<UiPrefsNotifier, UiPrefs>(
  UiPrefsNotifier.new,
);

/// 课程表排布偏好（字符串，读取时已容错为 auto）
final scheduleLayoutPrefProvider = Provider<String>((ref) {
  return ref.watch(uiPrefsProvider).valueOrNull?.scheduleLayout ??
      UiPrefs.scheduleLayoutAuto;
});
