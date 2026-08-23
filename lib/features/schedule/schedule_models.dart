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

/// 课程
class Course {
  final String id;
  final String termId;
  final String name;
  final String teacher;
  final String classroom;
  final int weekday; // 1-7（周一=1）
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final List<int> weeks; // 上课周次，如 [1,2,...,16]
  final String notes; // 课程说明（Markdown/文本）

  const Course({
    required this.id,
    this.termId = '',
    this.name = '',
    this.teacher = '',
    this.classroom = '',
    this.weekday = 1,
    this.startTime = '08:00',
    this.endTime = '09:40',
    this.weeks = const [],
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'termId': termId,
    'name': name,
    'teacher': teacher,
    'classroom': classroom,
    'weekday': weekday,
    'startTime': startTime,
    'endTime': endTime,
    'weeks': weeks,
    'notes': notes,
  };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'] as String? ?? '',
    termId: j['termId'] as String? ?? '',
    name: j['name'] as String? ?? '',
    teacher: j['teacher'] as String? ?? '',
    classroom: j['classroom'] as String? ?? '',
    weekday: (j['weekday'] as num?)?.toInt() ?? 1,
    startTime: j['startTime'] as String? ?? '08:00',
    endTime: j['endTime'] as String? ?? '09:40',
    weeks:
        (j['weeks'] as List?)
            ?.whereType<num>()
            .map((e) => e.toInt())
            .toList() ??
        const [],
    notes: j['notes'] as String? ?? '',
  );
}
