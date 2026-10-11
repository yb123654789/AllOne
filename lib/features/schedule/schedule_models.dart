/// 学期（半年一换）
class Term {
  final String id;
  final String name;
  final String start; // yyyy-MM-dd
  final String end; // yyyy-MM-dd

  const Term({
    required this.id,
    this.name = '',
    this.start = '',
    this.end = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'end': end,
  };

  factory Term.fromJson(Map<String, dynamic> j) => Term(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    start: j['start'] as String? ?? '',
    end: j['end'] as String? ?? '',
  );
}

/// 作息表里的一节课（第几节 + 起止时间）。
///
/// 引入它是为了两件事：① 课程只选「第几节」，不用每次手填时间；
/// ② 周网格能按节次画成等高的行（时间轴在左侧），空间不再局促。
class SectionTime {
  final int index; // 第几节（1 起）
  final String start; // HH:mm
  final String end; // HH:mm

  const SectionTime({
    required this.index,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'start': start,
    'end': end,
  };

  factory SectionTime.fromJson(Map<String, dynamic> j) => SectionTime(
    index: (j['index'] as num?)?.toInt() ?? 1,
    start: j['start'] as String? ?? '08:00',
    end: j['end'] as String? ?? '08:45',
  );

  SectionTime copyWith({int? index, String? start, String? end}) =>
      SectionTime(
        index: index ?? this.index,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  /// 起止合并展示：`08:50-09:35`
  String get label => '$start-$end';
}

/// 默认作息表（照用户给的课表截图：上午 4 节、下午 4 节、晚上 3 节）。
///
/// 只作为**默认值**：用户可以在「作息表」页里随意改时间、增删节次。
const List<SectionTime> kDefaultSections = [
  SectionTime(index: 1, start: '08:50', end: '09:35'),
  SectionTime(index: 2, start: '09:40', end: '10:25'),
  SectionTime(index: 3, start: '10:40', end: '11:25'),
  SectionTime(index: 4, start: '11:30', end: '12:15'),
  SectionTime(index: 5, start: '14:00', end: '14:45'),
  SectionTime(index: 6, start: '14:50', end: '15:35'),
  SectionTime(index: 7, start: '15:45', end: '16:30'),
  SectionTime(index: 8, start: '16:40', end: '17:25'),
  SectionTime(index: 9, start: '19:00', end: '19:45'),
  SectionTime(index: 10, start: '19:50', end: '20:35'),
  SectionTime(index: 11, start: '22:40', end: '23:25'),
];

/// 课程的**一个上课时段**：周几 + 第几节到第几节 + 教室 + 上哪些周。
///
/// 为什么按时段拆开：同一门课常常一周上两次、甚至两个时段教室不同
/// （截图里「数据结构」就在 A4201 与 A4607 各一次），
/// 拆开之后一门课只建一条记录，统计页也不会重复。
class CourseSession {
  final int weekday; // 1-7（周一=1）

  /// 起始 / 结束节次（相等 = 单节；start < end = 连堂）。
  /// 旧数据没有节次概念，这里为 0 表示「未指定」，显示时按 [startTime] 就近匹配作息表。
  final int startSection;
  final int endSection;

  /// 上课周次（1 起）。逐周点选的结果；空 = 每周。
  final List<int> weeks;

  final String classroom;

  /// 可选的自定义时间（旧数据迁移用；新课程留空，时间由作息表决定）
  final String startTime;
  final String endTime;

  const CourseSession({
    this.weekday = 1,
    this.startSection = 0,
    this.endSection = 0,
    this.weeks = const [],
    this.classroom = '',
    this.startTime = '',
    this.endTime = '',
  });

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'startSection': startSection,
    'endSection': endSection,
    'weeks': weeks,
    'classroom': classroom,
    if (startTime.isNotEmpty) 'startTime': startTime,
    if (endTime.isNotEmpty) 'endTime': endTime,
  };

  factory CourseSession.fromJson(Map<String, dynamic> j) => CourseSession(
    weekday: (j['weekday'] as num?)?.toInt() ?? 1,
    startSection: (j['startSection'] as num?)?.toInt() ?? 0,
    endSection: (j['endSection'] as num?)?.toInt() ?? 0,
    weeks:
        (j['weeks'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ??
        const [],
    classroom: j['classroom'] as String? ?? '',
    startTime: j['startTime'] as String? ?? '',
    endTime: j['endTime'] as String? ?? '',
  );

  CourseSession copyWith({
    int? weekday,
    int? startSection,
    int? endSection,
    List<int>? weeks,
    String? classroom,
    String? startTime,
    String? endTime,
    bool clearCustomTime = false,
  }) => CourseSession(
    weekday: weekday ?? this.weekday,
    startSection: startSection ?? this.startSection,
    endSection: endSection ?? this.endSection,
    weeks: weeks ?? this.weeks,
    classroom: classroom ?? this.classroom,
    startTime: clearCustomTime ? '' : (startTime ?? this.startTime),
    endTime: clearCustomTime ? '' : (endTime ?? this.endTime),
  );

  bool get hasCustomTime => startTime.isNotEmpty || endTime.isNotEmpty;

  /// 该时段是否在这一周上课（[weekNo] 从 1 开始；空 weeks = 每周都上）
  bool occursInWeek(int weekNo) => weeks.isEmpty || weeks.contains(weekNo);

  bool get isSingleSection => startSection > 0 && endSection <= startSection;
}

/// 课程
class Course {
  final String id;
  final String termId;
  final String name;
  final String teacher;

  /// 课程块颜色（hex）。留空时界面按名称哈希分配一个默认色。
  final String color;

  /// 上课时段（可多个）
  final List<CourseSession> sessions;

  final String notes; // 课程说明（Markdown/文本）

  const Course({
    required this.id,
    this.termId = '',
    this.name = '',
    this.teacher = '',
    this.color = '',
    this.sessions = const [],
    this.notes = '',
  });

  /// 兼容旧字段：教室 / 星期 / 时间 / 周次都取**第一个时段**的值。
  /// 界面上请优先用 sessions（多时段）或 [startClock] / [endClock]。
  String get classroom => sessions.isEmpty ? '' : sessions.first.classroom;
  int get weekday => sessions.isEmpty ? 1 : sessions.first.weekday;
  List<int> get weeks => sessions.isEmpty ? const [] : sessions.first.weeks;

  /// 第一个时段（没有时段时给一个空时段）：
  /// 只是为了让「旧用法」（如导出、日历摘要）少写一堆空判断。
  CourseSession get primarySession =>
      sessions.isEmpty ? const CourseSession() : sessions.first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'termId': termId,
    'name': name,
    'teacher': teacher,
    'color': color,
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'notes': notes,
  };

  /// 容错读取：**兼容只有 weekday/startTime/endTime/weeks 的旧课程**
  /// —— 把它们迁移成一个时段（自定义时间保留，节次留 0 由界面就近匹配）。
  factory Course.fromJson(Map<String, dynamic> j) {
    final sessions = <CourseSession>[];
    final raw = j['sessions'] as List?;
    if (raw != null) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          sessions.add(CourseSession.fromJson(e));
        }
      }
    }
    if (sessions.isEmpty) {
      final weeks =
          (j['weeks'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const <int>[];
      sessions.add(
        CourseSession(
          weekday: (j['weekday'] as num?)?.toInt() ?? 1,
          weeks: weeks,
          classroom: j['classroom'] as String? ?? '',
          startTime: j['startTime'] as String? ?? '',
          endTime: j['endTime'] as String? ?? '',
        ),
      );
    }
    return Course(
      id: j['id'] as String? ?? '',
      termId: j['termId'] as String? ?? '',
      name: j['name'] as String? ?? '',
      teacher: j['teacher'] as String? ?? '',
      color: j['color'] as String? ?? '',
      sessions: sessions,
      notes: j['notes'] as String? ?? '',
    );
  }

  Course copyWith({
    String? termId,
    String? name,
    String? teacher,
    String? color,
    List<CourseSession>? sessions,
    String? notes,
  }) => Course(
    id: id,
    termId: termId ?? this.termId,
    name: name ?? this.name,
    teacher: teacher ?? this.teacher,
    color: color ?? this.color,
    sessions: sessions ?? this.sessions,
    notes: notes ?? this.notes,
  );
}
