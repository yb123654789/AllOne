import 'calendar_models.dart';

/// 倒数日「过期自动处理」的**纯逻辑**：只做列表变换，不碰存储，便于单元测试。
///
/// 规则（与用户确认过的需求一致）：
/// - 单次项（考试等）：**过了那一天**就「过期」等待归档；**当天不算过期**。
/// - 每年重复项（生日等）：过期后自动推进到下一次，原始日期留在 [SpecialDay.originDate]，
///   所以「第 N 周年」不受影响。
class SpecialDayLifecycle {
  const SpecialDayLifecycle._();

  /// 每年重复项推进到下一次（单次项原样保留）。
  ///
  /// 返回新列表；没有任何变化时，内容与入参逐项相同（配合 [changed] 决定是否写盘）。
  static List<SpecialDay> advanceRecurring(
    List<SpecialDay> all,
    String today,
  ) {
    return [
      for (final s in all) s.repeatYearly ? s.advancedTo(today) : s,
    ];
  }

  /// 已过期、等待用户确认归档的单次项（按日期升序：最早过期的排前面）。
  static List<SpecialDay> expiredOneOffs(List<SpecialDay> all, String today) {
    return all.where((s) => s.isCustom && s.isExpiredOn(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 把指定 id 移入回收站（已归档的保持不变）
  static List<SpecialDay> archive(
    List<SpecialDay> all,
    Iterable<String> ids,
    String today,
  ) {
    final set = ids.toSet();
    return [
      for (final s in all)
        if (set.contains(s.id)) s.archivedOn(today) else s,
    ];
  }

  /// 从回收站恢复
  static List<SpecialDay> restore(List<SpecialDay> all, String id) => [
    for (final s in all)
      if (s.id == id) s.restored() else s,
  ];

  /// 彻底删除一条
  static List<SpecialDay> remove(List<SpecialDay> all, String id) => [
    for (final s in all)
      if (s.id != id) s,
  ];

  /// 彻底删除多条（清空回收站）
  static List<SpecialDay> removeAll(
    List<SpecialDay> all,
    Iterable<String> ids,
  ) {
    final set = ids.toSet();
    return [
      for (final s in all)
        if (!set.contains(s.id)) s,
    ];
  }

  /// 回收站内容：最近归档的排前面
  static List<SpecialDay> trashed(List<SpecialDay> all) =>
      all.where((s) => s.archived).toList()
        ..sort((a, b) => (b.archivedAt ?? '').compareTo(a.archivedAt ?? ''));

  /// 两个列表是否有实质变化（决定要不要写盘）
  static bool changed(List<SpecialDay> a, List<SpecialDay> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.date != y.date ||
          x.originDate != y.originDate ||
          x.archived != y.archived ||
          x.archivedAt != y.archivedAt) {
        return true;
      }
    }
    return false;
  }
}
