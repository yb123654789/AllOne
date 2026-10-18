import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/utils/media_utils.dart';
import '../../core/widgets/attachment_view.dart';
import '../../core/widgets/location_map_picker.dart';
import '../../core/widgets/location_map_view.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 写 / 编辑一条笔记记录。
///
/// 与日记编辑页的差别：
/// - 多一个「发生时间」（可补记过去的事，时间线按它排）；
/// - 没有「时间戳（纪念节点）」「模板」这些日记特有概念。
class NoteEntryEditPage extends ConsumerStatefulWidget {
  final String topicId;
  final NoteEntry? entry;

  const NoteEntryEditPage({super.key, required this.topicId, this.entry});

  @override
  ConsumerState<NoteEntryEditPage> createState() => _NoteEntryEditPageState();
}

class _NoteEntryEditPageState extends ConsumerState<NoteEntryEditPage> {
  /// 大文件阈值：超过则转外链引用（与日记一致）
  static const int largeFileThreshold = 50 * 1024 * 1024;

  late final String _entryId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _plainCtrl;
  final List<String> _tags = [];
  final List<MediaAttachment> _media = [];
  late DateTime _occurredAt;

  bool _locEnabled = false;
  String _locName = '';
  double _locLat = 0;
  double _locLng = 0;

  bool _recording = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _entryId = e?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _plainCtrl = TextEditingController(text: e?.plainText ?? '');
    _occurredAt = e?.occurredAt ?? DateTime.now();
    if (e != null) {
      _tags.addAll(e.tags);
      _media.addAll(e.media);
      _locEnabled = e.locationStamp.enabled;
      _locName = e.locationStamp.name;
      _locLat = e.locationStamp.lat;
      _locLng = e.locationStamp.lng;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _plainCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final plain = _plainCtrl.text;
    if (title.isEmpty && plain.trim().isEmpty && _media.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('写点什么吧（标题、正文或附件）')));
      return;
    }
    final now = DateTime.now();
    final existing = widget.entry;
    final entry = NoteEntry(
      id: _entryId,
      topicId: widget.topicId,
      title: title,
      plainText: plain,
      occurredAt: _occurredAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      tags: List.of(_tags),
      media: List.of(_media),
      locationStamp: LocationStamp(
        enabled: _locEnabled,
        lat: _locLat,
        lng: _locLng,
        name: _locName,
      ),
    );
    await ref.read(noteEntryListProvider(widget.topicId).notifier).save(entry);
    if (mounted) Navigator.pop(context, entry);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(
        () => _occurredAt = DateTime(
          d.year,
          d.month,
          d.day,
          _occurredAt.hour,
          _occurredAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (t != null) {
      setState(
        () => _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          t.hour,
          t.minute,
        ),
      );
    }
  }

  Future<void> _addMedia(MediaType type) async {
    final File? picked;
    switch (type) {
      case MediaType.photo:
        picked = await MediaUtils.pickImage();
      case MediaType.audio:
        picked = await MediaUtils.pickAnyFile();
      case MediaType.video:
        picked = await MediaUtils.pickAnyFile();
      case MediaType.file:
        picked = await MediaUtils.pickAnyFile();
      case MediaType.videoLink:
        picked = null;
    }
    if (picked == null) return;
    final size = await picked.length();
    if (size > largeFileThreshold) {
      setState(() {
        _media.add(
          MediaAttachment(
            type: type,
            external: picked!.path,
            size: size,
            note: '大文件外链',
          ),
        );
      });
      _toastAdded(type);
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(
      p.join(store.root.path, noteMediaDir(widget.topicId, _entryId)),
    );
    final name = await MediaUtils.copyToDir(picked, dir);
    if (name != null && mounted) {
      setState(() {
        _media.add(MediaAttachment(type: type, file: name, size: size));
      });
      _toastAdded(type);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await MediaUtils.stopRecording();
      _recording = false;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) {
          final size = await f.length();
          final store = await ref.read(jsonStoreProvider.future);
          final dir = Directory(
            p.join(store.root.path, noteMediaDir(widget.topicId, _entryId)),
          );
          final name = await MediaUtils.copyToDir(f, dir);
          if (name != null && mounted) {
            setState(() {
              _media.add(MediaAttachment(type: MediaType.audio, file: name, size: size));
            });
            _toastAdded(MediaType.audio);
          }
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (!await MediaUtils.requestMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('需要麦克风权限才能录音')));
      }
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(
      p.join(store.root.path, noteMediaDir(widget.topicId, _entryId)),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_rec.m4a');
    final started = await MediaUtils.startRecording(path);
    _recording = started;
    if (!started && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? '记一条' : '编辑记录'),
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
          _buildTimeBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                hintText: '小标题（可留空，正文首行会当标题）',
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          _buildStampsBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _plainCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 16, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '这次记的内容…（读书摘抄、练习心得、工作复盘都行）',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          _buildAttachedStrip(),
          _buildAttachmentBar(),
        ],
      ),
    );
  }

  /// 发生时间：可点日期 / 时间单独改，方便补记过去
  Widget _buildTimeBar() {
    final isToday =
        dateText(_occurredAt) == dateText(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.event_outlined, size: 16),
            label: Text(isToday ? '今天' : dateText(_occurredAt)),
            visualDensity: VisualDensity.compact,
            onPressed: _pickDate,
          ),
          ActionChip(
            avatar: const Icon(Icons.access_time, size: 16),
            label: Text(
              '${_occurredAt.hour.toString().padLeft(2, '0')}:'
              '${_occurredAt.minute.toString().padLeft(2, '0')}',
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _pickTime,
          ),
          if (!isToday)
            TextButton(
              onPressed: () => setState(() => _occurredAt = DateTime.now()),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('回到现在', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildStampsBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _chip(
            icon: Icons.label_outline,
            label: '标签${_tags.isEmpty ? '' : '(${_tags.length})'}',
            onTap: _showTagDialog,
            active: _tags.isNotEmpty,
          ),
          _chip(
            icon: Icons.location_on_outlined,
            label: _locEnabled ? '位置✓' : '位置',
            onTap: _showLocationDialog,
            active: _locEnabled,
          ),
          if (_media.isNotEmpty)
            _chip(
              icon: Icons.attach_file,
              label: '附件(${_media.length})',
              onTap: _showMediaList,
              active: true,
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ActionChip(
        avatar: Icon(
          icon,
          size: 18,
          color: active ? Colors.white : AppTheme.primary,
        ),
        label: Text(label),
        backgroundColor: active ? AppTheme.primary : Colors.transparent,
        side: BorderSide(color: active ? AppTheme.primary : AppTheme.divider),
        labelStyle: TextStyle(
          color: active ? Colors.white : AppTheme.textPrimary,
          fontSize: 13,
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildAttachmentBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _attachBtn(Icons.photo_outlined, '照片', () => _addMedia(MediaType.photo)),
            _attachBtn(
              _recording ? Icons.stop_circle_outlined : Icons.mic_none,
              _recording ? '停止' : '录音',
              _toggleRecord,
            ),
            _attachBtn(Icons.videocam_outlined, '视频', () => _addMedia(MediaType.video)),
            _attachBtn(Icons.attach_file, '文件', () => _addMedia(MediaType.file)),
          ],
        ),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
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
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<void> _showTagDialog() async {
    // 汇总所有主题记录的标签，方便复用
    final allTags = <String>{..._tags};
    final topics = ref.read(noteTopicListProvider).valueOrNull ?? const <NoteTopic>[];
    for (final t in topics) {
      final entries = ref.read(noteEntryListProvider(t.id)).valueOrNull;
      if (entries == null) continue;
      for (final e in entries) {
        allTags.addAll(e.tags);
      }
    }
    final result = await showTagPicker(
      context,
      allTags: allTags.toList(),
      initial: List.of(_tags),
      title: '标签',
    );
    if (result != null) {
      setState(
        () => _tags
          ..clear()
          ..addAll(result),
      );
    }
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记录位置'),
                value: _locEnabled,
                onChanged: (v) => setState(() => _locEnabled = v),
              ),
              TextFormField(
                enabled: _locEnabled,
                initialValue: _locName,
                decoration: const InputDecoration(labelText: '地点名称（如：图书馆）'),
                onChanged: (v) => _locName = v,
              ),
              const SizedBox(height: 8),
              if (_locEnabled)
                LocationMapView(
                  center: LatLng(
                    _locLat == 0 ? 39.9042 : _locLat,
                    _locLng == 0 ? 116.4074 : _locLng,
                  ),
                  interactive: true,
                  height: 170,
                  onChanged: (pt) => setState(() {
                    _locLat = pt.latitude;
                    _locLng = pt.longitude;
                    if (_locName.isEmpty) _locName = '地图标记点';
                  }),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _locEnabled
                      ? () async {
                          final point = await LocationMapPicker.show(
                            context,
                            lat: _locLat == 0 ? null : _locLat,
                            lng: _locLng == 0 ? null : _locLng,
                            name: _locName.isEmpty ? null : _locName,
                          );
                          if (point != null) {
                            setState(() {
                              _locLat = point.latitude;
                              _locLng = point.longitude;
                              if (_locName.isEmpty) _locName = '地图标记点';
                            });
                          }
                        }
                      : null,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('在地图上选点（离线优先）'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成')),
          ],
        ),
      ),
    );
  }

  /// 添加附件后的即时反馈（与日记 / 待办 / 任务一致）
  void _toastAdded(MediaType type) {
    if (!mounted) return;
    showAttachmentAddedToast(context, type, _media.length);
  }

  /// 已添加的附件：添加后立刻铺开缩略图（公共组件 [MediaThumbStrip]）
  Widget _buildAttachedStrip() {
    final root = ref.read(jsonStoreProvider).valueOrNull?.root.path;
    final mediaDir = root == null
        ? null
        : p.join(root, noteMediaDir(widget.topicId, _entryId));
    return MediaThumbStrip(
      media: _media,
      mediaDir: mediaDir,
      onRemove: (m) => setState(() => _media.remove(m)),
    );
  }

  void _showMediaList() {
    final root = ref.read(jsonStoreProvider).valueOrNull?.root.path;
    final mediaDir = root == null
        ? null
        : p.join(root, noteMediaDir(widget.topicId, _entryId));
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('附件列表', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final m in _media)
            AttachmentTile(
              media: m,
              mediaDir: mediaDir,
              onDelete: () => setState(() => _media.remove(m)),
            ),
        ],
      ),
    );
  }
}
