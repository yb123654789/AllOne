import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import 'diary_models.dart';

/// 日记导入（其他软件的 txt / PDF → AllOne 日记）。
///
/// 设计原则：
/// - **只新增，绝不覆盖**：导入的每篇日记都分配**全新 ID** 写入 `diary/entries/`，
///   整个过程不会读写（更不会删除）任何已有日记文件，导入失败也不影响现有数据。
/// - **纯逻辑与 UI 分离**：本文件只做「字节 → 文本 → 草稿列表」的无副作用转换，
///   便于单元测试；文件选择与写盘分别由 `diary_import_page.dart` 与仓库负责。

/// 一个文件内的文本切分方式
enum DiaryImportSplit {
  /// 智能：识别「日期标题行」自动分篇（识别不到日期则整篇作为一篇）
  auto,

  /// 整篇文件作为一篇日记
  wholeFile,

  /// 按空行分段，每段一篇
  blankLine,
}

extension DiaryImportSplitLabel on DiaryImportSplit {
  String get label => switch (this) {
    DiaryImportSplit.auto => '按日期自动分篇',
    DiaryImportSplit.wholeFile => '整篇作为一篇',
    DiaryImportSplit.blankLine => '按空行分段',
  };

  String get hint => switch (this) {
    DiaryImportSplit.auto => '识别「2024年5月1日 / 2024-05-01」这类日期行自动切成多篇（推荐）',
    DiaryImportSplit.wholeFile => '整个文件保存为一篇日记，不拆分',
    DiaryImportSplit.blankLine => '以连续空行为界，每段保存为一篇日记',
  };
}

// ---------------------------------------------------------------------------
// 文本规范化（康熙部首 → 普通汉字）
// ---------------------------------------------------------------------------

