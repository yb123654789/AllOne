import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// 从 PDF 字节流里提取嵌入的 JPEG 图片。
///
/// **为什么自己解析**：项目用的 `syncfusion_flutter_pdf` 只暴露了
/// 「往 PDF 上画图」的 API，没有「把已嵌入的图片取出来」的公开接口
/// （`PdfDocument` 只给 `pages` / `fileStructure` / `attachments`，
/// 拿不到页面资源树，也没有 `extractImages` 之类的方法）。
///
/// 适用范围：只处理 **DCTDecode（JPEG）** 图片，这也是「一本日记」等
/// 手机 App 用 Chromium/Skia 导出 PDF 时的常见形式（实测用户的导出件里
/// 46 张图全部是 DCTDecode）。其它编码（FlateDecode 像素流、JPX 等）
/// 这里不处理，避免引入一个完整 PDF 解码器带来的不确定性。
///
/// 说明：JPEG 是**完整嵌入**在 PDF 流里的，所以可以直接按 SOI/EOI
/// 标记原样截取，不需要重新编码，画质无损。
class PdfJpegImage {
  /// 图片在 PDF 中的字节偏移（用于与页面对象比对，判断属于哪一页）
  final int offset;

  /// JPEG 原始字节
  final Uint8List bytes;

  const PdfJpegImage({required this.offset, required this.bytes});

  int get length => bytes.length;
}

/// 文本行的最小信息（由 `PdfTextLineInfo` 实现，避免两个文件互相 import）
abstract interface class PdfTextLineInfoLike {
  int get pageIndex;
  String get text;
  double get top;
}

/// 一张从 PDF 里提取出来的内嵌图片，附带归属信息。
class PdfEmbeddedImage {
  /// 图片在 PDF 中的字节偏移
  final int offset;

  /// JPEG 原始字节
  final Uint8List bytes;

  /// 图片对象号（`23 0 obj` 里的 23）
  final int objectNumber;

  /// PDF 中的页面序号（0 起，按页面对象在文件里出现的顺序；未能归属时 -1）
  final int pageIndex;

  /// 在页面资源里的名字（如 `X23`）
  final String resourceName;

  /// 图片像素尺寸（来自 PDF 字典，可能为 null）
  final int? width;
  final int? height;

  /// 绘制该图时的 `cm` 变换矩阵 [a,b,c,d,e,f]（解析不到为 null）
  final List<double>? matrix;

  const PdfEmbeddedImage({
    required this.offset,
    required this.bytes,
    required this.objectNumber,
    required this.pageIndex,
    required this.resourceName,
    this.width,
    this.height,
    this.matrix,
  });

  int get length => bytes.length;

  /// 长宽比（宽/高），用于识别装饰性长图
  double? get aspectRatio => (width == null || height == null || height == 0)
      ? null
      : width! / height!;
}

/// 「上一篇延续过来」的键。见 [assignImagesToDates]。
const int carryKey = -1;

/// 把图片按纵向位置归给「它上方最近的那个日期」。
///
/// [datePositions] / [imagePositions] 必须是**同一套页面坐标**下的纵坐标
/// （自上而下递增）。调用方负责换算，换算方式见 [pageTopFromImageMatrix]。
///
/// 规则（由真实导出件的排版规律得出）：
/// - 一篇日记的排版顺序是「日期行 → 元信息行 → 正文 → 图片」，
///   所以图片归给它**上方最近的日期**；
/// - 若图片位于本页**第一个日期之上**，说明它属于**上一页延续过来**的那篇，
///   返回时键为 [carryKey]（调用方据此把图片挂到上一篇）；
/// - [hasCarry] 为 false（没有上一篇）时，这些图片仍记为 [carryKey]，
///   由调用方决定丢弃还是提示。
///
/// 返回：`{日期序号: [图片序号…], carryKey: [图片序号…]}`，按位置升序。
Map<int, List<int>> assignImagesToDates({
  required List<double> datePositions,
  required List<double> imagePositions,
  bool hasCarry = false,
}) {
  final result = <int, List<int>>{};
  if (imagePositions.isEmpty) return result;

  // 日期与图片一起按位置排序，扫描时即可判断「当前图片落在哪个日期之后」
  final order = <(double, int, int)>[]; // (位置, 类型0=日期/1=图片, 序号)
  for (var i = 0; i < datePositions.length; i++) {
    order.add((datePositions[i], 0, i));
  }
  for (var i = 0; i < imagePositions.length; i++) {
    order.add((imagePositions[i], 1, i));
  }
  // 同位置时先处理日期，保证「日期下方的图片」归该日期
  order.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });

  var current = carryKey; // 当前图片应归属的日期序号（-1 = 上一篇延续）
  for (final item in order) {
    if (item.$2 == 0) {
      current = item.$3;
    } else {
      if (current == carryKey && !hasCarry) {
        // 没有上一篇：仍然记录在 carryKey 下，交给调用方处理
      }
      result.putIfAbsent(current, () => []).add(item.$3);
    }
  }
  return result;
}

