import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/widgets/color_picker.dart';

/// 自定义颜色相关纯逻辑测试：
/// 日历「特殊日子」以前只能从 5 个固定色块里选，现在可以任意取色，
/// 这里保证 hex 与 Color 的互转是可靠、容错的。
void main() {
  group('颜色转换', () {
    test('Color → #RRGGBB（忽略透明度）', () {
      expect(colorToHex(const Color(0xFF2F6FED)), '#2F6FED');
      expect(colorToHex(const Color(0x802F6FED)), '#2F6FED');
      expect(colorToHex(const Color(0xFF000000)), '#000000');
      expect(colorToHex(const Color(0xFFFFFFFF)), '#FFFFFF');
    });

    test('#RRGGBB 解析', () {
      expect(hexColor('#2F6FED'), const Color(0xFF2F6FED));
      expect(hexColor('2f6fed'), const Color(0xFF2F6FED));
    });

    test('#RGB 简写会展开', () {
      expect(hexColor('#F00'), const Color(0xFFFF0000));
    });

    test('#AARRGGBB 带透明度解析', () {
      expect(hexColor('#802F6FED'), const Color(0x802F6FED));
    });

    test('非法输入回退到 fallback（不抛异常）', () {
      expect(hexColor('不是颜色', fallback: const Color(0xFF123456)),
          const Color(0xFF123456));
      expect(hexColor('', fallback: const Color(0xFF123456)),
          const Color(0xFF123456));
      expect(hexColor('#12345', fallback: const Color(0xFF123456)),
          const Color(0xFF123456));
    });

    test('round-trip：任意颜色转 hex 再解析回来一致（RGB 部分）', () {
      for (final c in const [
        Color(0xFFE5484D),
        Color(0xFFF5A623),
        Color(0xFF30A46C),
        Color(0xFF1E88E5),
        Color(0xFF7C3AED),
        Color(0xFFD6409F),
      ]) {
        expect(hexColor(colorToHex(c)), c);
      }
    });

    test('预设色板全部可解析，且格式统一为 #RRGGBB', () {
      for (final hex in kPresetColors) {
        expect(hex, matches(RegExp(r'^#[0-9A-F]{6}$')));
        expect(hexColor(hex), isNotNull);
        expect(colorToHex(hexColor(hex)), hex);
      }
    });
  });
}
