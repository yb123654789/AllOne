import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/utils/media_utils.dart';
import '../../core/widgets/attachment_view.dart';
import 'quest_models.dart';
import 'quest_repository.dart';

/// 新建 / 编辑任务的基础字段。
///
/// 里程碑、行动项、投入记录都在**详情页**里管，这里只管「这个任务是什么」。
/// 附件也在这里：拆不出文字说明的时候，贴一张参考图 / 录一段语音最省事，
/// 子项目同样支持。
class QuestEditPage extends ConsumerStatefulWidget {
  final Quest? quest;

  /// 新建子项目时传入父任务 id（新建后挂在它下面）
  final String? parentId;

  const QuestEditPage({super.key, this.quest, this.parentId});

  @override
  ConsumerState<QuestEditPage> createState() => _QuestEditPageState();
}

class _QuestEditPageState extends ConsumerState<QuestEditPage> {
  /// 大文件阈值：超过则转外链引用（与日记 / 待办一致）
  static const int largeFileThreshold = 50 * 1024 * 1024;

  late final String _questId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _visionCtrl;
  late final TextEditingController _categoryCtrl;
  late QuestStatus _status;
  late String _startDate;
  late String _targetDate;
  late String _time;
  late int _manualProgress;
  late bool _pinned;
  final List<MediaAttachment> _media = [];
  bool _recording = false;

  bool get _isNew => widget.quest == null;

