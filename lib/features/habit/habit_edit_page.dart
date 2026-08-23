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
import '../../core/widgets/rich_text_editor.dart';
import 'habit_models.dart';
import 'habit_repository.dart';

/// 习惯编辑页。
class HabitEditPage extends ConsumerStatefulWidget {
  final Habit? habit;

  const HabitEditPage({super.key, this.habit});

  @override
  ConsumerState<HabitEditPage> createState() => _HabitEditPageState();
}

class _HabitEditPageState extends ConsumerState<HabitEditPage> {
  static const int largeFileThreshold = 50 * 1024 * 1024;

  late final String _id;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _descCtrl;
  late final QuillController _descRichCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _tagInput;
  HabitType _type = HabitType.count;

  /// 描述模式：纯文本 / 富文本（与待办一致）
  bool _descRichMode = false;
  final List<MediaAttachment> _media = [];
  final List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _id = h?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: h?.title ?? '');
    _categoryCtrl = TextEditingController(text: h?.category ?? '通用');
    _descCtrl = TextEditingController(text: h?.description ?? '');
    _descRichCtrl = QuillController(
      document: QuillCodec.decode(h?.descriptionRich ?? ''),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _targetCtrl = TextEditingController(
      text: (h?.target.value ?? 30).toString(),
    );
    _tagInput = TextEditingController();
    _type = h?.target.type ?? HabitType.count;
    if (h != null) {
      _descRichMode = h.descriptionRich.isNotEmpty;
      _media.addAll(h.media);
      _tags.addAll(h.tags);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _descCtrl.dispose();
    _descRichCtrl.dispose();
    _targetCtrl.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final habit = Habit(
      id: _id,
      title: _titleCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty
          ? '通用'
          : _categoryCtrl.text.trim(),
      target: HabitTarget(
        type: _type,
        value: int.tryParse(_targetCtrl.text.trim()) ?? 30,
      ),
      description: _descRichMode
          ? _descRichCtrl.document.toPlainText()
          : _descCtrl.text.trim(),
      descriptionRich: _descRichMode
          ? QuillCodec.encode(_descRichCtrl.document)
          : '',
      media: List.of(_media),
      tags: List.of(_tags),
      createdAt: widget.habit?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(habitListProvider.notifier).saveHabit(habit);
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
    final dir = Directory(p.join(store.root.path, habitMediaDir(_id)));
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
        final len = await f.length();
        final store = await ref.read(jsonStoreProvider.future);
        final dir = Directory(p.join(store.root.path, habitMediaDir(_id)));
        final name = await MediaUtils.copyToDir(f, dir);
        if (name != null && mounted) {
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
    final dir = Directory(p.join(store.root.path, habitMediaDir(_id)));
    if (!await dir.exists()) await dir.create(recursive: true);
    await MediaUtils.startRecording(
      p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_rec.m4a'),
    );
    _recording = true;
    if (mounted) setState(() {});
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
        title: Text(widget.habit == null ? '新建习惯' : '编辑习惯'),
        actions: [
          IconButton(
            onPressed: _save,
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '习惯名称（如：每日阅读）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(labelText: '分类（如：学习 / 健康 / 生活）'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<HabitType>(
                  segments: const [
                    ButtonSegment(value: HabitType.count, label: Text('按次数')),
                    ButtonSegment(
                      value: HabitType.duration,
                      label: Text('按天数'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _targetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _type == HabitType.count ? '目标次数' : '目标天数',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('描述格式：', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('纯文本')),
                  ButtonSegment(value: true, label: Text('富文本')),
                ],
                selected: {_descRichMode},
                onSelectionChanged: (s) =>
                    setState(() => _descRichMode = s.first),
                showSelectedIcon: false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_descRichMode)
            SizedBox(
              height: 200,
              child: RichTextEditor(
                controller: _descRichCtrl,
                placeholder: '习惯描述（富文本，可含列表 / 勾选）…',
              ),
            )
          else
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '习惯描述（内容 / 备注）'),
            ),
          const SizedBox(height: 16),
          Text(
            '标签',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
          const SizedBox(height: 16),
          Text(
            '附件',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
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
              if (_media.isNotEmpty)
                _ab(
                  Icons.image_outlined,
                  '附件(${_media.length})',
                  _showMediaList,
                ),
            ],
          ),
          if (_media.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final m in _media)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_mediaIcon(m.type), size: 18),
                title: Text(
                  m.file ?? m.external ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => setState(() => _media.remove(m)),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            '打卡说明：创建后在列表页点击习惯卡片即可完成当日打卡；按次数习惯每日可多次打卡。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
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
            Icon(icon, color: AppTheme.primary, size: 20),
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

  void _showMediaList() {
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
}