/// 由图片的 `cm` 矩阵算出它的页面纵坐标（top 制，自上而下递增）。
///
/// Skia 导出的 PDF 在内容流开头有 `0.24 0 0 -0.24 0 841.92 cm`，
/// 因此图片矩阵里的 `f` 是「缩放前、自下而上」的坐标：
/// `top = 页面高 - f × 0.24`。用真实导出件逐页核对过（页 6/14/2 全部吻合）。
double pageTopFromImageMatrix(
  List<double> matrix, {
  double scale = 0.23999999,
  double pageHeight = 841.91998,
}) {
  final f = matrix.length >= 6 ? matrix[5] : 0.0;
  return pageHeight - f * scale;
}

/// 从 PDF 里还原出来的一篇日记草稿（正文 + 归属于它的图片）。
class PdfImportDraft {
  final String text;

  /// 该篇的日期（解析不到为 null）
  final String? date;

  /// 归属于这一篇的图片（JPEG 原始字节，保持原画质）
  final List<Uint8List> images;

  /// 该篇起始页（0 起）
  final int pageIndex;

  const PdfImportDraft({
    required this.text,
    required this.images,
    required this.pageIndex,
    this.date,
  });

  PdfImportDraft copyWith({String? date, List<Uint8List>? images}) =>
      PdfImportDraft(
        text: text,
        date: date ?? this.date,
        images: images ?? this.images,
        pageIndex: pageIndex,
      );
}

