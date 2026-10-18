import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'notes_logic.dart';

/// 笔记主题 / 分组可选颜色（与全应用主色调一致的克制配色）
const List<String> kNotePalette = [
  '#2F6FED', // 蓝（默认）
  '#E5484D', // 红
  '#F2A93B', // 橙
  '#2E9E6B', // 绿
  '#7C5CFF', // 紫
  '#E0559B', // 粉
  '#0EA5E9', // 青
  '#6A7280', // 灰
];

/// 把存进 JSON 的颜色字符串转成 Color（非法值退回主色）
Color noteColor(String hex) => Color(parseHexColor(hex) ?? 0xFF2F6FED);

/// 主题卡片左侧的竖色条
class NoteColorBar extends StatelessWidget {
  final String color;
  final double width;
  final double height;

  const NoteColorBar({
    super.key,
    required this.color,
    this.width = 4,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: noteColor(color),
        borderRadius: BorderRadius.circular(width),
      ),
    );
  }
}

/// 颜色选择器：一排圆点，选中打勾
class NoteColorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const NoteColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in kNotePalette)
          InkWell(
            onTap: () => onChanged(hex),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: noteColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex == value ? AppTheme.textPrimary : Colors.white,
                  width: hex == value ? 2 : 1,
                ),
              ),
              child: hex == value
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
