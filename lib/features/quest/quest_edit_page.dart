import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'quest_models.dart';
import 'quest_repository.dart';

/// 新建 / 编辑任务的基础字段。
///
/// 里程碑、行动项、投入记录都在**详情页**里管，这里只管「这个任务是什么」。
class QuestEditPage extends ConsumerStatefulWidget {
  final Quest? quest;

  const QuestEditPage({super.key, this.quest});

  @override
  ConsumerState<QuestEditPage> createState() => _QuestEditPageState();
}

class _QuestEditPageState extends ConsumerState<QuestEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _visionCtrl;
  late final TextEditingController _categoryCtrl;
  late QuestStatus _status;
  late String _startDate;
  late String _targetDate;
  late String _time;
  late int _manualProgress;
  late bool _pinned;

  bool get _isNew => widget.quest == null;

  @override
  void initState() {
    super.initState();
    final q = widget.quest;
    _titleCtrl = TextEditingController(text: q?.title ?? '');
    _visionCtrl = TextEditingController(text: q?.vision ?? '');
    _categoryCtrl = TextEditingController(text: q?.category ?? '未分类');
    _status = q?.status ?? QuestStatus.active;
    _startDate = q?.startDate ?? AppTime.dateOnly(DateTime.now());
    _targetDate = q?.targetDate ?? '';
    _time = q?.time ?? '';
    _manualProgress = q?.manualProgress ?? 0;
    _pinned = q?.pinned ?? false;
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
              labelText: '目标 / 愿景（为什么做、想达成什么）',
              hintText: '长期任务最怕忘了当初为什么开始，这里写清楚',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
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
    if (_isNew) {
      await notifier.save(
        Quest(
          id: AppPaths.newId(),
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
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}
