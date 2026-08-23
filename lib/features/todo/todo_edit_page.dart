import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/utils/media_utils.dart';
import '../../core/widgets/location_map_picker.dart';
import '../../core/widgets/rich_text_editor.dart';
import 'todo_models.dart';
import 'todo_repository.dart';
import 'todo_templates_page.dart';

/// 待办编辑页。
class TodoEditPage extends ConsumerStatefulWidget {
  final TodoItem? item;

  const TodoEditPage({super.key, this.item});

  @override
  ConsumerState<TodoEditPage> createState() => _TodoEditPageState();
}

class _TodoEditPageState extends ConsumerState<TodoEditPage> {
  static const int largeFileThreshold = 50 * 1024 * 1024;

  late final String _itemId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _plainCtrl;
  late final QuillController _richCtrl;
  late final TextEditingController _tagInput;
  TodoMode _mode = TodoMode.plain;

  DeadlineInfo _deadline = const DeadlineInfo();
  LocationInfo _location = const LocationInfo();
  String? _chainId;
  final List<MediaAttachment> _media = [];
  final List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _itemId = it?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: it?.title ?? '');
    _plainCtrl = TextEditingController(text: it?.contentPlain ?? '');
    _richCtrl = QuillController(
      document: QuillCodec.decode(it?.contentRich ?? ''),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _tagInput = TextEditingController();
    if (it != null) {
      _mode = it.mode;
      _deadline = it.deadline;
      _location = it.location;
      _chainId = it.taskChainId;
      _media.addAll(it.media);
      _tags.addAll(it.tags);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _plainCtrl.dispose();
    _richCtrl.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final item = TodoItem(
      id: _itemId,
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
      status: widget.item?.status ?? TodoStatus.pending,
      taskChainId: _chainId,
      media: List.of(_media),
      tags: List.of(_tags),
      createdAt: widget.item?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(todoListProvider.notifier).saveItem(item);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addMedia(MediaType type) async {
    final File? picked;
    switch (type) {
      case MediaType.photo:
        picked = await MediaUtils.pickImage();
      case MediaType.video:
      case MediaType.file:
      case MediaType.audio:
        picked = await MediaUtils.pickAnyFile();
      case MediaType.videoLink:
        picked = null;
    }
    if (picked == null) return;
    final size = await picked.length();
    if (size > largeFileThreshold) {
      setState(
        () => _media.add(
          MediaAttachment(
            type: type,
            external: picked!.path,
            size: size,
            note: '大文件外链',
          ),
        ),
      );
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(p.join(store.root.path, todoMediaDir(_itemId)));
    final name = await MediaUtils.copyToDir(picked, dir);
    if (name != null) {
      setState(
        () => _media.add(MediaAttachment(type: type, file: name, size: size)),
      );
    }
  }

  bool _recording = false;
  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await MediaUtils.stopRecording();
      _recording = false;
      if (path != null) {
        final f = File(path);
        final store = await ref.read(jsonStoreProvider.future);
        final dir = Directory(p.join(store.root.path, todoMediaDir(_itemId)));
        final name = await MediaUtils.copyToDir(f, dir);
        final len = await f.length();
        if (name != null) {
          setState(
            () => _media.add(
              MediaAttachment(type: MediaType.audio, file: name, size: len),
            ),
          );
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (!await MediaUtils.requestMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('需要麦克风权限')));
      }
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(p.join(store.root.path, todoMediaDir(_itemId)));
    if (!await dir.exists()) await dir.create(recursive: true);
    await MediaUtils.startRecording(
      p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_rec.m4a'),
    );
    _recording = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? '新建待办' : '编辑待办'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(hintText: '待办内容 / 标题'),
            ),
          ),
          const SizedBox(height: 8),
          _buildToolbar(context),
          Expanded(child: _buildBody()),
          _buildAttachmentBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: SegmentedButton<TodoMode>(
              segments: const [
                ButtonSegment(value: TodoMode.plain, label: Text('纯文本')),
                ButtonSegment(value: TodoMode.rich, label: Text('富文本')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          _chip(
            icon: Icons.schedule_outlined,
            label: _deadline.date.isEmpty ? '截止' : '截止 ${_deadline.date}',
            color: _deadline.highlight ? _hex(_deadline.color) : null,
            onTap: _pickDeadline,
          ),
          _chip(
            icon: Icons.place_outlined,
            label: _location.text.isEmpty ? '地点' : _location.text,
            color: _location.highlight ? _hex(_location.color) : null,
            onTap: _pickLocation,
          ),
          _chip(
            icon: Icons.account_tree_outlined,
            label: _chainId == null ? '任务链' : '任务链✓',
            onTap: _pickChain,
          ),
          _chip(
            icon: Icons.description_outlined,
            label: '模板',
            onTap: _pickTemplate,
          ),
          _chip(
            icon: Icons.label_outline,
            label: '标签${_tags.isEmpty ? '' : '(${_tags.length})'}',
            onTap: _showTagDialog,
          ),
          if (_media.isNotEmpty)
            _chip(
              icon: Icons.attachment_outlined,
              label: '附件(${_media.length})',
              onTap: _showMedia,
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color ?? AppTheme.primary),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        side: BorderSide(color: color ?? AppTheme.divider),
        backgroundColor: color?.withValues(alpha: 0.1) ?? Colors.transparent,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == TodoMode.plain) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _plainCtrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: '纯文本内容（类似 txt）…',
            filled: false,
          ),
        ),
      );
    }
    return RichTextEditor(controller: _richCtrl, placeholder: '富文本内容，可插入勾选列表…');
  }

  Widget _buildAttachmentBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ab(Icons.photo_outlined, '照片', () => _addMedia(MediaType.photo)),
            _ab(
              _recording ? Icons.stop_circle_outlined : Icons.mic_none,
              _recording ? '停止' : '录音',
              _toggleRecord,
            ),
            _ab(
              Icons.videocam_outlined,
              '视频',
              () => _addMedia(MediaType.video),
            ),
            _ab(Icons.attach_file, '文件', () => _addMedia(MediaType.file)),
          ],
        ),
      ),
    );
  }

  Widget _ab(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primary, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 设置对话框 ——

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

  Future<void> _pickChain() async {
    final chains = ref.read(taskChainListProvider).valueOrNull ?? [];
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '选择任务链',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (chains.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无任务链，请先在「待办-任务链」中创建'),
              ),
            for (final c in chains)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(c.title.isEmpty ? '未命名任务链' : c.title),
                subtitle: Text('进度 ${(c.progress * 100).toStringAsFixed(0)}%'),
                trailing: c.id == _chainId
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _chainId = c.id);
                  Navigator.pop(ctx);
                },
              ),
            if (_chainId != null)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消关联任务链'),
                onTap: () {
                  setState(() => _chainId = null);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showMedia() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('附件列表', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final m in _media)
            ListTile(
              leading: Icon(_mediaIcon(m.type)),
              title: Text(m.file ?? m.external ?? ''),
              subtitle: Text('${(m.size / 1024).toStringAsFixed(1)} KB'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _media.remove(m)),
              ),
            ),
        ],
      ),
    );
  }

  /// 选择待办模板并套用其内容（仅填充字段，不覆盖已填写内容）。
  Future<void> _pickTemplate() async {
    final t = await Navigator.push<TodoTemplate>(
      context,
      MaterialPageRoute(
        builder: (_) => const TodoTemplatesPage(selectable: true),
      ),
    );
    if (t == null || !mounted) return;
    setState(() {
      if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = t.title;
      _mode = t.mode;
      if (t.mode == TodoMode.plain) {
        if (_plainCtrl.text.trim().isEmpty) _plainCtrl.text = t.contentPlain;
      } else {
        if (_richCtrl.document.toPlainText().trim().isEmpty) {
          _richCtrl.document = QuillCodec.decode(t.contentRich);
        }
      }
      if (_deadline.date.isEmpty) _deadline = t.deadline;
      if (_location.text.isEmpty) _location = t.location;
      for (final tag in t.tags) {
        if (!_tags.contains(tag)) _tags.add(tag);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已套用模板「${t.name.isEmpty ? '未命名模板' : t.name}」')),
      );
    }
  }

  void _showTagDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: _tags
                  .map(
                    (t) => InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInput,
                    decoration: const InputDecoration(hintText: '输入标签后回车'),
                    onSubmitted: (_) {
                      final s = _tagInput.text.trim();
                      if (s.isNotEmpty && !_tags.contains(s)) {
                        setState(() => _tags.add(s));
                        _tagInput.clear();
                      }
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final s = _tagInput.text.trim();
                    if (s.isNotEmpty && !_tags.contains(s)) {
                      setState(() => _tags.add(s));
                      _tagInput.clear();
                    }
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  IconData _mediaIcon(MediaType t) {
    switch (t) {
      case MediaType.photo:
        return Icons.photo;
      case MediaType.audio:
        return Icons.mic;
      case MediaType.video:
        return Icons.videocam;
      case MediaType.file:
        return Icons.insert_drive_file;
      case MediaType.videoLink:
        return Icons.link;
    }
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