/// 把 PDF 解析结果按「日期行」切成多篇，并把图片归给正确的篇。
///
/// 输入可以直接来自 `PdfJpegExtractor.extractWithPages` 与
/// `DiaryPdfText.extractLines`；本函数是纯函数，便于单元测试。
List<PdfImportDraft> buildDraftsFromPdf({
  required List<PdfTextLineInfoLike> lines,
  required List<PdfEmbeddedImage> images,
  required RegExp dateRe,
  int? yearHint,
  bool Function(String text)? isNoise,
}) {
  // 1) 每个页面上的条目按 top 升序（自上而下阅读顺序）
  final pages = <int, List<PdfTextLineInfoLike>>{};
  for (final l in lines) {
    pages.putIfAbsent(l.pageIndex, () => []).add(l);
  }
  for (final list in pages.values) {
    list.sort((a, b) => a.top.compareTo(b.top));
  }

  // 2) 逐年收集「条目」：条目 = 日期行之后、下一条日期行之前的所有文本行
  final year = yearHint ?? 0;
  final drafts = <PdfImportDraft>[];
  final pageImageIdx = <int, List<int>>{};
  for (var i = 0; i < images.length; i++) {
    final pg = images[i].pageIndex;
    if (pg < 0) continue;
    pageImageIdx.putIfAbsent(pg, () => []).add(i);
  }

  final sortedPages = pages.keys.toList()..sort();
  var pendingCarry = <int>[]; // 上一篇延续：本页顶部、日期上方的图片

  for (final pg in sortedPages) {
    final pageLines = pages[pg]!;
    // 找出本页的日期行
    final dateIdx = <int>[];
    for (var i = 0; i < pageLines.length; i++) {
      if (dateRe.hasMatch(pageLines[i].text)) dateIdx.add(i);
    }
    // 切条目
    final blocks = <List<int>>[]; // 每块 = 行序号
    if (dateIdx.isEmpty) {
      if (pageLines.isNotEmpty) {
        blocks.add(List.generate(pageLines.length, (i) => i));
      }
    } else {
      if (dateIdx.first > 0) {
        // 日期之前的行属于上一篇的延续（正文）
        blocks.add(List.generate(dateIdx.first, (i) => i));
      }
      for (var k = 0; k < dateIdx.length; k++) {
        final start = dateIdx[k];
        final end = k + 1 < dateIdx.length ? dateIdx[k + 1] : pageLines.length;
        blocks.add(List.generate(end - start, (i) => start + i));
      }
    }

    // 图片归属
    final datePositions = [for (final i in dateIdx) pageLines[i].top];
    final pageImgIds = pageImageIdx[pg] ?? const <int>[];
    final imgPositions = [
      for (final id in pageImgIds)
        pageTopFromImageMatrix(images[id].matrix ?? const []),
    ];
    final assign = assignImagesToDates(
      datePositions: datePositions,
      imagePositions: imgPositions,
      hasCarry: drafts.isNotEmpty || pendingCarry.isNotEmpty,
    );

    // 上一页延续过来的图片，先并到本页的 carry 里
    var carryIds = <int>[...pendingCarry];
    for (final localIdx in assign[carryKey] ?? const <int>[]) {
      carryIds.add(pageImgIds[localIdx]);
    }
    pendingCarry = [];
    // 标记 carry 是否已被某个「延续块」消费，避免页末兜底时重复并入
    var carryConsumed = false;

    // 逐个块建草稿
    var blockDateSlot = 0; // 对应 datePositions 的下标
    for (var b = 0; b < blocks.length; b++) {
      final rows = blocks[b];
      if (rows.isEmpty) continue;
      final firstRow = pageLines[rows.first];
      final startsWithDate = dateRe.hasMatch(firstRow.text);
      // 收集正文（去掉日期行本身）
      final buf = StringBuffer();
      for (final r in rows) {
        final t = pageLines[r].text.trimRight();
        if (dateRe.hasMatch(t) && r == rows.first) continue;
        if (isNoise != null && isNoise(t)) continue;
        if (t.trim().isEmpty) continue;
        buf.writeln(t);
      }
      final text = buf.toString().trim();

      if (startsWithDate) {
        // 本页第 [blockDateSlot] 个日期块：图片只取「归到该日期」的那些。
        // **注意不要把 carryIds 并进来** —— 那些属于上一篇，
        // 并进本页第一篇会把照片挂错日记。
        final ids = <int>[
          for (final localIdx in assign[blockDateSlot] ?? const <int>[])
            pageImgIds[localIdx],
        ];
        // 注意：**即使正文为空也要建这篇**。
        // 日期行本身就是一篇日记（可能只有日期、没有正文与照片），
        // 早期这里会把它 skip 掉，导致 32 篇变成 31 篇。
        drafts.add(
          PdfImportDraft(
            text: text,
            date: _dateKey(firstRow.text, dateRe, year),
            pageIndex: pg,
            images: [for (final id in ids) images[id].bytes],
          ),
        );
        blockDateSlot++;
      } else {
        // 延续块（位于本页第一个日期之前）：正文与图片都归上一篇
        if (text.isEmpty && carryIds.isEmpty) continue;
        final prev = _lastDatedDraftIndex(drafts);
        if (prev >= 0) {
          final p = drafts[prev];
          drafts[prev] = PdfImportDraft(
            text: [p.text, text].where((s) => s.isNotEmpty).join('\n'),
            date: p.date,
            pageIndex: p.pageIndex,
            images: [...p.images, for (final id in carryIds) images[id].bytes],
          );
          carryConsumed = true; // 已被消费，页末不再兜底
        } else {
          // 还没有任何带日期的草稿（说明这些图属于导出范围之外的上一篇），
          // 仍然建一条草稿保留内容，避免丢数据。
          drafts.add(
            PdfImportDraft(
              text: text,
              pageIndex: pg,
              images: [for (final id in carryIds) images[id].bytes],
            ),
          );
        }
      }
    }

    // 本页处理完后，若还有「归上一篇」的图片没被延续块接收
    // （典型情况：本页第一个块就是日期块，日期上方那些图属于上一篇），
    // 直接并回最近一篇有日期的草稿 —— 否则这些照片会被静默丢掉。
    // 实测真实导出件：页 14 有 10 张图全在唯一日期上方，正是这种情形。
    if (!carryConsumed && carryIds.isNotEmpty) {
      final prev = _lastDatedDraftIndex(drafts);
      if (prev >= 0) {
        final p = drafts[prev];
        drafts[prev] = PdfImportDraft(
          text: p.text,
          date: p.date,
          pageIndex: p.pageIndex,
          images: [...p.images, for (final id in carryIds) images[id].bytes],
        );
      }
    }
  }
  return drafts;
}