/// 康熙部首书写形式 → 普通汉字（Unicode NFKC 兼容分解）的显式映射。
///
/// 生成方式：对 U+2E80..U+2FD5 逐码点做 NFKC 规范化，取「恰好归一为
/// 单个汉字」的 216 条（无一例归一为多字符，已核对）。
///
/// 刻意写成**显式映射**而不是紧凑字符串 + 索引：早期版本把源字符按码点
/// 排序、目标字符也按码点排序后按下标对齐，但两组排序互不相同，
/// 导致 `⽉` 被错映射成 `門`。显式表没有这种歧义。
const Map<int, String> _kangxiMap = {
  0x2E9F: '母',
  0x2EF3: '龟',
  0x2F00: '一',
  0x2F01: '丨',
  0x2F02: '丶',
  0x2F03: '丿',
  0x2F04: '乙',
  0x2F05: '亅',
  0x2F06: '二',
  0x2F07: '亠',
  0x2F08: '人',
  0x2F09: '儿',
  0x2F0A: '入',
  0x2F0B: '八',
  0x2F0C: '冂',
  0x2F0D: '冖',
  0x2F0E: '冫',
  0x2F0F: '几',
  0x2F10: '凵',
  0x2F11: '刀',
  0x2F12: '力',
  0x2F13: '勹',
  0x2F14: '匕',
  0x2F15: '匚',
  0x2F16: '匸',
  0x2F17: '十',
  0x2F18: '卜',
  0x2F19: '卩',
  0x2F1A: '厂',
  0x2F1B: '厶',
  0x2F1C: '又',
  0x2F1D: '口',
  0x2F1E: '囗',
  0x2F1F: '土',
  0x2F20: '士',
  0x2F21: '夂',
  0x2F22: '夊',
  0x2F23: '夕',
  0x2F24: '大',
  0x2F25: '女',
  0x2F26: '子',
  0x2F27: '宀',
  0x2F28: '寸',
  0x2F29: '小',
  0x2F2A: '尢',
  0x2F2B: '尸',
  0x2F2C: '屮',
  0x2F2D: '山',
  0x2F2E: '巛',
  0x2F2F: '工',
  0x2F30: '己',
  0x2F31: '巾',
  0x2F32: '干',
  0x2F33: '幺',
  0x2F34: '广',
  0x2F35: '廴',
  0x2F36: '廾',
  0x2F37: '弋',
  0x2F38: '弓',
  0x2F39: '彐',
  0x2F3A: '彡',
  0x2F3B: '彳',
  0x2F3C: '心',
  0x2F3D: '戈',
  0x2F3E: '戶',
  0x2F3F: '手',
  0x2F40: '支',
  0x2F41: '攴',
  0x2F42: '文',
  0x2F43: '斗',
  0x2F44: '斤',
  0x2F45: '方',
  0x2F46: '无',
  0x2F47: '日',
  0x2F48: '曰',
  0x2F49: '月',
  0x2F4A: '木',
  0x2F4B: '欠',
  0x2F4C: '止',
  0x2F4D: '歹',
  0x2F4E: '殳',
  0x2F4F: '毋',
  0x2F50: '比',
  0x2F51: '毛',
  0x2F52: '氏',
  0x2F53: '气',
  0x2F54: '水',
  0x2F55: '火',
  0x2F56: '爪',
  0x2F57: '父',
  0x2F58: '爻',
  0x2F59: '爿',
  0x2F5A: '片',
  0x2F5B: '牙',
  0x2F5C: '牛',
  0x2F5D: '犬',
  0x2F5E: '玄',
  0x2F5F: '玉',
  0x2F60: '瓜',
  0x2F61: '瓦',
  0x2F62: '甘',
  0x2F63: '生',
  0x2F64: '用',
  0x2F65: '田',
  0x2F66: '疋',
  0x2F67: '疒',
  0x2F68: '癶',
  0x2F69: '白',
  0x2F6A: '皮',
  0x2F6B: '皿',
  0x2F6C: '目',
  0x2F6D: '矛',
  0x2F6E: '矢',
  0x2F6F: '石',
  0x2F70: '示',
  0x2F71: '禸',
  0x2F72: '禾',
  0x2F73: '穴',
  0x2F74: '立',
  0x2F75: '竹',
  0x2F76: '米',
  0x2F77: '糸',
  0x2F78: '缶',
  0x2F79: '网',
  0x2F7A: '羊',
  0x2F7B: '羽',
  0x2F7C: '老',
  0x2F7D: '而',
  0x2F7E: '耒',
  0x2F7F: '耳',
  0x2F80: '聿',
  0x2F81: '肉',
  0x2F82: '臣',
  0x2F83: '自',
  0x2F84: '至',
  0x2F85: '臼',
  0x2F86: '舌',
  0x2F87: '舛',
  0x2F88: '舟',
  0x2F89: '艮',
  0x2F8A: '色',
  0x2F8B: '艸',
  0x2F8C: '虍',
  0x2F8D: '虫',
  0x2F8E: '血',
  0x2F8F: '行',
  0x2F90: '衣',
  0x2F91: '襾',
  0x2F92: '見',
  0x2F93: '角',
  0x2F94: '言',
  0x2F95: '谷',
  0x2F96: '豆',
  0x2F97: '豕',
  0x2F98: '豸',
  0x2F99: '貝',
  0x2F9A: '赤',
  0x2F9B: '走',
  0x2F9C: '足',
  0x2F9D: '身',
  0x2F9E: '車',
  0x2F9F: '辛',
  0x2FA0: '辰',
  0x2FA1: '辵',
  0x2FA2: '邑',
  0x2FA3: '酉',
  0x2FA4: '釆',
  0x2FA5: '里',
  0x2FA6: '金',
  0x2FA7: '長',
  0x2FA8: '門',
  0x2FA9: '阜',
  0x2FAA: '隶',
  0x2FAB: '隹',
  0x2FAC: '雨',
  0x2FAD: '靑',
  0x2FAE: '非',
  0x2FAF: '面',
  0x2FB0: '革',
  0x2FB1: '韋',
  0x2FB2: '韭',
  0x2FB3: '音',
  0x2FB4: '頁',
  0x2FB5: '風',
  0x2FB6: '飛',
  0x2FB7: '食',
  0x2FB8: '首',
  0x2FB9: '香',
  0x2FBA: '馬',
  0x2FBB: '骨',
  0x2FBC: '高',
  0x2FBD: '髟',
  0x2FBE: '鬥',
  0x2FBF: '鬯',
  0x2FC0: '鬲',
  0x2FC1: '鬼',
  0x2FC2: '魚',
  0x2FC3: '鳥',
  0x2FC4: '鹵',
  0x2FC5: '鹿',
  0x2FC6: '麥',
  0x2FC7: '麻',
  0x2FC8: '黃',
  0x2FC9: '黍',
  0x2FCA: '黑',
  0x2FCB: '黹',
  0x2FCC: '黽',
  0x2FCD: '鼎',
  0x2FCE: '鼓',
  0x2FCF: '鼠',
  0x2FD0: '鼻',
  0x2FD1: '齊',
  0x2FD2: '齒',
  0x2FD3: '龍',
  0x2FD4: '龜',
  0x2FD5: '龠',
};

