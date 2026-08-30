import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/utils/media_utils.dart';

/// 从照片识别课程信息。
/// 该功能依赖 Google ML Kit（仅 Android / iOS），调用前需用
/// [isOcrSupported] 判断当前平台是否支持。

/// 当前平台是否支持本地 OCR（Android / iOS）
bool isOcrSupported() {
  return Platform.isAndroid || Platform.isIOS;
}

/// 识别结果（尽量按课程字段拆分，供用户确认后回填）
class CourseOcrResult {
  String name; // 课程名
  String teacher; // 教师
  String classroom; // 教室 / 地点
  int? weekday; // 星期（1-7，无法判断时为 null）
  String startTime; // 开始时间
  String endTime; // 结束时间
  String weeks; // 周次（逗号分隔字符串）
  final String rawText; // 完整原文

  CourseOcrResult({
    this.name = '',
    this.teacher = '',
    this.classroom = '',
    this.weekday,
    this.startTime = '',
    this.endTime = '',
    this.weeks = '',
    this.rawText = '',
  });

  bool get usable => name.isNotEmpty || classroom.isNotEmpty;
}

/// 从相册选图并做本地 OCR 识别，返回解析结果。
Future<CourseOcrResult?> recognizeCourseFromImage() async {
  final file = await MediaUtils.pickImage();
  if (file == null) return null;

  // 中文识别脚本
  final recognizer = TextRecognizer(
    script: TextRecognitionScript.chinese,
  );
  try {
    final input = InputImage.fromFile(file);
    final result = await recognizer.processImage(input);
    final lines = <String>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty) lines.add(text);
      }
    }
    return parseOcrCourses(lines);
  } finally {
    await recognizer.close();
  }
}

/// 从识别出的文本行里解析出课程字段候选。
/// 课程表照片为表格，这里做启发式解析：
/// - 时间：形如 08:00 / 8:00-9:40 或「第N节」
/// - 教室：含「教/室/楼/馆/楼」且长度较短
/// - 星期：含「周一/星期一/礼拜一」等
/// - 教师：含「老师/教师」或「姓名(教师)」
/// - 其余作为课程名候选
CourseOcrResult parseOcrCourses(List<String> lines) {
  final raw = lines.join('\n');
  String? startTime, endTime;
  String? classroom;
  int? weekday;
  final nameParts = <String>[];
  final teacherParts = <String>[];

  final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*[-~至到]\s*(\d{1,2}):(\d{2})');
  final singleTimeRegex = RegExp(r'(\d{1,2}):(\d{2})');
  final weekdays = {
    '周一': 1, '星期一': 1, '礼拜一': 1, '周1': 1,
    '周二': 2, '星期二': 2, '礼拜二': 2, '周2': 2,
    '周三': 3, '星期三': 3, '礼拜三': 3, '周3': 3,
    '周四': 4, '星期四': 4, '礼拜四': 4, '周4': 4,
    '周五': 5, '星期五': 5, '礼拜五': 5, '周5': 5,
    '周六': 6, '星期六': 6, '礼拜六': 6, '周6': 6,
    '周日': 7, '星期日': 7, '星期天': 7, '礼拜日': 7, '周7': 7,
  };
  final weekRegex = RegExp(r'第?(\d{1,2})[、\s-]*[周周节]');
  final roomKeyword = RegExp(
    r'(?:(?:教学楼|实验楼|综合楼|图书馆|体育馆|实验中心|机房|教室|实验|报告厅|阶梯教室)[\w\dA-Za-z\-]*|[\w\dA-Za-z]+[室楼馆厅])',
  );
  final teacherKeyword = RegExp(r'(老师|教师|教授|讲师)');

  for (final line in lines) {
    final s = line.trim();
    if (s.isEmpty) continue;

    // 判断星期
    for (final e in weekdays.entries) {
      if (s.contains(e.key)) {
        weekday = e.value;
        break;
      }
    }

    // 判断时间段
    final timeMatch = timeRegex.firstMatch(s);
    if (timeMatch != null) {
      startTime = '${timeMatch.group(1)!.padLeft(2, '0')}:${timeMatch.group(2)}';
      endTime = '${timeMatch.group(3)!.padLeft(2, '0')}:${timeMatch.group(4)}';
      continue;
    }

    // 判断教室
    if (roomKeyword.hasMatch(s) && s.length <= 20) {
      classroom = s;
      continue;
    }

    // 判断教师
    if (teacherKeyword.hasMatch(s) && s.length <= 15) {
      teacherParts.add(s);
      continue;
    }

    // 其余作为课程名候选（剔除纯数字行、纯星期行、周次行）
    final isPureNumber = RegExp(r'^[\d\s,，\-~至到]+$').hasMatch(s);
    final isWeekInfo = weekRegex.hasMatch(s) && s.length <= 12;
    if (!isPureNumber && !isWeekInfo) {
      nameParts.add(s);
    }
  }

  // 课程名：取最像课程名的（一般是第一项且非纯时间/地点）
  final name = nameParts.isNotEmpty ? nameParts.first : '';
  final teacher =
      teacherParts.isNotEmpty ? teacherParts.join('、') : '';
  // 周次：拆出连续的周数字
  final weeks = _extractWeeks(raw);

  return CourseOcrResult(
    name: name,
    teacher: teacher,
    classroom: classroom ?? '',
    weekday: weekday,
    startTime: startTime ?? '',
    endTime: endTime ?? '',
    weeks: weeks,
    rawText: raw,
  );
}

/// 从原文里提取周次（如 1-16 或 1,2,3,4,5），返回逗号分隔。
String _extractWeeks(String raw) {
  final rangeMatch = RegExp(r'(第)?\s*(\d{1,2})\s*[-~至到]\s*(\d{1,2})\s*[周节]').firstMatch(raw);
  if (rangeMatch != null) {
    final a = int.tryParse(rangeMatch.group(2)!) ?? 1;
    final b = int.tryParse(rangeMatch.group(3)!) ?? a;
    if (b >= a && b - a <= 60) {
      return List.generate(b - a + 1, (i) => (a + i).toString()).join(',');
    }
  }
  final listMatch = RegExp(r'\d{1,2}').allMatches(raw).map((m) => m.group(0)!).toList();
  final nums = <int>[];
  for (final n in listMatch) {
    final v = int.tryParse(n) ?? 0;
    if (v >= 1 && v <= 30 && !nums.contains(v)) nums.add(v);
  }
  nums.sort();
  return nums.take(20).join(',');
}