/// 最近一篇「带日期」的草稿下标（用于把跨页延续的内容并回上一篇）
int _lastDatedDraftIndex(List<PdfImportDraft> drafts) {
  for (var i = drafts.length - 1; i >= 0; i--) {
    if (drafts[i].date != null) return i;
  }
  return -1;
}

String? _dateKey(String text, RegExp re, int yearHint) {
  final m = re.firstMatch(text);
  if (m == null) return null;
  var y = yearHint;
  var mi = 1;
  if (m.groupCount >= 3 && m.group(1) != null) {
    y = int.parse(m.group(1)!);
    mi = 2;
  }
  final mo = int.tryParse(m.group(mi)!) ?? 1;
  final d = int.tryParse(m.group(mi + 1)!) ?? 1;
  return '${y.toString().padLeft(4, '0')}-'
      '${mo.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';
}

/// PDF 内嵌 JPEG 提取器
class PdfJpegExtractor {
  PdfJpegExtractor._();

  static const int _soi = 0xD8; // JPEG Start Of Image (0xFFD8)
  static const int _eoi = 0xD9; // JPEG End Of Image (0xFFD9)

  /// 扫描全部字节，返回按出现顺序排列的 JPEG 图片（不含归属信息）。
  static List<PdfJpegImage> extractAll(List<int> data) => _extractAll(data);

  /// 扫描并解析归属：给出每张图片的对象号、所在页、资源名与尺寸。
  ///
  /// 解析思路（针对 Chromium/Skia 导出的 PDF —— 页面对象为明文、不使用对象流）：
  /// 1. 扫描 `N 0 obj <</Type /XObject /Subtype /Image ... /Length L>> stream`
  ///    记下图片对象号、字节长度、宽高、以及紧随其后的流起点；
  /// 2. 扫描 `N 0 obj <</Type /Page .../XObject <</X23 23 0 R ...>>>>`，
  ///    按出现顺序得到页面顺序，并记下每页的「资源名 → 对象号」；
  /// 3. 把图片流起点与第 1 步的 JPEG 起始偏移对应起来，即可得到
  ///    「JPEG 字节 ↔ 对象号 ↔ 页面 ↔ 资源名」。
  static List<PdfEmbeddedImage> extractWithPages(List<int> data) {
    final jpegs = _extractAll(data);
    if (jpegs.isEmpty) return const [];

    final objects = _parseImageObjects(data);
    final pages = _parsePages(data);

    // 流起点 → 对象信息
    final byStreamStart = <int, _ImageObject>{};
    for (final o in objects) {
      byStreamStart[o.streamStart] = o;
    }

    final result = <PdfEmbeddedImage>[];
    for (final j in jpegs) {
      // JPEG 起点通常紧跟在流换行之后，允许少量偏移误差
      _ImageObject? obj;
      for (var d = 0; d <= 4; d++) {
        obj = byStreamStart[j.offset - d];
        if (obj != null) break;
      }
      var pageIndex = -1;
      var resourceName = '';
      List<double>? matrix;
      if (obj != null) {
        for (var i = 0; i < pages.length; i++) {
          if (pages[i].xobjects[obj.number] != null) {
            pageIndex = i;
            resourceName = pages[i].xobjects[obj.number]!;
            // 用页内容流里的 cm 矩阵补上绘制位置
            matrix = _placementsOfPage(data, pages[i])[resourceName];
            break;
          }
        }
      }
      result.add(
        PdfEmbeddedImage(
          offset: j.offset,
          bytes: j.bytes,
          objectNumber: obj?.number ?? -1,
          pageIndex: pageIndex,
          resourceName: resourceName,
          width: obj?.width,
          height: obj?.height,
          matrix: matrix,
        ),
      );
    }
    return result;
  }

  /// 解析某页内容流里的图片落点（带缓存，避免同一页重复解压）
  static final Map<int, Map<String, List<double>>> _placementCache = {};