/// 把文本里的康熙部首字符还原成普通汉字。
///
/// **为什么必须做这一步**：很多 PDF / txt 导出会把汉字写成「康熙部首」
/// 书写形式，例如日期 `2026年03⽉08⽇` 里的 `⽉`(U+2F49) 和 `⽇`(U+2F47)，
/// 看着与「月」(U+6708)、「日」(U+65E5) 一模一样，**码点却完全不同**。
/// 于是所有按「年月日」匹配日期的逻辑全部失效 ——
/// 实测一个 32 篇的日记 PDF 只能识别出 1 篇（首篇之前的内容），
/// 其余 31 篇因为找不到日期行而被合并。
///
/// 这里按 Unicode NFKC 的兼容分解规则还原（等价于 Python 的
/// `unicodedata.normalize('NFKC', s)`）。只改这些部首字符，
/// 不动其它任何内容，因此对正常文本是零影响。
String normalizeKangxiRadicals(String text) {
  if (text.isEmpty) return text;
  final sb = StringBuffer();
  for (final rune in text.runes) {
    final mapped = _kangxiMap[rune];
    if (mapped != null) {
      sb.write(mapped);
    } else {
      sb.writeCharCode(rune);
    }
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// 编码识别
// ---------------------------------------------------------------------------

/// 把文本文件字节解码为字符串。
///
/// 依次尝试：UTF-8 BOM → UTF-16 BOM → 严格 UTF-8 → GBK（中文 txt 常见）
/// → Latin-1 兜底，尽量保证「其他软件导出的 txt」不乱码。
///
/// 解码后会再做一次**康熙部首还原**，见 [normalizeKangxiRadicals] ——
/// 有些软件导出的 txt 会把「月/日」写成码点不同的部首字形，
/// 不还原的话按日期自动分篇会几乎全部失效。
String decodeDiaryText(List<int> bytes) =>
    normalizeKangxiRadicals(_decodeDiaryTextRaw(bytes));

String _decodeDiaryTextRaw(List<int> bytes) {
  if (bytes.isEmpty) return '';

  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-16 LE / BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  // 严格 UTF-8（失败说明不是 UTF-8，转 GBK）
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 继续尝试 GBK
  }
  try {
    return gbk.decode(bytes);
  } catch (_) {
    // 继续兜底
  }
  return latin1.decode(bytes, allowInvalid: true);
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? (bytes[i] | (bytes[i + 1] << 8))
          : ((bytes[i] << 8) | bytes[i + 1]),
    );
  }
  return String.fromCharCodes(units);
}

// ---------------------------------------------------------------------------
// 日期识别
// ---------------------------------------------------------------------------

class _DateHit {
  final DateTime date;
  final int start;
  final int end;
  const _DateHit(this.date, this.start, this.end);
}

class _TimeHit {
  final int hour;
  final int minute;
  const _TimeHit(this.hour, this.minute);
}

/// 一行被识别为「日期标题行」的结果：日期 + 该行剩下的标题文字。
class DateLineMatch {
  final DateTime date;
  final String title;
  const DateLineMatch(this.date, this.title);
}

/// 从任意文本中识别第一个日期（可带时间）。识别不到返回 null。
///
/// 支持格式：`2024年5月1日`、`2024-05-01`、`2024/5/1`、`2024.5.1`、
/// `20240501`、`5月1日`、`5-1`（缺年份时用 [defaultYear]，默认今年）。
DateTime? parseDiaryDate(String text, {int? defaultYear}) =>
    _findDate(text, defaultYear: defaultYear)?.date;

