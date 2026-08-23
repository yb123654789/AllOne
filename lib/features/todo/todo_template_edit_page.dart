import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import '../../core/widgets/location_map_picker.dart';
import '../../core/widgets/rich_text_editor.dart';
import 'todo_models.dart';
import 'todo_repository.dart';

/// 待办模板编辑页（新建 / 编辑模板）。
class TodoTemplateEditPage extends ConsumerStatefulWidget {
  final TodoTemplate? template;

  const TodoTemplateEditPage({super.key, this.template});

  @override
  ConsumerState<TodoTemplateEditPage> createState() =>
      _TodoTemplateEditPageState();
}

class _TodoTemplateEditPageState extends ConsumerState<TodoTemplateEditPage> {
  late final String _id;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _plainCtrl;
  late final QuillController _richCtrl;
  final List<String> _tags = [];
  late final TextEditingController _tagInput;

  TodoMode _mode = TodoMode.plain;
  DeadlineInfo _deadline = const DeadlineInfo();
  LocationInfo _location = const LocationInfo();

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _id = t?.id ?? AppPaths.newId();
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _plainCtrl = TextEditingController(text: t?.contentPlain ?? '');
    _richCtrl = QuillController(
      document: QuillCodec.decode(t?.contentRich ?? ''),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _tagInput = TextEditingController();
    if (t != null) {
      _mode = t.mode;
      _deadline = t.deadline;
      _location = t.location;
      _tags.addAll(t.tags);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _plainCtrl.dispose();
    _richCtrl.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入模板名称')));
      }
      return;
    }
    final now = DateTime.now();
    final t = TodoTemplate(
      id: _id,
      name: _nameCtrl.text.trim(),
      title: _titleCtrl.text.trim(),
      mode: _mode,
      contentPlain: _mode == TodoMode.plain
          ? _plainCtrl.text
          : _richCtrl.document.toPlainText(),
      contentRich: _mode == TodoMode.rich
          ? QuillCodec.encode(_richCtrl.document)
          : '',
      deadline: _deadline,
      location: _location,
      tags: List.of(_tags),
      createdAt: widget.template?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(todoTemplateListProvider.notifier).save(t);
    if (mounted) Navigator.pop(context);
  }

