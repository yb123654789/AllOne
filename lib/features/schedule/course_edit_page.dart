import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'course_ocr.dart';
import 'course_ocr_page.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 课程编辑页。
class CourseEditPage extends ConsumerStatefulWidget {
  final Course? course;

  const CourseEditPage({super.key, this.course});

  @override
  ConsumerState<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends ConsumerState<CourseEditPage> {
  late final String _id;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;
  late final TextEditingController _roomCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late final TextEditingController _weeksCtrl;
  late final TextEditingController _notesCtrl;
  int _weekday = 1;
  String _termId = '';

  static const _weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _id = c?.id ?? AppPaths.newId();
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _teacherCtrl = TextEditingController(text: c?.teacher ?? '');
    _roomCtrl = TextEditingController(text: c?.classroom ?? '');
    _startCtrl = TextEditingController(text: c?.startTime ?? '08:00');
    _endCtrl = TextEditingController(text: c?.endTime ?? '09:40');
    _weeksCtrl = TextEditingController(text: c?.weeks.join(',') ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    _weekday = c?.weekday ?? 1;
    _termId = c?.termId ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _roomCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _weeksCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final course = Course(
      id: _id,
      termId: _termId,
      name: _nameCtrl.text.trim(),
      teacher: _teacherCtrl.text.trim(),
      classroom: _roomCtrl.text.trim(),
      weekday: _weekday,
      startTime: _startCtrl.text.trim(),
      endTime: _endCtrl.text.trim(),
      weeks: _weeksCtrl.text
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList(),
      notes: _notesCtrl.text.trim(),
    );
    await ref.read(courseListProvider.notifier).saveCourse(course);
    if (mounted) Navigator.pop(context);
  }

  /// 从照片识别课程信息，结果回填到表单（仅 Android / iOS）。
  Future<void> _pickFromImage() async {
    final result = await Navigator.push<CourseOcrResult>(
      context,
      MaterialPageRoute(builder: (_) => const CourseOcrPage()),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.name.isNotEmpty) _nameCtrl.text = result.name;
      if (result.teacher.isNotEmpty) _teacherCtrl.text = result.teacher;
      if (result.classroom.isNotEmpty) _roomCtrl.text = result.classroom;
      if (result.weekday != null) _weekday = result.weekday!;
      if (result.startTime.isNotEmpty) _startCtrl.text = result.startTime;
      if (result.endTime.isNotEmpty) _endCtrl.text = result.endTime;
      if (result.weeks.isNotEmpty) _weeksCtrl.text = result.weeks;
      // 课程说明填入识别原文，供参考
      if (result.rawText.isNotEmpty) _notesCtrl.text = result.rawText;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已填入识别结果，请核对后再保存')),
      );
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final parts = ctrl.text.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (t != null) {
      ctrl.text =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(termListProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
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
          DropdownButtonFormField<String>(
            initialValue: _termId.isEmpty && terms.isNotEmpty
                ? terms.first.id
                : _termId,
            decoration: const InputDecoration(labelText: '所属学期'),
            items: [
              for (final t in terms)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name.isEmpty ? '未命名学期' : t.name),
                ),
            ],
            onChanged: (v) => _termId = v ?? '',
          ),
          if (isOcrSupported()) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFromImage,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('📷 从照片识别课程信息'),
            ),
            const SizedBox(height: 4),
            Text(
              '拍照 / 选图自动识别课程名、教室、时间等（本地识别，仅安卓 / iOS）',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '课程名称 *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(labelText: '任课教师'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _roomCtrl,
            decoration: const InputDecoration(labelText: '上课地点 *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _weekday,
            decoration: const InputDecoration(labelText: '星期'),
            items: [
              for (var i = 0; i < 7; i++)
                DropdownMenuItem(value: i + 1, child: Text(_weekNames[i])),
            ],
            onChanged: (v) => setState(() => _weekday = v ?? 1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtrl,
                  decoration: const InputDecoration(labelText: '开始时间'),
                  onTap: () => _pickTime(_startCtrl),
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _endCtrl,
                  decoration: const InputDecoration(labelText: '结束时间'),
                  onTap: () => _pickTime(_endCtrl),
                  readOnly: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weeksCtrl,
            decoration: const InputDecoration(
              labelText: '上课周次（逗号分隔，如 1,2,3,4,5）',
              hintText: '留空表示每周',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '课程说明（课程要求 / 相关资料）'),
          ),
          const SizedBox(height: 16),
          Text(
            '（课程表每半年一个学期，可在课程表页管理学期）',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