/// 从文件名中识别日期（如 `2024-05-01 日记.txt` → 2024-05-01）。
DateTime? parseDateFromFileName(String fileName, {int? defaultYear}) =>
    _findDate(fileName, defaultYear: defaultYear)?.date;

/// 判断一行是否是「日期标题行」（如 `2024年5月1日 天气晴`），
/// 并取出行内剩余文字作为标题。正文行（日期后面跟大段文字）返回 null。
DateLineMatch? matchDateLine(String line, {int? defaultYear}) {
  final text = line.trim();
  if (text.isEmpty) return null;
  final hit = _findDate(text, defaultYear: defaultYear);
  if (hit == null) return null;

  var rest = text.substring(0, hit.start) + text.substring(hit.end);
  rest = _stripDecoration(rest);
  // 日期后面剩余文字过多 → 视为正文行（避免把正文误判成标题行）
  if (rest.length > 16) return null;
  return DateLineMatch(hit.date, rest);
}

_DateHit? _findDate(String text, {int? defaultYear}) {
  if (text.trim().isEmpty) return null;
  final time = _findTime(text);

  // 1) 2024年5月1日 / 2024-05-01 / 2024.5.1 / 2024/5/1 / 2024_5_1
  final m1 = RegExp(
    r'(\d{4})\s*[年\-/._]\s*(\d{1,2})\s*[月\-/._]\s*(\d{1,2})\s*[日号]?',
  ).firstMatch(text);
  if (m1 != null) {
    final d = _makeDate(
      int.parse(m1.group(1)!),
      int.parse(m1.group(2)!),
      int.parse(m1.group(3)!),
      time,
    );
    if (d != null) return _DateHit(d, m1.start, m1.end);
  }

  // 2) 5月1日（缺年份）
  final m2 = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]').firstMatch(text);
  if (m2 != null) {
    final d = _makeDate(
      defaultYear ?? DateTime.now().year,
      int.parse(m2.group(1)!),
      int.parse(m2.group(2)!),
      time,
    );
    if (d != null) return _DateHit(d, m2.start, m2.end);
  }

  // 3) 紧凑写法 20240501
  final m3 = RegExp(r'(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)').firstMatch(text);
  if (m3 != null) {
    final d = _makeDate(
      int.parse(m3.group(1)!),
      int.parse(m3.group(2)!),
      int.parse(m3.group(3)!),
      time,
    );
    if (d != null) return _DateHit(d, m3.start, m3.end);
  }

  // 4) 5-1 / 5/1（缺年份，风险较高：仅在整行很短时识别）
  if (text.trim().length <= 24) {
    final m4 = RegExp(r'(?<![\d\-/.])(\d{1,2})\s*[-/]\s*(\d{1,2})(?![\d\-/.])')
        .firstMatch(text);
    if (m4 != null) {
      final d = _makeDate(
        defaultYear ?? DateTime.now().year,
        int.parse(m4.group(1)!),
        int.parse(m4.group(2)!),
        time,
      );
      if (d != null) return _DateHit(d, m4.start, m4.end);
    }
  }
  return null;
}

DateTime? _makeDate(int year, int month, int day, _TimeHit? time) {
  if (year < 1900 || year > 2200) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final dt = DateTime(year, month, day, time?.hour ?? 0, time?.minute ?? 0);
  // 排除 2 月 30 日这类不存在的日期（DateTime 会自动进位）
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return dt;
}

_TimeHit? _findTime(String text) {
  final m = RegExp(
    r'(?<![\d:：])(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*\d{2})?(?![\d:：])',
  ).firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return _TimeHit(h, mi);
}

