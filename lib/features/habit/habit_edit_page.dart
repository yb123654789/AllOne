import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/utils/media_utils.dart';
import '../../core/widgets/tag_dialogs.dart';
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
  late final TextEditingController _dailyTargetCtrl;
  late final TextEditingController _persistenceCtrl;
  late final TextEditingController _tagInput;

  // 频率
  HabitFrequency _frequency = HabitFrequency.daily;
  final Set<int> _weekdays = {}; // 1-7
  late final TextEditingController _intervalDaysCtrl;
  late final TextEditingController _weeklyTimesCtrl;

  // 当天目标
  HabitDailyTarget _dailyTarget = HabitDailyTarget.once;

  // 坚持周期
  HabitPersistence _persistence = HabitPersistence.unlimited;

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
    _dailyTargetCtrl = TextEditingController(
      text: (h?.dailyTargetValue ?? 1).toString(),
    );
    _persistenceCtrl = TextEditingController(
      text: (h?.persistenceValue ?? 21).toString(),
    );
    _intervalDaysCtrl = TextEditingController(
      text: (h?.intervalDays ?? 3).toString(),
    );
    _weeklyTimesCtrl = TextEditingController(
      text: (h?.weeklyTimes ?? 3).toString(),
    );
    _tagInput = TextEditingController();

    _frequency = h?.frequency ?? HabitFrequency.daily;
    _weekdays.addAll(h?.weekdays ?? const []);
    _dailyTarget = h?.dailyTarget ?? HabitDailyTarget.once;
    _persistence = h?.persistence ?? HabitPersistence.unlimited;
    if (h != null) {
      _media.addAll(h.media);
      _tags.addAll(h.tags);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _descCtrl.dispose();
    _dailyTargetCtrl.dispose();
    _persistenceCtrl.dispose();
    _intervalDaysCtrl.dispose();
    _weeklyTimesCtrl.dispose();
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
      frequency: _frequency,
      weekdays: _weekdays.toList()..sort(),
      intervalDays: int.tryParse(_intervalDaysCtrl.text.trim()) ?? 1,
      weeklyTimes: int.tryParse(_weeklyTimesCtrl.text.trim()) ?? 1,
      dailyTarget: _dailyTarget,
      dailyTargetValue: int.tryParse(_dailyTargetCtrl.text.trim()) ?? 1,
      persistence: _persistence,
      persistenceValue: int.tryParse(_persistenceCtrl.text.trim()) ?? 0,
      description: _descCtrl.text.trim(),
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
        final store = await ref.read(jsonStoreProvider.future);
        final dir = Directory(p.join(store.root.path, habitMediaDir(_id)));
        // 先确认文件存在并取到长度，再复制，避免留下未登记的孤立文件
        if (await f.exists()) {
          final len = await f.length();
          final name = await MediaUtils.copyToDir(f, dir);
          if (name != null && mounted) {
            setState(
              () => _media.add(
                MediaAttachment(type: MediaType.audio, file: name, size: len),
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
            .showSnackBar(const SnackBar(content: Text('需要麦克风权限')));
      }
      return;
    }
    final store = await ref.read(jsonStoreProvider.future);
    final dir = Directory(p.join(store.root.path, habitMediaDir(_id)));
    if (!await dir.exists()) await dir.create(recursive: true);
    final started = await MediaUtils.startRecording(
      p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_rec.m4a'),
    );
    _recording = started;
    if (!started && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
    }
    if (mounted) setState(() {});
  }

  void _addTag() {
    final s = _tagInput.text.trim();
    if (s.isNotEmpty && !_tags.contains(s)) {
      setState(() => _tags.add(s));
      _tagInput.clear();
    }
  }

  /// 从已有标签中检索复用（支持模糊搜索）
  Future<void> _showTagPicker() async {
    final allTags =
        ref
            .read(habitListProvider)
            .valueOrNull
            ?.expand((h) => h.tags)
            .toSet() ??
        <String>{};
    final result = await showTagPicker(
      context,
      allTags: allTags.toList(),
      initial: List.of(_tags),
    );
    if (result != null) {
      setState(
        () => _tags
          ..clear()
          ..addAll(result),
      );
    }
  }

  /// —— 频率配置区 ——
  Widget _frequencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('打卡频率'),
        const SizedBox(height: 6),
        SegmentedButton<HabitFrequency>(
          segments: const [
            ButtonSegment(value: HabitFrequency.daily, label: Text('每天')),
            ButtonSegment(value: HabitFrequency.weekly, label: Text('每周几天')),
            ButtonSegment(value: HabitFrequency.interval, label: Text('每 N 天')),
            ButtonSegment(
              value: HabitFrequency.weeklyTimes,
              label: Text('每周 N 次'),
            ),
          ],
          selected: {_frequency},
          onSelectionChanged: (s) => setState(() => _frequency = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        if (_frequency == HabitFrequency.weekly)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_weekdayName(d)),
                  selected: _weekdays.contains(d),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _weekdays.add(d);
                    } else {
                      _weekdays.remove(d);
                    }
                  }),
                ),
            ],
          ),
        if (_frequency == HabitFrequency.interval)
          TextField(
            controller: _intervalDaysCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每隔多少天打卡一次（如：3）'),
          ),
        if (_frequency == HabitFrequency.weeklyTimes)
          TextField(
            controller: _weeklyTimesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每周累计打卡多少次（如：3）'),
          ),
        if (_frequency == HabitFrequency.daily)
          const Text(
            '每天都可以打卡。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
      ],
    );
  }

  /// —— 当天目标配置区 ——
  Widget _dailyTargetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('当天目标（一天完成多少算完成当天）'),
        const SizedBox(height: 6),
        SegmentedButton<HabitDailyTarget>(
          segments: const [
            ButtonSegment(value: HabitDailyTarget.once, label: Text('一次即完成')),
            ButtonSegment(value: HabitDailyTarget.quantity, label: Text('定量')),
            ButtonSegment(value: HabitDailyTarget.minutes, label: Text('时长')),
          ],
          selected: {_dailyTarget},
          onSelectionChanged: (s) => setState(() => _dailyTarget = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        if (_dailyTarget == HabitDailyTarget.quantity)
          TextField(
            controller: _dailyTargetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每天需累计多少次 / 多少量（如：8）'),
          ),
        if (_dailyTarget == HabitDailyTarget.minutes)
          TextField(
            controller: _dailyTargetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每天需累计多少分钟（如：30）'),
          ),
        if (_dailyTarget == HabitDailyTarget.once)
          const Text(
            '当天打一次卡即算完成。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
      ],
    );
  }

  /// —— 坚持周期配置区 ——
  Widget _persistenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('坚持周期（习惯存在的窗口）'),
        const SizedBox(height: 6),
        SegmentedButton<HabitPersistence>(
          segments: const [
            ButtonSegment(value: HabitPersistence.unlimited, label: Text('不限')),
            ButtonSegment(value: HabitPersistence.days, label: Text('坚持 N 天')),
            ButtonSegment(value: HabitPersistence.times, label: Text('累计 N 次')),
            ButtonSegment(value: HabitPersistence.cycles, label: Text('循环周期')),
          ],
          selected: {_persistence},
          onSelectionChanged: (s) => setState(() => _persistence = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        if (_persistence == HabitPersistence.days)
          TextField(
            controller: _persistenceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '坚持多少天（如：21）'),
          ),
        if (_persistence == HabitPersistence.times)
          TextField(
            controller: _persistenceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '累计打卡多少次（如：100）'),
          ),
        if (_persistence == HabitPersistence.cycles)
          TextField(
            controller: _persistenceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '每轮多少天（如：21），完成后自动开始下一轮',
            ),
          ),
        if (_persistence == HabitPersistence.unlimited)
          const Text(
            '不设结束，一直存在。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
  );

  String _weekdayName(int d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return (d >= 1 && d <= 7) ? names[d - 1] : '?';
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
          _frequencySection(),
          const SizedBox(height: 16),
          _dailyTargetSection(),
          const SizedBox(height: 16),
          _persistenceSection(),
          const SizedBox(height: 16),
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
            crossAxisAlignment: WrapCrossAlignment.center,
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
              ActionChip(
                avatar: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppTheme.primary,
                ),
                label: const Text('从已有标签选择'),
                onPressed: _showTagPicker,
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
            '打卡说明：在列表页点击习惯卡片上的「打卡」按钮，可手动输入本次的数量 / 分钟数；'
            '达标后当天即视为完成。',
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