  void _addTag() {
    final s = _tagInput.text.trim();
    if (s.isNotEmpty && !_tags.contains(s)) {
      setState(() => _tags.add(s));
      _tagInput.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? '新建待办模板' : '编辑待办模板'),
        actions: [
          IconButton(
            onPressed: _save,
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '模板名称（如：周报 / 采购清单）',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: '待办标题预设（可留空）'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('内容模式：', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    SegmentedButton<TodoMode>(
                      segments: const [
                        ButtonSegment(
                          value: TodoMode.plain,
                          label: Text('纯文本'),
                        ),
                        ButtonSegment(value: TodoMode.rich, label: Text('富文本')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                      showSelectedIcon: false,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_mode == TodoMode.plain)
                  TextField(
                    controller: _plainCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '模板内容（纯文本，类似 txt）…',
                    ),
                  )
                else
                  SizedBox(
                    height: 220,
                    child: RichTextEditor(
                      controller: _richCtrl,
                      placeholder: '模板内容（富文本，可含勾选列表）…',
                    ),
                  ),
                const SizedBox(height: 12),
                _optionTile(
                  icon: Icons.schedule_outlined,
                  title: '截止时间',
                  subtitle: _deadline.date.isEmpty
                      ? '未设置'
                      : '${_deadline.date}${_deadline.time.isEmpty ? '' : ' ${_deadline.time}'}',
                  onTap: _pickDeadline,
                ),
                _optionTile(
                  icon: Icons.place_outlined,
                  title: '地点',
                  subtitle: _location.text.isEmpty ? '未设置' : _location.text,
                  onTap: _pickLocation,
                ),
                const SizedBox(height: 12),
                Text(
                  '标签',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _tags)
                      InputChip(
                        label: Text(t),
                        onDeleted: () => setState(() => _tags.remove(t)),
                      ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _tagInput,
                        decoration: const InputDecoration(hintText: '加标签后回车'),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }

  // —— 截止时间选择（与待办编辑页一致） ——
  Future<void> _pickDeadline() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          var d = _deadline;
          DateTime? date = d.date.isEmpty ? null : DateTime.tryParse(d.date);
          return AlertDialog(
            title: const Text('截止时间'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('日期'),
                  subtitle: Text(date == null ? '未设置' : AppTime.dateOnly(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(
                        () => d = DeadlineInfo(
                          date: AppTime.dateOnly(picked),
                          time: d.time,
                          color: d.color,
                          highlight: d.highlight,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  title: const Text('时间'),
                  subtitle: Text(d.time.isEmpty ? '未设置' : d.time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: d.time.isEmpty
                          ? const TimeOfDay(hour: 9, minute: 0)
                          : _parseTime(d.time),
                    );
                    if (picked != null) {
                      setState(
                        () => d = DeadlineInfo(
                          date: d.date,
                          time:
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                          color: d.color,
                          highlight: d.highlight,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  title: const Text('颜色标记'),
                  subtitle: Text(d.color),
                  trailing: _colorDot(d.color),
                  onTap: () async {
                    final c = await _pickColor(ctx, d.color);
                    if (c != null) {
                      setState(
                        () => d = DeadlineInfo(
                          date: d.date,
                          time: d.time,
                          color: c,
                          highlight: d.highlight,
                        ),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('醒目高亮'),
                  value: d.highlight,
                  onChanged: (v) => setState(
                    () => d = DeadlineInfo(
                      date: d.date,
                      time: d.time,
                      color: d.color,
                      highlight: v,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '清除',
                  style: TextStyle(color: AppTheme.danger),
                ),
              ),
              TextButton(
                onPressed: () {
                  _deadline = d;
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  // —— 地点选择（与待办编辑页一致） ——
  Future<void> _pickLocation() async {
    final textCtrl = TextEditingController(text: _location.text);
    String color = _location.color;
    bool highlight = _location.highlight;
    double lat = _location.lat;
    double lng = _location.lng;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('地点'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(labelText: '地点名称'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final point = await LocationMapPicker.show(
                      context,
                      lat: lat == 0 ? null : lat,
                      lng: lng == 0 ? null : lng,
                      name: textCtrl.text.trim().isEmpty
                          ? null
                          : textCtrl.text.trim(),
                    );
                    if (point != null) {
                      setState(() {
                        lat = point.latitude;
                        lng = point.longitude;
                        if (textCtrl.text.trim().isEmpty) {
                          textCtrl.text = '地图标记点';
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('在地图上选点'),
                ),
              ),
              ListTile(
                title: const Text('颜色标记'),
                subtitle: Text(color),
                trailing: _colorDot(color),
                onTap: () async {
                  final c = await _pickColor(ctx, color);
                  if (c != null) setState(() => color = c);
                },
              ),
              SwitchListTile(
                title: const Text('醒目高亮'),
                value: highlight,
                onChanged: (v) => setState(() => highlight = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _location = LocationInfo(
                  text: '',
                  color: color,
                  highlight: highlight,
                );
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('清除', style: TextStyle(color: AppTheme.danger)),
            ),
            TextButton(
              onPressed: () {
                _location = LocationInfo(
                  text: textCtrl.text.trim(),
                  color: color,
                  highlight: highlight,
                  lat: lat,
                  lng: lng,
                );
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickColor(BuildContext ctx, String current) async {
    const colors = [
      '#E5484D',
      '#F76B15',
      '#F5A623',
      '#30A46C',
      '#1E88E5',
      '#7C3AED',
      '#5C5C5C',
    ];
    return showDialog<String>(
      context: ctx,
      builder: (c) => SimpleDialog(
        title: const Text('选择颜色'),
        children: [
          for (final col in colors)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, col),
              child: Row(
                children: [
                  _colorDot(col),
                  const SizedBox(width: 12),
                  Text(col),
                  if (col == current) const Spacer(),
                  if (col == current)
                    const Icon(Icons.check, color: AppTheme.primary, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _colorDot(String hex) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: _hex(hex), shape: BoxShape.circle),
    );
  }

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFE5484D);
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }
}
