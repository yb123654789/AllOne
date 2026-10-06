import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'diary_import.dart' show normalizeKangxiRadicals;
import 'diary_pdf_images.dart' show PdfTextLineInfoLike;

/// 一行 PDF 文本（含页码与位置）
class PdfTextLineInfo implements PdfTextLineInfoLike {
  @override
  final int pageIndex;
  @override
  final String text;
  @override
  final double top; // 矩形上边界（页面坐标，自上而下递增）
  final double bottom;

  const PdfTextLineInfo({
    required this.pageIndex,
    required this.text,
    required this.top,
    required this.bottom,
  });
}

/// PDF 文本提取（本地解析，不联网）。
///
/// 说明：
/// - 只能提取**文本型 PDF**（其他软件导出的 Word→PDF、日记导出等）；
///   扫描件 / 图片型 PDF 没有文本层，会返回空串，需要先做 OCR。
/// - 解析失败（加密、损坏、非 PDF）会抛出异常，由调用方提示用户。
/// - 提取结果会做一次**康熙部首还原**：不少 App 导出的 PDF 把「月/日」
///   写成康熙部首 `⽉`/`⽇`（码点不同、字形一样），不还原就会导致
///   按日期分篇完全失效（实测 32 篇只能识别 1 篇）。详见 [normalizeKangxiRadicals]。
class DiaryPdfText {
  DiaryPdfText._();

  /// 提取 PDF 的全部文本（按页顺序，页间以换行分隔）
  static String extract(List<int> bytes) {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      return normalizeKangxiRadicals(PdfTextExtractor(doc).extractText());
    } finally {
      doc?.dispose();
    }
  }

  /// 逐行提取文本，附带页码与位置（用于把图片归到正确的日记）。
  ///
  /// 文本同样做康熙部首还原，保证调用方不需要再处理。
  static List<PdfTextLineInfo> extractLines(List<int> bytes) {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      final lines = PdfTextExtractor(doc).extractTextLines();
      return [
        for (final l in lines)
          PdfTextLineInfo(
            pageIndex: l.pageIndex,
            text: normalizeKangxiRadicals(l.text),
            top: l.bounds.top,
            bottom: l.bounds.bottom,
          ),
      ];
    } finally {
      doc?.dispose();
    }
  }

  /// PDF 页数（失败返回 0）
  static int pageCount(List<int> bytes) {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      return doc.pages.count;
    } catch (_) {
      return 0;
    } finally {
      doc?.dispose();
    }
  }
}
