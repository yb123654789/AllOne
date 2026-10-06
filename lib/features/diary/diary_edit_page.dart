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
import '../../core/widgets/location_map_picker.dart';
import '../../core/widgets/location_map_view.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'diary_models.dart';
import 'diary_repository.dart';

/// 日记编辑页（新建 / 编辑）。
class DiaryEditPage extends ConsumerStatefulWidget {
  final DiaryEntry? entry;
  final DiaryTemplate? template;

  const DiaryEditPage({super.key, this.entry, this.template});

  @override
  ConsumerState<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends ConsumerState<DiaryEditPage> {
  /// 大视频阈值：超过则转外链引用
  static const int largeFileThreshold = 50 * 1024 * 1024;

  late final String _entryId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _plainCtrl;
  final List<String> _tags = [];
  final List<MediaAttachment> _media = [];

  bool _tsEnabled = false;
  DateTime? _tsNodeDate;
  bool _tsPinTop = false;

  bool _locEnabled = false;
  String _locName = '';
  double _locLat = 0;
  double _locLng = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _entryId = e?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _plainCtrl = TextEditingController(text: e?.plainText ?? '');
    if (e != null) {
      _tags.addAll(e.tags);
      _media.addAll(e.media);
      _tsEnabled = e.timeStamp.enabled;
      _tsNodeDate = e.timeStamp.nodeDate != null
          ? DateTime.tryParse(e.timeStamp.nodeDate!)
          : null;
      _tsPinTop = e.timeStamp.pinTop;
      _locEnabled = e.locationStamp.enabled;
      _locName = e.locationStamp.name;
      _locLat = e.locationStamp.lat;
      _locLng = e.locationStamp.lng;
    } else if (widget.template != null) {
      // 模板新建：继承模板正文
      _plainCtrl.text = widget.template!.plainText;
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
    final now = DateTime.now();
    final entry = DiaryEntry(
      id: _entryId,
      templateId: widget.template?.id ?? widget.entry?.templateId,
      title: title.isEmpty ? plain.split('\n').first : title,
      plainText: plain,
      createdAt: widget.entry?.createdAt ?? now,
      updatedAt: now,
      timeStamp: TimeStamp(
        enabled: _tsEnabled,
        nodeDate: _tsNodeDate != null ? AppTime.dateOnly(_tsNodeDate!) : null,
        pinTop: _tsPinTop,
      ),
      locationStamp: LocationStamp(
        enabled: _locEnabled,
        lat: _locLat,
        lng: _locLng,
        name: _locName,
      ),
      tags: List.of(_tags),
      media: List.of(_media),
      pinned: _tsPinTop && _tsEnabled,
    );
    await ref.read(diaryListProvider.notifier).saveEntry(entry);
    if (mounted) Navigator.pop(context);
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
    if (picked == null) {
      if (type == MediaType.videoLink) _showLargeVideoDialog();
      return;
    }
    final size = await picked.length();
    // 大视频 / 大文件：转外链引用
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
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(p.join(store.root.path, diaryMediaDir(_entryId)));
    final name = await MediaUtils.copyToDir(picked, dir);
    if (name != null) {
      setState(() {
        _media.add(MediaAttachment(type: type, file: name, size: size));
      });
    }
  }

  Future<void> _showLargeVideoDialog() async {
    final pathCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('大视频外链'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '视频较大，不复制进数据目录，而是记录外部路径引用：',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pathCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '视频文件完整路径',
                hintText: '例如 D:\\Videos\\旅行.mp4 或 /sdcard/Movies/xx.mp4',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '也可直接粘贴一个链接地址。外链文件需自行保管（如存于 U 盘）。',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存外链'),
          ),
        ],
      ),
    );
    if (ok == true && pathCtrl.text.trim().isNotEmpty && mounted) {
      setState(() {
        _media.add(
          MediaAttachment(
            type: MediaType.videoLink,
            external: pathCtrl.text.trim(),
            size: 0,
            note: '大视频外链',
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? '写日记' : '编辑日记'),
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
              decoration: const InputDecoration(hintText: '标题（留空则取正文首行）'),
            ),
          ),
          _buildStampsBar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _plainCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 16, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '正文内容（类似 txt），手机 / 电脑键盘皆友好…',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          _buildAttachmentBar(),
        ],
      ),
    );
  }

  /// 三种「戳」+ 标签：横向滚动快捷条
  Widget _buildStampsBar(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _chip(
            icon: Icons.label_outline,
            label: '标签${_tags.isEmpty ? '' : '(${_tags.length})'}',
            onTap: _showTagDialog,
            active: _tags.isNotEmpty,
          ),
          _chip(
            icon: Icons.schedule_outlined,
            label: _tsEnabled ? '时间戳✓' : '时间戳',
            onTap: _showTimeStampDialog,
            active: _tsEnabled,
          ),
          _chip(
            icon: Icons.location_on_outlined,
            label: _locEnabled ? '地址戳✓' : '地址戳',
            onTap: _showLocationDialog,
            active: _locEnabled,
          ),
          _chip(
            icon: Icons.description_outlined,
            label: '模板',
            onTap: _showTemplateDialog,
            active: widget.template != null,
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

  /// 附件操作栏
  Widget _buildAttachmentBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _attachBtn(
              Icons.photo_outlined,
              '照片',
              () => _addMedia(MediaType.photo),
            ),
            _attachBtn(Icons.mic_none, '录音', _startRecord),
            _attachBtn(
              Icons.videocam_outlined,
              '视频',
              () => _addMedia(MediaType.video),
            ),
            _attachBtn(
              Icons.attach_file,
              '文件',
              () => _addMedia(MediaType.file),
            ),
            if (_media.isNotEmpty)
              _attachBtn(
                Icons.image_outlined,
                '附件(${_media.length})',
                _showMediaList,
              ),
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

  bool _recording = false;
  Future<void> _startRecord() async {
    if (_recording) {
      final path = await MediaUtils.stopRecording();
      _recording = false;
      if (path != null) {
        final f = File(path);
        final store = await ref.read(jsonStoreProvider.future);
        final dir = Directory(p.join(store.root.path, diaryMediaDir(_entryId)));
        // 先确认文件存在并取到长度，再复制，避免留下未登记的孤立文件
        if (await f.exists()) {
          final size = await f.length();
          final name = await MediaUtils.copyToDir(f, dir);
          if (name != null && mounted) {
            setState(
              () => _media.add(
                MediaAttachment(type: MediaType.audio, file: name, size: size),
              ),
            );
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
    final dir = Directory(p.join(store.root.path, diaryMediaDir(_entryId)));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_rec.m4a',
    );
    final started = await MediaUtils.startRecording(path);
    _recording = started;
    if (!started && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
    }
    if (mounted) setState(() {});
  }

  // —— 各设置对话框 ——

  Future<void> _showTagDialog() async {
    // 收集全部已有标签（含各日记），支持模糊搜索复用
    final allTags =
        ref
            .read(diaryListProvider)
            .valueOrNull
            ?.expand((e) => e.tags)
            .toSet() ??
        <String>{};
    final result = await showTagPicker(
      context,
      allTags: allTags.toList(),
      initial: List.of(_tags),
      title: '标签戳',
    );
    if (result != null) {
      setState(
        () => _tags
          ..clear()
          ..addAll(result),
      );
    }
  }

  void _showTimeStampDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('时间戳 · 历史纪念'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('启用时间戳'),
                value: _tsEnabled,
                onChanged: (v) => setState(() => _tsEnabled = v),
              ),
              ListTile(
                title: const Text('纪念节点日期'),
                subtitle: Text(
                  _tsNodeDate == null
                      ? '未设置（建议：半年 / 一年）'
                      : AppTime.dateOnly(_tsNodeDate!),
                ),
                onTap: _tsEnabled
                    ? () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _tsNodeDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _tsNodeDate = d);
                      }
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2, bottom: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final quick in const [
                      (1, '一个月后'),
                      (6, '半年后'),
                      (12, '一年后'),
                    ])
                      ActionChip(
                        label: Text(
                          quick.$2,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _tsEnabled
                            ? () {
                                final now = DateTime.now();
                                setState(
                                  () => _tsNodeDate = DateTime(
                                    now.year,
                                    now.month + quick.$1,
                                    now.day,
                                  ),
                                );
                              }
                            : null,
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('节点到达后置顶'),
                value: _tsPinTop,
                onChanged: _tsEnabled
                    ? (v) => setState(() => _tsPinTop = v)
                    : null,
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
      ),
    );
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('地址戳 · 位置标记'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('启用地址戳'),
                value: _locEnabled,
                onChanged: (v) => setState(() => _locEnabled = v),
              ),
              TextFormField(
                enabled: _locEnabled,
                decoration: const InputDecoration(labelText: '地点名称（如：家）'),
                onChanged: (v) => _locName = v,
                initialValue: _locName,
              ),
              const SizedBox(height: 8),
              // 内嵌可视化地图：直接点击地图选点，所见即所得
              if (_locEnabled)
                LocationMapView(
                  center: LatLng(
                    _locLat == 0 ? 39.9042 : _locLat,
                    _locLng == 0 ? 116.4074 : _locLng,
                  ),
                  interactive: true,
                  height: 180,
                  onChanged: (p) => setState(() {
                    _locLat = p.latitude;
                    _locLng = p.longitude;
                    if (_locName.isEmpty) _locName = '地图标记点';
                  }),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: _locEnabled,
                      decoration: const InputDecoration(labelText: '纬度'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _locLat = double.tryParse(v) ?? 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      enabled: _locEnabled,
                      decoration: const InputDecoration(labelText: '经度'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _locLng = double.tryParse(v) ?? 0,
                    ),
                  ),
                ],
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
              const SizedBox(height: 4),
              const Text(
                '离线瓦片存放于 AllOneData/map_tiles 目录时，可完全离线使用',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
      ),
    );
  }

  Future<void> _showTemplateDialog() async {
    final t = await showDialog<DiaryTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择日记模板'),
        children: [
          for (final t
              in (ref.read(diaryTemplateListProvider).valueOrNull ?? []))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t.name.isEmpty ? '未命名模板' : t.name),
            ),
          if ((ref.read(diaryTemplateListProvider).valueOrNull ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无模板，可在「日记-模板」中创建'),
            ),
        ],
      ),
    );
    if (t == null || !mounted) return;
    setState(() {
      // 模板套用：填充正文
      _plainCtrl.text = t.plainText;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已套用模板「${t.name.isEmpty ? '未命名模板' : t.name}」')),
      );
    }
  }

  void _showMediaList() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('附件列表', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final m in _media)
            ListTile(
              leading: Icon(_mediaIcon(m.type)),
              title: Text(m.file ?? m.external ?? '外链'),
              subtitle: Text(
                m.note ?? '${(m.size / 1024).toStringAsFixed(1)} KB',
              ),
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
