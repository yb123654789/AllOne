import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_paths.dart';
import 'json_store.dart';

/// 通用 JSON 存储 provider（懒初始化 + 缓存）。
/// 各模块通过 `ref.watch(jsonStoreProvider)` 获取同一份 JsonStore。
final jsonStoreProvider = FutureProvider<JsonStore>((ref) async {
  final root = await AppPaths.dataRoot();
  return JsonStore(root);
});