/// 去掉标题两侧的装饰符号、时间、星期、括号补充等
String _stripDecoration(String s) {
  var t = s;
  t = t.replaceAll(
    RegExp(r'(?<![\d:：])\d{1,2}\s*[:：]\s*\d{2}(?::\d{2})?'),
    ' ',
  );
  t = t.replaceAll(RegExp(r'[（(【\[][^）)】\]]{0,12}[）)】\]]'), ' ');
  t = t.replaceAll(RegExp(r'星期[一二三四五六日天]|周[一二三四五六日天]'), ' ');
  t = t.replaceAll(RegExp(r'^[\s#*=\-–—·•>_|【\[（(「《:：,，、.。]+'), '');
  t = t.replaceAll(RegExp(r'[\s#*=\-–—·•<】\]）)」》:：,，、.。|_]+$'), '');
  return t.trim();
}

/// 去掉正文首行的 Markdown / 装饰前缀（`# 标题` → `标题`）
String _cleanInline(String s) => s
    .replaceAll(RegExp(r'^[\s#*=\-–—·•>_|]+'), '')
    .replaceAll(RegExp(r'[\s#*=\-–—·•<|_]+$'), '')
    .trim();

// ---------------------------------------------------------------------------
// 草稿模型
// ---------------------------------------------------------------------------

/// 待导入的一篇日记草稿（用户可在导入前勾选 / 取消）。
class DiaryImportDraft {
  /// 来源文件名
  final String sourceName;
  final String title;
  final String plainText;

  /// 从正文或文件名识别到的日期（决定日记的创建时间），null = 用导入时间
  final DateTime? date;

  /// 随本篇一起导入的附件图片（JPEG 原始字节）。
  ///
  /// 目前只有 PDF 导入会带上（从 PDF 里抽出的内嵌照片）；
  /// txt 导入恒为空。导入时写入 `diary/entries/<id>/media/`。
  final List<Uint8List> attachedImages;

  /// 是否勾选导入
  bool selected;

  /// 与现有日记疑似重复（同标题 + 同日期 + 同正文）
  bool duplicate;

  DiaryImportDraft({
    required this.sourceName,
    required this.title,
    required this.plainText,
    this.date,
    this.attachedImages = const [],
    this.selected = true,
    this.duplicate = false,
  });

  /// 附带图片张数
  int get imageCount => attachedImages.length;

  /// 正文字数（不含空白）
  int get charCount => plainText.replaceAll(RegExp(r'\s'), '').length;

  /// 内容指纹，用于重复检测
  String get fingerprint =>
      diaryFingerprint(title: title, text: plainText, date: date);

  /// 预览文本（列表里展示的摘要）
  String get previewText =>
      plainText.length <= 300 ? plainText : '${plainText.substring(0, 300)}…';

  /// 转换为日记条目（使用全新 ID，**不会覆盖任何已有日记**）
  DiaryEntry toEntry({List<String> tags = const [], DateTime? now}) {
    final created = date ?? now ?? DateTime.now();
    return DiaryEntry(
      id: AppPaths.newId(),
      title: title,
      plainText: plainText,
      createdAt: created,
      updatedAt: created,
      tags: List<String>.of(tags),
    );
  }
}

/// 计算日记指纹（FNV-1a 32 位）。用于导入时检测「疑似重复」。
String diaryFingerprint({
  required String title,
  required String text,
  DateTime? date,
}) {
  final normalized =
      '${title.trim()}\u0001'
      '${date == null ? '' : AppTime.dateOnly(date)}\u0001'
      '${text.trim().replaceAll('\r\n', '\n')}';
  var hash = 0x811C9DC5;
  for (final b in utf8.encode(normalized)) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 现有日记的指纹集合（导入前用来标记疑似重复项）
Set<String> diaryFingerprints(Iterable<DiaryEntry> entries) => entries
    .map(
      (e) => diaryFingerprint(
        title: e.title,
        text: e.plainText,
        date: e.createdAt,
      ),
    )
    .toSet();

// ---------------------------------------------------------------------------
// 文本切分
// ---------------------------------------------------------------------------

/// 把一段（已解码的）文本切分为若干待导入草稿。
///
/// - [split] 切分方式；[fileDate] 从文件名识别到的日期（无日期行时兜底）。
List<DiaryImportDraft> splitDiaryText(
  String text, {
  required String sourceName,
  DiaryImportSplit split = DiaryImportSplit.auto,
  DateTime? fileDate,
}) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  switch (split) {
    case DiaryImportSplit.wholeFile:
      final d = _buildDraft(
        title: '',
        body: normalized,
        date: fileDate,
        sourceName: sourceName,
      );
      return d == null ? const [] : [d];
    case DiaryImportSplit.blankLine:
      return _splitByBlankLines(
        normalized,
        sourceName: sourceName,
        fileDate: fileDate,
      );
    case DiaryImportSplit.auto:
      return _splitByDateLines(
        normalized,
        sourceName: sourceName,
        fileDate: fileDate,
      );
  }
}

