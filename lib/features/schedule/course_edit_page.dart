import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'course_ocr.dart';
import 'course_ocr_page.dart';
import 'schedule_logic.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 课程编辑页（新增 / 修改）。
///
/// 核心变化：**不再手填时间和周次数字**
/// - 时间：只选「第几节」（下拉，支持连堂选到第几节），时间由作息表决定；
/// - 周次：**逐周点按钮**（还有全选 / 单周 / 双周快捷）；
/// - 一门课可以加**多个时段**（同课不同天、不同教室各一条）。
class CourseEditPage extends ConsumerStatefulWidget {
  final Course? course;

  const CourseEditPage({super.key, this.course});

  @override
  ConsumerState<CourseEditPage> createState() => _CourseEditPageState();
}

/// 编辑中的时段草稿（可变，便于表单里直接改）
class _SessionDraft {
  int weekday;
  int startSection;
  int endSection;

  /// 教室输入框的控制器**必须由草稿持有**：
  /// 不能在 build 里 new，否则每次重建都会丢光标和正在输入的内容。
  final TextEditingController classroomCtrl;
  Set<int> weeks;
  String startTime;
  String endTime;

  _SessionDraft({
    this.weekday = 1,
    this.startSection = 1,
    this.endSection = 1,
    String classroom = '',
    Set<int>? weeks,
    this.startTime = '',
    this.endTime = '',
  }) : classroomCtrl = TextEditingController(text: classroom),
       weeks = weeks ?? <int>{};

  factory _SessionDraft.from(CourseSession s) => _SessionDraft(
    weekday: s.weekday,
    startSection: s.startSection,
    endSection: s.endSection <= 0 ? s.startSection : s.endSection,
    classroom: s.classroom,
    weeks: {...s.weeks},
    startTime: s.startTime,
    endTime: s.endTime,
  );

  String get classroom => classroomCtrl.text;
}