  @override
  void initState() {
    super.initState();
    final q = widget.quest;
    // 先定好 id：附件要在「保存前」就能落盘到 quest/quests/<id>/media/
    _questId = q?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: q?.title ?? '');
    _visionCtrl = TextEditingController(text: q?.vision ?? '');
    _categoryCtrl = TextEditingController(text: q?.category ?? '未分类');
    _status = q?.status ?? QuestStatus.active;
    _startDate = q?.startDate ?? AppTime.dateOnly(DateTime.now());
    _targetDate = q?.targetDate ?? '';
    _time = q?.time ?? '';
    _manualProgress = q?.manualProgress ?? 0;
    _pinned = q?.pinned ?? false;
    _media.addAll(q?.media ?? const <MediaAttachment>[]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _visionCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMilestones = (widget.quest?.milestones.isNotEmpty) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建任务' : '编辑任务'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: _isNew,
            decoration: const InputDecoration(
              labelText: '任务名称',
              hintText: '如：写完那本书 / 学会钢琴 / 把身体练回来',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _visionCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '描述 / 目标（想做成什么样、为什么做）',
              hintText: '长期任务最怕忘了当初为什么开始，这里写清楚；'
                  '也可以只写一句「这一步要交付什么」',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          _attachmentsSection(),
          const SizedBox(height: 18),
          _label('领域分类'),
          const SizedBox(height: 6),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '工作 / 学习 / 健康 …',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in QuestLogic.categoryOptions)
                ActionChip(
                  label: Text(c),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _categoryCtrl.text = c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _label('状态'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final s in QuestStatus.values)
                ChoiceChip(
                  label: Text(_statusLabel(s)),
                  selected: _status == s,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _label('时间跨度'),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('起始日期'),
            subtitle: Text(_startDate.isEmpty ? '未设置' : _startDate),
            trailing: const Icon(Icons.edit_calendar_outlined, size: 18),
            onTap: () => _pickDate(
              initial: _startDate,
              onPicked: (d) => setState(() => _startDate = d),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: const Text('期望完成'),
            subtitle: Text(
              _targetDate.isEmpty ? '长期 · 无期限' : _targetDate,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_targetDate.isNotEmpty)
                  IconButton(
                    tooltip: '改为长期（无期限）',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _targetDate = ''),
                  ),
                const Icon(Icons.edit_calendar_outlined, size: 18),
              ],
            ),
            onTap: () => _pickDate(
              initial: _targetDate.isEmpty ? _startDate : _targetDate,
              onPicked: (d) => setState(() => _targetDate = d),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('时间（可选）'),
            subtitle: Text(_time.isEmpty ? '不指定具体时间' : _time),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_time.isNotEmpty)
                  IconButton(
                    tooltip: '清除时间',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _time = ''),
                  ),
                const Icon(Icons.access_time, size: 18),
              ],
            ),
            onTap: () async {
              final parts = _time.split(':');
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9,
                  minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                ),
              );
              if (t == null) return;
              setState(() {
                _time =
                    '${t.hour.toString().padLeft(2, '0')}'
                    ':${t.minute.toString().padLeft(2, '0')}';
              });
            },
          ),
          const SizedBox(height: 6),
          const Text(
            '配「期望完成」用：填了时间，任务就会出现在日历「当天」日程表的时间轴上；'
            '不填则只在「无精确时分」区里等你安排。',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          _label('进度'),
          const SizedBox(height: 2),
          if (hasMilestones)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '这个任务已经有里程碑，进度由里程碑自动计算（勾选完成即可推进）。',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _manualProgress.toDouble().clamp(0, 100),
                    max: 100,
                    divisions: 20,
                    label: '$_manualProgress%',
                    onChanged: (v) =>
                        setState(() => _manualProgress = v.round()),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$_manualProgress%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Text(
              '还没有里程碑时，进度用手动百分比表示（长期事情的进度往往是主观的）。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            title: const Text('钉住（当前重心）'),
            subtitle: const Text(
              '钉住的任务排在总览最前面，方便每天先看它',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Text(
    s,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );

  // ── 附件（照片 / 录音 / 视频 / 文件） ─────────────────────────────────────

  /// 添加附件后的即时反馈（与日记 / 待办 / 笔记一致）
  void _toastAdded(MediaType type) {
    if (!mounted) return;
    showAttachmentAddedToast(context, type, _media.length);
  }

  Widget _attachmentsSection() {
    final root = ref.read(jsonStoreProvider).valueOrNull?.root.path;
    final mediaDir = root == null ? null : p.join(root, questMediaDir(_questId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('附件（照片 / 录音 / 视频 / 文件）'),
        const SizedBox(height: 6),
        Row(
          children: [
            _attachBtn(
              Icons.photo_outlined,
              '照片',
              () => _addMedia(MediaType.photo),
            ),
            _attachBtn(
              _recording ? Icons.stop_circle_outlined : Icons.mic_none,
              _recording ? '停止' : '录音',
              _toggleRecord,
            ),
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
          ],
        ),
        if (_media.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '还没有附件；参考图、截图、语音备忘都可以放这里',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          )
        else
          MediaThumbStrip(
            media: _media,
            mediaDir: mediaDir,
            padding: EdgeInsets.zero,
            onRemove: (m) => setState(() => _media.remove(m)),
          ),
      ],
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
      ),
    );
  }

  Future<void> _addMedia(MediaType type) async {
    final File? picked;
    switch (type) {
      case MediaType.photo:
        picked = await MediaUtils.pickImage();
      case MediaType.audio:
      case MediaType.video:
      case MediaType.file:
        picked = await MediaUtils.pickAnyFile();
      case MediaType.videoLink:
        picked = null;
    }
    if (picked == null) return;
    final size = await picked.length();
    // 大文件：不复制进数据目录，只记外部路径引用（与日记一致）
    if (size > largeFileThreshold) {
      if (!mounted) return;
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
    final dir = Directory(p.join(store.root.path, questMediaDir(_questId)));
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
          final dir = Directory(p.join(store.root.path, questMediaDir(_questId)));
          final name = await MediaUtils.copyToDir(f, dir);
          if (name != null && mounted) {
            setState(() {
              _media.add(
                MediaAttachment(type: MediaType.audio, file: name, size: size),
              );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(p.join(store.root.path, questMediaDir(_questId)));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_rec.m4a',
    );
    final started = await MediaUtils.startRecording(path);
    _recording = started;
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音启动失败，请检查麦克风权限')),
      );
    }
    if (mounted) setState(() {});
  }

  String _statusLabel(QuestStatus s) {
    switch (s) {
      case QuestStatus.active:
        return '进行中';
      case QuestStatus.paused:
        return '暂停';
      case QuestStatus.done:
        return '已完成';
      case QuestStatus.dropped:
        return '已放弃';
    }
  }

  Future<void> _pickDate({
    required String initial,
    required void Function(String) onPicked,
  }) async {
    final now = DateTime.now();
    final init = DateTime.tryParse(initial) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 50),
      helpText: '选择日期',
    );
    if (picked == null) return;
    onPicked(AppTime.dateOnly(picked));
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('给任务起个名字吧')),
      );
      return;
    }
    final now = DateTime.now();
    final notifier = ref.read(questListProvider.notifier);
    // 完成约束：编辑页也不能绕过「子项目全部了结才能完成」。
    // 之前这里直接 mutate 写库，能把还有未了结子项目的任务强行标成已完成，
    // 与列表菜单 / 详情菜单的规则不一致。
    if (!_isNew &&
        _status == QuestStatus.done &&
        widget.quest!.status != QuestStatus.done) {
      final all = ref.read(questListProvider).valueOrNull ?? const <Quest>[];
      final blockers = QuestLogic.blockersForDone(all, widget.quest!.id);
      if (blockers.isNotEmpty) {
        final names = blockers
            .take(3)
            .map((b) => '「${b.title.isEmpty ? '未命名' : b.title}」')
            .join('、');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '还有 ${blockers.length} 个子项目没了结（$names'
              '${blockers.length > 3 ? ' 等' : ''}），要先把它们设为已完成或已放弃',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    if (_isNew) {
      await notifier.save(
        Quest(
          id: _questId,
          title: title,
          vision: _visionCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? '未分类'
              : _categoryCtrl.text.trim(),
          status: _status,
          startDate: _startDate,
          targetDate: _targetDate,
          time: _time,
          manualProgress: _manualProgress,
          pinned: _pinned,
          pinnedAt: _pinned ? now.toIso8601String() : '',
          media: List.of(_media),
          parentId: widget.parentId ?? '',
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      final old = widget.quest!;
      await notifier.mutate(
        old.id,
        (q) => q.copyWith(
          title: title,
          vision: _visionCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? '未分类'
              : _categoryCtrl.text.trim(),
          status: _status,
          startDate: _startDate,
          targetDate: _targetDate,
          clearTargetDate: _targetDate.isEmpty,
          time: _time,
          clearTime: _time.isEmpty,
          manualProgress: _manualProgress,
          pinned: _pinned,
          pinnedAt: _pinned
              ? (q.pinnedAt.isEmpty ? now.toIso8601String() : q.pinnedAt)
              : '',
          clearPinnedAt: !_pinned,
          media: List.of(_media),
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}
