import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/schedule/schedule_page.dart';

/// 课程表周视图的宽度计算测试。
///
/// 背景：旧实现是横向 ListView + 7 个固定 150px 的列（≈1050px），
/// 窗口比它宽就右侧留白「对不齐」，比它窄（手机）就只能左右平移。
/// 现在列宽由可用宽度算出来，必须保证「7 列不会超出窗口」。
void main() {
  group('课程表周视图 - 列宽', () {
    const gap = 6.0;
    const padding = 8.0;

    double totalWidth(double col) => col * 7 + gap * 6 + padding * 2;

    test('常见窗口宽度：7 列正好铺满可用宽度（与窗口对齐）', () {
      for (final w in [600.0, 800.0, 1024.0, 1280.0, 1600.0, 1920.0, 2400.0]) {
        final col = scheduleColumnWidth(w, gap: gap);
        expect(totalWidth(col), closeTo(w, 0.01), reason: '窗口宽 $w');
        expect(col * 7, lessThanOrEqualTo(w));
      }
    });

    test('超宽屏：列宽封顶，不再无限拉宽', () {
      final col = scheduleColumnWidth(4000, gap: gap);
      expect(col, 360.0);
      expect(totalWidth(col), lessThan(4000));
    });

    test('极窄窗口：不低于最小列宽（此宽度已走手机纵向布局，仅保证不崩）', () {
      expect(scheduleColumnWidth(10, gap: gap), 60.0);
      expect(scheduleColumnWidth(0, gap: gap), 60.0);
      expect(scheduleColumnWidth(-100, gap: gap), 60.0);
    });

    test('手机上手选「网格」：列宽取最小 60，整体比窗口宽 → 横向平移（用户主动选择）', () {
      final col = scheduleColumnWidth(390, gap: gap);
      expect(col, 60.0);
      expect(totalWidth(col), greaterThan(390));
    });

    test('列数 / 间距参数可调', () {
      final col = scheduleColumnWidth(500, columns: 5, gap: 10);
      expect(col * 5 + 10 * 4 + padding * 2, closeTo(500, 0.01));
    });
  });
}
