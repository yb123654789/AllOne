import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
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
  late final String _id;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _targetCtrl;
  HabitType _type = HabitType.count;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _id = h?.id ?? AppPaths.newId();
    _titleCtrl = TextEditingController(text: h?.title ?? '');
    _categoryCtrl = TextEditingController(text: h?.category ?? '通用');
    _descCtrl = TextEditingController(text: h?.description ?? '');
    _targetCtrl = TextEditingController(text: (h?.target.value ?? 30).toString());
    _type = h?.target.type ?? HabitType.count;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final habit = Habit(
      id: _id,
      title: _titleCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? '通用' : _categoryCtrl.text.trim(),
      target: HabitTarget(
        type: _type,
        value: int.tryParse(_targetCtrl.text.trim()) ?? 30,
      ),
      description: _descCtrl.text.trim(),
      createdAt: widget.habit?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(habitListProvider.notifier).saveHabit(habit);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? '新建习惯' : '编辑习惯'),
        actions: [
          IconButton(onPressed: _save, tooltip: '保存', icon: const Icon(Icons.save_outlined)),
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
                    ButtonSegment(value: HabitType.duration, label: Text('按天数')),
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
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '习惯描述（内容 / 备注）'),
          ),
          const SizedBox(height: 16),
          Text(
            '打卡说明：创建后在列表页点击习惯卡片即可完成当日打卡；按次数习惯每日可多次打卡。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
