/// 特殊日子 / 节假日（在日历界面直接创建，不属于待办或习惯）
class SpecialDay {
  final String id;
  final String date; // yyyy-MM-dd
  final String name;
  final String type; // holiday / custom
  final String color; // hex

  const SpecialDay({
    required this.id,
    required this.date,
    this.name = '',
    this.type = 'custom',
    this.color = '#E5484D',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'name': name,
    'type': type,
    'color': color,
  };

  factory SpecialDay.fromJson(Map<String, dynamic> j) => SpecialDay(
    id: j['id'] as String? ?? '',
    date: j['date'] as String? ?? '',
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'custom',
    color: j['color'] as String? ?? '#E5484D',
  );
}
