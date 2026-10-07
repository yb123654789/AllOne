import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 颜色工具 + 颜色选择器（全项目共用，避免各页面各写一份 `_hex`）。
///
/// 之前日历的「添加特殊日子」只有 5 个固定色块，**无法自定义颜色**；
/// 这里提供：常用色板 + RGB 微调 + 十六进制输入，任意颜色都能选。

/// Color → '#RRGGBB'
String colorToHex(Color c) {
  String two(int n) => n.clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
}

/// '#RGB' / '#RRGGBB' / '#AARRGGBB' → Color（容错；解析失败返回 [fallback]）
Color hexColor(String hex, {Color fallback = AppTheme.primary}) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// 常用颜色（快捷选择；不够用可以进「自定义」任意调）
const List<String> kPresetColors = <String>[
  '#E5484D',
  '#F76808',
  '#F5A623',
  '#FFD60A',
  '#8FBF1F',
  '#30A46C',
  '#12A594',
  '#00A2C7',
  '#1E88E5',
  '#2F6FED',
  '#5B5BD6',
  '#7C3AED',
  '#AB4ABA',
  '#D6409F',
  '#E93D82',
  '#8D4B2A',
  '#6A7280',
  '#1F2329',
  '#FFFFFF',
  '#000000',
];

/// 弹出颜色选择器，返回 '#RRGGBB'；取消返回 null。
Future<String?> showColorPickerDialog(
  BuildContext context, {
  String initial = '#2F6FED',
  String title = '选择颜色',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ColorPickerDialog(initial: initial, title: title),
  );
}

/// 颜色选择对话框：色板 + RGB 滑块 + 十六进制输入，互相联动。
class ColorPickerDialog extends StatefulWidget {
  final String initial;
  final String title;

  const ColorPickerDialog({
    super.key,
    this.initial = '#2F6FED',
    this.title = '选择颜色',
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _color;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _color = hexColor(widget.initial);
    _hexCtrl = TextEditingController(text: colorToHex(_color));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  /// 应用颜色；[syncText] 为 false 时不动输入框（避免用户打字时被改写）
  void _apply(Color c, {bool syncText = true}) {
    setState(() {
      _color = c;
      if (syncText) _hexCtrl.text = colorToHex(c);
    });
  }

  void _onHexChanged(String v) {
    final t = v.trim().replaceFirst('#', '');
    if (t.length != 3 && t.length != 6) return; // 还没输完，不打断输入
    final c = hexColor(t, fallback: _color);
    if (c == _color) return;
    setState(() => _color = c);
  }

  @override
  Widget build(BuildContext context) {
    final r = (_color.r * 255).round();
    final g = (_color.g * 255).round();
    final b = (_color.b * 255).round();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.divider),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      decoration: const InputDecoration(
                        labelText: '十六进制',
                        hintText: '#2F6FED',
                        isDense: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9a-fA-F#]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      onChanged: _onHexChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '常用颜色',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final hex in kPresetColors) _swatch(hex)],
              ),
              const SizedBox(height: 16),
              const Text(
                '微调（红 / 绿 / 蓝）',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              _slider('红', r, (v) {
                _apply(Color.fromARGB(255, v.round(), g, b));
              }),
              _slider('绿', g, (v) {
                _apply(Color.fromARGB(255, r, v.round(), b));
              }),
              _slider('蓝', b, (v) {
                _apply(Color.fromARGB(255, r, g, v.round()));
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, colorToHex(_color)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _swatch(String hex) {
    final c = hexColor(hex);
    final selected = colorToHex(c) == colorToHex(_color);
    return InkWell(
      onTap: () => _apply(c),
      customBorder: const CircleBorder(),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.textPrimary : AppTheme.divider,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, int value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