  static Map<String, List<double>> _placementsOfPage(
    List<int> data,
    _PageObject page,
  ) {
    final key = page.contentsObjectNumber;
    if (key < 0) return const {};
    final cached = _placementCache[key];
    if (cached != null) return cached;
    final content = _decodeContentStream(data, key);
    if (content == null || content.isEmpty) {
      _placementCache[key] = const {};
      return const {};
    }
    final parsed = parseImagePlacements(content);
    _placementCache[key] = parsed;
    return parsed;
  }

  /// 清空落点缓存（多次解析不同 PDF 时调用，避免串味）
  static void clearPlacementCache() => _placementCache.clear();

  static List<PdfJpegImage> _extractAll(List<int> data) {
    final out = <PdfJpegImage>[];
    final n = data.length;
    var i = 0;
    while (i + 3 < n) {
      if (data[i] == 0xFF && data[i + 1] == _soi && data[i + 2] == 0xFF) {
        final end = _findEoi(data, i + 2);
        if (end > 0) {
          out.add(
            PdfJpegImage(
              offset: i,
              bytes: Uint8List.fromList(data.sublist(i, end + 1)),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      i++;
    }
    return out;
  }

  /// 找 JPEG 的 EOI（0xFFD9）。
  ///
  /// 熵编码数据里 0xFF 后面必然跟 0x00（字节填充）或 RST 标记（0xD0~0xD7），
  /// 所以第一个 0xFF 0xD9 就是真正的结尾。
  static int _findEoi(List<int> data, int from) {
    for (var i = from; i + 1 < data.length; i++) {
      if (data[i] == 0xFF && data[i + 1] == _eoi) return i + 1;
    }
    return -1;
  }

  /// 解析内容流，取出「资源名 → 绘制位置（cm 矩阵）」。
  ///
  /// 内容流里画图的形式是 `q ... a b c d e f cm /Xn Do Q`，
  /// 其中 `cm` 的 e/f 是平移，即图片落点。
  /// 返回的 key 形如 `X23`，value 为 [a,b,c,d,e,f]。
  static Map<String, List<double>> parseImagePlacements(List<int> content) {
    final out = <String, List<double>>{};
    debugDoCount = 0;
    debugNameCount = 0;
    debugCmCount = 0;
    debugDoLog.clear();
    final n = content.length;
    var i = 0;
    var pending = <double>[];
    String? lastName;
    List<double>? curCm;

    while (i < n) {
      final c = content[i];
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x00) {
        i++;
        continue;
      }
      // 数字 / 小数点 / 负号 → 收集操作数
      if ((c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D) {
        final start = i;
        while (i < n &&
            ((content[i] >= 0x30 && content[i] <= 0x39) ||
                content[i] == 0x2E ||
                content[i] == 0x2D)) {
          i++;
        }
        final v = double.tryParse(
          String.fromCharCodes(content.sublist(start, i)),
        );
        if (v != null) pending.add(v);
        continue;
      }
      // 名字对象 /Xn
      if (c == 0x2F) {
        final start = i + 1;
        var j = start;
        while (j < n && _isNameChar(content[j])) {
          j++;
        }
        lastName = String.fromCharCodes(content.sublist(start, j));
        debugNameCount++;
        i = j;
        continue;
      }
      // 操作符（字母）
      final start = i;
      while (i < n && _isOpChar(content[i])) {
        i++;
      }
      if (i == start) {
        i++;
        continue;
      }
      final op = String.fromCharCodes(content.sublist(start, i));
      if (op == 'cm') {
        debugCmCount++;
        // 记下当前变换矩阵（6 个操作数）；不清空 pending，
        // 因为 Skia 的内容流里 cm 之后还会紧跟颜色/gs 等操作符。
        if (pending.length >= 6) {
          curCm = List<double>.of(pending.sublist(pending.length - 6));
          pending = <double>[];
        }
      } else if (op == 'Do') {
        debugDoCount++;
        final name = lastName;
        final cm = curCm;
        if (name != null && cm != null) {
          out[name] = List<double>.of(cm);
        }
        pending = <double>[];
        lastName = null;
      } else if (_pathConsumingOps.contains(op)) {
        // 路径类操作符：消费操作数，并结束上一轮 cm 的作用范围
        pending = <double>[];
        curCm = null;
      }
      lastName = null;
    }
    return out;
  }

  /// 会消费/重置操作数栈的路径类操作符
  static const Set<String> _pathConsumingOps = {
    're',
    'm',
    'l',
    'c',
    'v',
    'y',
    'h',
    'n',
    'f',
    'F',
    'f*',
    'B',
    'B*',
    'b',
    'b*',
    'S',
    's',
    'W',
    'W*',
    'sh',
  };

  /// 仅用于诊断的计数器
  static int debugDoCount = 0;
  static int debugNameCount = 0;
  static int debugCmCount = 0;
  static final List<String> debugDoLog = [];

  static bool _isNameChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x2D ||
      c == 0x5F;

  static bool _isOpChar(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2A;

  /// 仅用于诊断：暴露每页内容流中图片的落点
  static Map<int, Map<String, List<double>>> debugPlacements(List<int> data) {
    final result = <int, Map<String, List<double>>>{};
    final pages = _parsePages(data);
    for (var i = 0; i < pages.length; i++) {
      final content = _decodeContentStream(data, pages[i].contentsObjectNumber);
      if (content == null || content.isEmpty) continue;
      result[i] = parseImagePlacements(content);
    }
    return result;
  }

  /// 仅用于诊断：暴露某页解压后的内容流字节
  static List<int> debugContentStream(List<int> data, int pageIndex) {
    final pages = _parsePages(data);
    if (pageIndex >= pages.length) return const [];
    final c = _decodeContentStream(data, pages[pageIndex].contentsObjectNumber);
    return c ?? const [];
  }

  /// 取出并解压某对象的内容流。
  ///
  /// 内容流通常是 `/Filter /FlateDecode`（zlib）压缩的，
  /// 用 Dart 自带的 [ZLibDecoder] 解压即可，不必依赖第三方 PDF 库内部实现。
  static List<int>? _decodeContentStream(List<int> data, int objNumber) {
    if (objNumber < 0) return null;
    final at = _indexOf(data, '$objNumber 0 obj'.codeUnits, 0);
    if (at < 0) return null;
    final streamAt = _indexOf(data, 'stream'.codeUnits, at);
    if (streamAt < 0) return null;
    final dict = String.fromCharCodes(data.sublist(at, streamAt));
    final start = _skipEol(data, streamAt + 6);
    final length = _intAfter(dict, '/Length');
    final end = length == null
        ? data.length
        : (start + length).clamp(0, data.length);
    final raw = data.sublist(start, end);
    if (!dict.contains('FlateDecode')) return raw;
    try {
      return ZLibDecoder().convert(raw);
    } catch (_) {
      return null;
    }
  }

  /// 解析 `N 0 obj <</Type /XObject /Subtype /Image ...>> stream` 形式的图片对象
  static List<_ImageObject> _parseImageObjects(List<int> data) {
    final out = <_ImageObject>[];
    final n = data.length;
    var i = 0;
    while (i < n - 5) {
      // 找 "<数字> 0 obj" 里的 " obj"。
      //
      // **必须带前导空格**：直接搜 "obj" 会匹配到上一个对象结尾的
      // "endobj" 里的 "obj"，导致解析的是「上一个对象的结尾」而不是
      // 当前对象的字典 —— 这样拿到的对象号全是垃圾值。
      if (data[i] == 0x20 &&
          data[i + 1] == 0x6F && // o
          data[i + 2] == 0x62 && // b
          data[i + 3] == 0x6A) {
        // j
        // 往后找 "stream"
        final dictEnd = _indexOf(data, 'stream'.codeUnits, i);
        if (dictEnd > 0 && dictEnd - i < 1200) {
          // 字典文本 = 从 " obj" 到 "stream"，足够读到 /Subtype /Length /Width /Height
          final dict = String.fromCharCodes(data.sublist(i, dictEnd));
          if (dict.contains('/Subtype /Image')) {
            // 对象号在 "obj" 之前，这里从 "obj" 往前找形如 "<数字> 0" 的头
            final head = i - 40 < 0 ? 0 : i - 40;
            final headText = String.fromCharCodes(data.sublist(head, i));
            final objNum = _parseObjNumber(headText) ?? -1;
            final streamStart = _skipEol(data, dictEnd + 6);
            out.add(
              _ImageObject(
                number: objNum,
                streamStart: streamStart,
                length: _intAfter(dict, '/Length'),
                width: _intAfter(dict, '/Width'),
                height: _intAfter(dict, '/Height'),
              ),
            );
            i = streamStart;
          }
        }
      }
      i++;
    }
    return out;
  }

  /// 从 "23 0 " 这样的小片段里取对象号。
  ///
  /// 形如 `<对象号> <代数> obj`，这里只需要对象号，
  /// 所以在片段里从后往前找第一个「数字 0」组合。
  static int? _parseObjNumber(String headText) {
    // 先把结尾的空白去掉，拿到 ".... 23 0"
    var t = headText.replaceAll(RegExp(r'[\s\r\n]+$'), '');
    // 末尾应为 "0"
    if (!t.endsWith('0')) return null;
    t = t.substring(0, t.length - 1);
    // 再往前找数字
    final m = RegExp(r'(\d+)[\s\r\n]*$').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// 解析页面对象，按出现顺序返回每页的「图片对象号 → 资源名」与内容流位置
  static List<_PageObject> _parsePages(List<int> data) {
    final out = <_PageObject>[];
    final n = data.length;
    var i = 0;
    while (i < n - 10) {
      // 找 "/Type /Page"（后面不能跟 s）
      if (data[i] == 0x2F &&
          _matchesAt(data, i, '/Type /Page') &&
          !(i + 11 < n && data[i + 11] == 0x73)) {
        // 找这个页面对象字典的结尾（endobj）
        final end = _indexOf(data, 'endobj'.codeUnits, i);
        if (end > 0) {
          final body = String.fromCharCodes(data.sublist(i, end));
          out.add(
            _PageObject(
              xobjects: _parseXObjects(body),
              contentsObjectNumber: _intAfter(body, '/Contents') ?? -1,
            ),
          );
          i = end;
        }
      }
      i++;
    }
    return out;
  }

  /// 从页面字典文本里解析 `/XObject <</X23 23 0 R /X25 25 0 R>>`
  static Map<int, String> _parseXObjects(String pageBody) {
    final map = <int, String>{};
    final idx = pageBody.indexOf('/XObject');
    if (idx < 0) return map;
    // 取 /XObject 之后的一段（到字典收尾或 /Font /MediaBox 为止）
    var seg = pageBody.substring(idx);
    for (final stop in ['/Font', '/MediaBox', '/Contents', '/Parent']) {
      final s = seg.indexOf(stop);
      if (s > 0) seg = seg.substring(0, s);
    }
    final re = RegExp(r'/([A-Za-z0-9]+)\s+(\d+)\s+\d+\s+R');
    for (final m in re.allMatches(seg)) {
      final num = int.tryParse(m.group(2)!);
      if (num != null) map[num] = m.group(1)!;
    }
    return map;
  }

  static bool _matchesAt(List<int> data, int at, String pattern) {
    if (at + pattern.length > data.length) return false;
    for (var k = 0; k < pattern.length; k++) {
      if (data[at + k] != pattern.codeUnitAt(k)) return false;
    }
    return true;
  }

  static int _indexOf(List<int> data, List<int> pattern, int from) {
    final n = data.length;
    for (var i = from; i + pattern.length <= n; i++) {
      var ok = true;
      for (var k = 0; k < pattern.length; k++) {
        if (data[i + k] != pattern[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  static int _skipEol(List<int> data, int at) {
    var i = at;
    if (i < data.length && data[i] == 0x0D) i++;
    if (i < data.length && data[i] == 0x0A) i++;
    return i;
  }

  static int? _intAfter(String s, String key) {
    final i = s.indexOf(key);
    if (i < 0) return null;
    final re = RegExp(r'\d+');
    final m = re.firstMatch(s.substring(i + key.length));
    return m == null ? null : int.tryParse(m.group(0)!);
  }
}

class _ImageObject {
  final int number;
  final int streamStart;
  final int? length;
  final int? width;
  final int? height;
  const _ImageObject({
    required this.number,
    required this.streamStart,
    this.length,
    this.width,
    this.height,
  });
}

class _PageObject {
  final Map<int, String> xobjects;

  /// 该页内容流的对象号（-1 表示未解析到）
  final int contentsObjectNumber;

  const _PageObject({required this.xobjects, this.contentsObjectNumber = -1});
}
