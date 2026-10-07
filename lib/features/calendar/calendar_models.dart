/// 特殊日子 / 节假日（在日历界面直接创建，不属于待办或习惯）
///
/// 除了「某一天」的标记，这里还承担**倒数日**的计算：
/// 支持「每年重复」（生日 / 纪念日），并提供距今天数与倒计时文案。
class SpecialDay {
  final String id;
  final String date; // yyyy-MM-dd（每年重复时只有「月-日」有意义）
  final String name;
  final String type; // holiday / custom
  final String color; // hex

  /// 是否每年重复（生日、纪念日等）。旧数据没有这个字段，默认 false。
  final bool repeatYearly;

  const SpecialDay({
    required this.id,
    required this.date,
    this.name = '',
    this.type = 'custom',
    this.color = '#E5484D',
    this.repeatYearly = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'name': name,
    'type': type,
    'color': color,
    'repeatYearly': repeatYearly,
  };

  factory SpecialDay.fromJson(Map<String, dynamic> j) => SpecialDay(
    id: j['id'] as String? ?? '',
    date: j['date'] as String? ?? '',
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'custom',
    color: j['color'] as String? ?? '#E5484D',
    repeatYearly: j['repeatYearly'] as bool? ?? false,
  );

  /// 是否是用户自己建的日子（内置节假日不可编辑 / 删除 / 参与倒数）
  bool get isCustom => type == 'custom';

  SpecialDay copyWith({
    String? name,
    String? color,
    bool? repeatYearly,
    String? date,
  }) => SpecialDay(
    id: id,
    date: date ?? this.date,
    name: name ?? this.name,
    type: type,
    color: color ?? this.color,
    repeatYearly: repeatYearly ?? this.repeatYearly,
  );

  /// 是否落在某一天（yyyy-MM-dd）。每年重复时只比较「月-日」。
  bool occursOn(String day) {
    if (day.length < 10) return false;
    if (!repeatYearly) return date == day;
    if (date.length < 10) return false;
    return date.substring(5, 10) == day.substring(5, 10);
  }

  /// 是否落在某个月（yyyy-MM）。每年重复的日子每年都算。
  bool inMonth(String ym) {
    if (date.length < 7 || ym.length < 7) return false;
    if (repeatYearly) return date.substring(5, 7) == ym.substring(5, 7);
    return date.substring(0, 7) == ym;
  }

  /// 下一次发生的日期（yyyy-MM-dd）。
  ///
  /// - 不重复：就是自身日期（可能已经过去）；
  /// - 每年重复：今年的那一天，已经过了就取明年。
  String nextDate(String today) {
    if (!repeatYearly || date.length < 10 || today.length < 10) return date;
    final year = int.tryParse(today.substring(0, 4));
    if (year == null) return date;
    final md = date.substring(5, 10);
    final thisYear = '$year-$md';
    return thisYear.compareTo(today) < 0 ? '${year + 1}-$md' : thisYear;
  }

  /// 距今天数：0 = 今天，正数 = 还有几天，负数 = 已经过去几天。
  /// 每年重复的日子永远取「下一次」，不会变成负数。
  int daysFrom(String today) {
    final target = DateTime.tryParse(nextDate(today));
    final base = DateTime.tryParse(today);
    if (target == null || base == null) return 0;
    return DateTime(target.year, target.month, target.day)
        .difference(DateTime(base.year, base.month, base.day))
        .inDays;
  }

  /// 倒计时文案：今天 / 还有 N 天 / 已过 N 天
  String countdownLabel(String today) {
    final d = daysFrom(today);
    if (d == 0) return '今天';
    if (d > 0) return '还有 $d 天';
    return '已过 ${-d} 天';
  }

  /// 每年重复的纪念日：这是第几周年（明年才到就返回下一个周年数）；
  /// 不重复、或起始日期还没到，返回 null。
  int? anniversaryYears(String today) {
    if (!repeatYearly || date.length < 10 || today.length < 10) return null;
    final origin = int.tryParse(date.substring(0, 4));
    final next = int.tryParse(nextDate(today).substring(0, 4));
    if (origin == null || next == null || next <= origin) return null;
    return next - origin;
  }
}