class _CourseEditPageState extends ConsumerState<CourseEditPage> {
  late final String _id;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;
  late final TextEditingController _notesCtrl;
  late List<_SessionDraft> _sessions;
  String _termId = '';
  String _color = '';

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _id = c?.id ?? AppPaths.newId();
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _teacherCtrl = TextEditingController(text: c?.teacher ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    _termId = c?.termId ?? '';
    _color = c?.color ?? '';
    _sessions = c == null || c.sessions.isEmpty
        ? [_SessionDraft()]
        : c.sessions.map(_SessionDraft.from).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// 周次按钮的数量：优先用学期总周数，否则 20
  int get _weekCount {
    final terms = ref.read(termListProvider).valueOrNull ?? const <Term>[];
    Term? term;
    if (_termId.isEmpty) {
      term = ScheduleLogic.currentTerm(terms, DateTime.now());
    } else {
      for (final t in terms) {
        if (t.id == _termId) term = t;
      }
    }
    final total = term == null ? 0 : ScheduleLogic.totalWeeks(term);
    return total > 0 ? total.clamp(1, 30) : 20;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('给课程起个名字吧')),
      );
      return;
    }
    final sessions = [
      for (final d in _sessions)
        CourseSession(
          weekday: d.weekday,
          startSection: d.startSection,
          endSection: d.endSection,
          weeks: (d.weeks.toList()..sort()),
          classroom: d.classroom.trim(),
          // 明确选了节次 → 清掉旧的自定义时间（由作息表决定时间）
          startTime: d.startSection > 0 ? '' : d.startTime,
          endTime: d.startSection > 0 ? '' : d.endTime,
        ),
    ];
    await ref
        .read(courseListProvider.notifier)
        .saveCourse(
          Course(
            id: _id,
            termId: _termId,
            name: name,
            teacher: _teacherCtrl.text.trim(),
            color: _color,
            sessions: sessions,
            notes: _notesCtrl.text.trim(),
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(termListProvider).valueOrNull ?? const <Term>[];
    final sections =
        ref.watch(sectionListProvider).valueOrNull ?? kDefaultSections;
    if (_termId.isEmpty && terms.isNotEmpty) {
      _termId = terms.first.id;
    }

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
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('加时段'),
        onPressed: () => setState(
          () => _sessions = [
            ..._sessions,
            _SessionDraft(startSection: 1, endSection: 1),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (terms.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _termId.isEmpty ? terms.first.id : _termId,
              decoration: const InputDecoration(
                labelText: '所属学期',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in terms)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(t.name.isEmpty ? '未命名学期' : t.name),
                  ),
              ],
              onChanged: (v) => setState(() => _termId = v ?? ''),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '课程名称 *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(
              labelText: '任课教师',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _label('课程颜色'),
          const SizedBox(height: 6),
          _colorPicker(),
          const SizedBox(height: 18),
          Row(
            children: [
              _label('上课时段（可多个）'),
              const Spacer(),
              if (isOcrSupported())
                TextButton.icon(
                  onPressed: _pickFromImage,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('从照片识别'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _sessions.length; i++) _sessionCard(i, sections),
          const SizedBox(height: 8),
          Text(
            '提示：同一门课一周上两次（不同天 / 不同教室）就加两个时段，'
            '统计里仍然只是一门课。',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '课程说明（课程要求 / 相关资料）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
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

  Widget _colorPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('自动'),
          selected: _color.isEmpty,
          onSelected: (_) => setState(() => _color = ''),
        ),
        for (final hex in ScheduleLogic.palette)
          GestureDetector(
            onTap: () => setState(() => _color = hex),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: ScheduleLogic.colorOf(
                  Course(id: 'x', name: '', color: hex),
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _color == hex
                      ? AppTheme.textPrimary
                      : AppTheme.divider,
                  width: _color == hex ? 2.5 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 一个时段的编辑卡片
  Widget _sessionCard(int i, List<SectionTime> sections) {
    final d = _sessions[i];
    final weekCount = _weekCount;
    final indices = sections.map((s) => s.index).toList();
    final maxIndex = indices.isEmpty ? 1 : indices.last;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '时段 ${i + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_sessions.length > 1)
                  IconButton(
                    tooltip: '删除这个时段',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      final list = [..._sessions]..removeAt(i);
                      _sessions = list;
                    }),
                  ),
              ],
            ),
            // 星期
            Wrap(
              spacing: 6,
              children: [
                for (var w = 1; w <= 7; w++)
                  ChoiceChip(
                    label: Text(_weekNames[w - 1]),
                    selected: d.weekday == w,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => d.weekday = w),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // 节次范围（下拉选择，不写数字）
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: d.startSection,
                    decoration: const InputDecoration(
                      labelText: '从第几节',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('不指定（按原时间）'),
                      ),
                      for (final s in sections)
                        DropdownMenuItem(
                          value: s.index,
                          child: Text('第 ${s.index} 节 ${s.start}'),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      d.startSection = v ?? 0;
                      if (d.endSection < d.startSection) {
                        d.endSection = d.startSection;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: d.endSection <= 0 ? d.startSection : d.endSection,
                    decoration: const InputDecoration(
                      labelText: '到第几节（连堂）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in sections)
                        if (s.index >= (d.startSection <= 0 ? 1 : d.startSection))
                          DropdownMenuItem(
                            value: s.index,
                            child: Text('第 ${s.index} 节 ${s.end}'),
                          ),
                    ],
                    onChanged: (v) => setState(() {
                      d.endSection = v ?? d.startSection;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: d.classroomCtrl,
              decoration: const InputDecoration(
                labelText: '上课地点（这个时段的教室）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '上课周次',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  d.weeks.isEmpty ? '每周都上' : '已选 ${d.weeks.length} 周',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(
                    () => d.weeks = {for (var w = 1; w <= weekCount; w++) w},
                  ),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(() => d.weeks = <int>{}),
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => d.weeks = {
                      for (var w = 1; w <= weekCount; w++)
                        if (w.isOdd) w,
                    },
                  ),
                  child: const Text('单周'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => d.weeks = {
                      for (var w = 1; w <= weekCount; w++)
                        if (w.isEven) w,
                    },
                  ),
                  child: const Text('双周'),
                ),
              ],
            ),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var w = 1; w <= weekCount; w++)
                  FilterChip(
                    label: Text('$w'),
                    selected: d.weeks.contains(w),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: const TextStyle(fontSize: 11),
                    onSelected: (on) => setState(() {
                      if (on) {
                        d.weeks.add(w);
                      } else {
                        d.weeks.remove(w);
                      }
                    }),
                  ),
              ],
            ),
            if (d.startSection <= 0 && (d.startTime.isNotEmpty || d.endTime.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '这是旧数据：时间 ${d.startTime}-${d.endTime}（选一下节次就会改用作息表时间）',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            if (d.startSection > 0 && d.startSection > maxIndex)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '这节的序号超出了当前作息表，去「作息表」补一节或改小一点',
                  style: TextStyle(fontSize: 11, color: AppTheme.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 从照片识别课程信息，回填到表单（仅 Android / iOS）
  Future<void> _pickFromImage() async {
    final result = await Navigator.push<CourseOcrResult>(
      context,
      MaterialPageRoute(builder: (_) => const CourseOcrPage()),
    );
    if (result == null || !mounted) return;
    final sections =
        ref.read(sectionListProvider).valueOrNull ?? kDefaultSections;
    setState(() {
      if (result.name.isNotEmpty) _nameCtrl.text = result.name;
      if (result.teacher.isNotEmpty) _teacherCtrl.text = result.teacher;
      if (result.rawText.isNotEmpty) _notesCtrl.text = result.rawText;
      final startSec = result.startTime.isEmpty
          ? 0
          : ScheduleLogic.nearestSection(sections, result.startTime);
      final endSec = result.endTime.isEmpty
          ? 0
          : ScheduleLogic.nearestSection(sections, result.endTime);
      final weeks = _parseWeeks(result.weeks);
      if (result.weekday != null ||
          startSec > 0 ||
          result.classroom.isNotEmpty) {
        _sessions = [
          _SessionDraft(
            weekday: result.weekday ?? _sessions.first.weekday,
            startSection: startSec,
            endSection: endSec <= 0 ? startSec : endSec,
            classroom: result.classroom,
            weeks: weeks.toSet(),
            startTime: result.startTime,
            endTime: result.endTime,
          ),
        ];
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已填入识别结果，请核对后再保存')),
      );
    }
  }

  /// 解析 OCR 给出的周次串：`1,2,3` / `1-16` / `1~16` 都能吃
  static List<int> _parseWeeks(String raw) {
    final out = <int>{};
    for (final part in raw.split(RegExp(r'[,，、\s]+'))) {
      if (part.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*[-~至到]\s*(\d+)$').firstMatch(part);
      if (m != null) {
        final a = int.tryParse(m.group(1)!);
        final b = int.tryParse(m.group(2)!);
        if (a != null && b != null) {
          for (var i = a; i <= b && i <= 60; i++) {
            out.add(i);
          }
        }
        continue;
      }
      final v = int.tryParse(part);
      if (v != null && v > 0) out.add(v);
    }
    return out.toList()..sort();
  }
}
