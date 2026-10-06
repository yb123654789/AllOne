// 诊断输出：打印提取统计，便于人工核查。
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/diary/diary_pdf_images.dart';

/// PDF 内嵌图片提取的回归测试。
///
/// 用真实导出件（「一本日记」App 导出，Chromium/Skia 生成）验证：
/// 46 张内嵌 JPEG 能全部提取、且能归属到正确的页。
void main() {
  final pdfPath = r'C:\Users\yb123\Downloads\2026-10-06_124912.pdf';

  group('PdfJpegExtractor - 合成数据', () {
    test('能按 SOI/EOI 切出一张完整 JPEG', () {
      final data = <int>[
        0x25, 0x50, 0x44, 0x46, // %PDF
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, // SOI + APP0
        0x12, 0x34, 0x56, // 假数据
        0xFF, 0xD9, // EOI
        0x00, 0x00,
      ];
      final imgs = PdfJpegExtractor.extractAll(data);
      expect(imgs.length, 1);
      expect(imgs.first.bytes.first, 0xFF);
      expect(imgs.first.bytes[1], 0xD8);
      expect(imgs.first.bytes.last, 0xD9);
      // SOI(2) + APP0(4) + 假数据(3) + EOI(2) = 11 字节
      expect(imgs.first.bytes.length, 11);
    });

    test('没有 JPEG 时返回空', () {
      expect(PdfJpegExtractor.extractAll([1, 2, 3, 4, 5]), isEmpty);
    });

    test('缺少 EOI 的残缺 JPEG 不被计入', () {
      final data = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03];
      expect(PdfJpegExtractor.extractAll(data), isEmpty);
    });
  });

  group('PdfJpegExtractor - 真实导出件', () {
    test('46 张图片全部提取且归属到页', () {
      final p = File(pdfPath);
      if (!p.existsSync()) {
        print('真实 PDF 不在本机，跳过');
        return;
      }
      final bytes = p.readAsBytesSync();
      final images = PdfJpegExtractor.extractWithPages(bytes);

      print('提取到 ${images.length} 张图片');
      final byPage = <int, int>{};
      var withPage = 0;
      for (final img in images) {
        byPage[img.pageIndex] = (byPage[img.pageIndex] ?? 0) + 1;
        if (img.pageIndex >= 0) withPage++;
      }
      print('已归属到页的: $withPage / ${images.length}');
      for (final k in (byPage.keys.toList()..sort())) {
        print('  页 $k: ${byPage[k]} 张');
      }

      expect(images.length, 46, reason: 'PDF 里应有 46 张内嵌 JPEG');
      expect(withPage, 46, reason: '每张图片都应能归属到某一页');

      // 每张都必须是完整 JPEG
      for (final img in images) {
        expect(img.bytes.first, 0xFF);
        expect(img.bytes[1], 0xD8);
        expect(img.bytes[img.bytes.length - 2], 0xFF);
        expect(img.bytes.last, 0xD9);
      }
      // 尺寸信息应解析出来
      expect(images.where((i) => i.width != null).length, 46);
      expect(images.where((i) => i.height != null).length, 46);
      // 对象号应为正数（回归：早期版本会误匹配 endobj，得到 -1）
      expect(
        images.where((i) => i.objectNumber > 0).length,
        46,
        reason: '对象号解析回归：不得匹配到 endobj 里的 obj',
      );
    });
  });
}