/// 按「日期标题行」自动分篇
List<DiaryImportDraft> _splitByDateLines(
  String text, {
  required String sourceName,
  DateTime? fileDate,
}) {
  final drafts = <DiaryImportDraft>[];
  final preamble = <String>[];
  var body = <String>[];
  var title = '';
  DateTime? date;
  var started = false;

  void flush() {
    if (!started) return;
    final d = _buildDraft(
      title: title,
      body: _trimBlank(body).join('\n'),
      date: date,
      sourceName: sourceName,
    );
    if (d != null) drafts.add(d);
    body = <String>[];
    title = '';
    date = null;
    started = false;
  }

  for (final line in text.split('\n')) {
    final m = matchDateLine(line, defaultYear: fileDate?.year);
    if (m != null) {
      flush();
      started = true;
      date = m.date;
      title = m.title;
    } else if (started) {
      body.add(line);
    } else {
      preamble.add(line);
    }
  }
  flush();

  // 第一篇日期行之前的内容单独成篇，避免丢内容
  final pre = _trimBlank(preamble);
  if (pre.isNotEmpty) {
    final d = _buildDraft(
      title: '',
      body: pre.join('\n'),
      date: fileDate,
      sourceName: sourceName,
    );
    if (d != null) drafts.insert(0, d);
  }
  return drafts;
}

/// 按空行分段
List<DiaryImportDraft> _splitByBlankLines(
  String text, {
  required String sourceName,
  DateTime? fileDate,
}) {
  final blocks = <List<String>>[];
  var cur = <String>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      if (cur.isNotEmpty) {
        blocks.add(cur);
        cur = <String>[];
      }
    } else {
      cur.add(line);
    }
  }
  if (cur.isNotEmpty) blocks.add(cur);

  final out = <DiaryImportDraft>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final fallback = i == 0 ? fileDate : null;
    final m = matchDateLine(block.first, defaultYear: fileDate?.year);
    final d = m != null
        ? _buildDraft(
            title: m.title,
            body: block.skip(1).join('\n'),
            date: m.date,
            sourceName: sourceName,
          )
        : _buildDraft(
            title: '',
            body: block.join('\n'),
            date: fallback,
            sourceName: sourceName,
          );
    if (d != null) out.add(d);
  }
  return out;
}

/// 组装草稿：标题为空时尝试用正文首行，仍为空则用日期 / 文件名兜底，最后去空白
DiaryImportDraft? _buildDraft({
  required String title,
  required String body,
  required String sourceName,
  DateTime? date,
}) {
  var t = title.trim();
  var b = body.trim();
  if (t.isEmpty && b.isEmpty) return null;

  if (t.isEmpty) {
    final lines = _trimBlank(b.split('\n'));
    if (lines.isNotEmpty) {
      final first = _cleanInline(lines.first);
      if (first.isNotEmpty && first.length <= 24 && lines.length > 1) {
        t = first;
        b = lines.skip(1).join('\n').trim();
      }
    }
  }
  if (t.isEmpty) {
    t = date != null ? '${AppTime.dateOnly(date)} 的日记' : sourceName;
  }

  return DiaryImportDraft(
    sourceName: sourceName,
    title: t,
    plainText: b,
    date: date,
  );
}

List<String> _trimBlank(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

/// 去掉扩展名，作为来源标题兜底
String sourceNameWithoutExtension(String fileName) {
  final i = fileName.lastIndexOf('.');
  final base = i > 0 ? fileName.substring(0, i) : fileName;
  return base.trim().isEmpty ? '导入的日记' : base.trim();
}
