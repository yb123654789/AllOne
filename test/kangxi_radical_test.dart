// 诊断性输出：刻意用 print 打印「还原前/后篇数」等对比信息，便于人工核查。
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allone/features/diary/diary_import.dart';
import 'package:allone/features/diary/diary_pdf_text.dart';

/// 康熙部首还原的回归测试。
///
/// 背景：很多 PDF / txt 导出把汉字写成「康熙部首」书写形式，
/// 例如 `2026年03⽉08⽇` 里的 `⽉`(U+2F49)、`⽇`(U+2F47)。
/// 这些字符**字形与「月」「日」相同、码点却不同**，
/// 导致按「年月日」匹配日期行的逻辑全部失效。
/// 真实案例：一个 32 篇的日记 PDF 只识别出 1 篇。
void main() {
  group('康熙部首还原', () {
    test('日期里的部首被还原', () {
      // ⽉ = U+2F49, ⽇ = U+2F47
      expect(normalizeKangxiRadicals('2026年03⽉08⽇'), '2026年03月08日');
    });

    test('常见部首字符都能还原', () {
      expect(normalizeKangxiRadicals('⽣活区'), '生活区');
      expect(normalizeKangxiRadicals('⼤学'), '大学');
      expect(normalizeKangxiRadicals('⼀本⽇记'), '一本日记');
      expect(normalizeKangxiRadicals('⾬天'), '雨天');
      expect(normalizeKangxiRadicals('⽂字'), '文字');
      expect(normalizeKangxiRadicals('⼯作'), '工作');
      expect(normalizeKangxiRadicals('⾃⼰'), '自己');
    });

    test('普通汉字不受影响', () {
      const normal = '2026年03月08日 周日 晴 日记 华南理工大学';
      expect(normalizeKangxiRadicals(normal), normal);
    });

    test('空串安全', () {
      expect(normalizeKangxiRadicals(''), '');
    });
  });

  group('还原之后，自动分篇恢复正常', () {
    test('部首写法的多篇文本能正确分篇', () {
      // 模拟用户 PDF 里的形态：日期用部首「⽉⽇」，各篇之间没有空行
      const raw =
          '2026年03⽉08⽇\n周⽇ · 晴\n今天休息。\n'
          '2026年03⽉15⽇\n周⽇ · 晴\n今天补考。\n'
          '2026年03⽉21⽇\n周六 · ⾬\n今天下雨。\n';

      // 不还原：识别不出日期行
      final before = splitDiaryText(raw, sourceName: 'x');
      // 还原后：应切成 3 篇
      final after = splitDiaryText(
        normalizeKangxiRadicals(raw),
        sourceName: 'x',
      );

      expect(after.length, 3, reason: '还原后应切成 3 篇');
      expect(after[0].date, DateTime(2026, 3, 8));
      expect(after[1].date, DateTime(2026, 3, 15));
      expect(after[2].date, DateTime(2026, 3, 21));

      print('还原前篇数=${before.length}  还原后篇数=${after.length}');
    });

    test('decodeDiaryText 会自动还原（txt 路径）', () {
      // txt 里同样可能出现部首字符
      final bytes = utf8.encode('2026年03⽉08⽇\n今天休息。\n2026年03⽉09⽇\n今天上班。');
      final text = decodeDiaryText(bytes);
      expect(text.contains('2026年03月08日'), isTrue);
      final drafts = splitDiaryText(text, sourceName: 'x');
      expect(drafts.length, 2);
      expect(drafts[0].date, DateTime(2026, 3, 8));
      expect(drafts[1].date, DateTime(2026, 3, 9));
    });
  });

  group('真实 PDF 文件（若存在则验证）', () {
    test('导入篇数应接近日记实际篇数', () {
      final p = File(r'C:\Users\yb123\Downloads\2026-10-06_124912.pdf');
      if (!p.existsSync()) {
        print('真实 PDF 不在本机，跳过');
        return;
      }
      final bytes = p.readAsBytesSync();
      final text = DiaryPdfText.extract(bytes);

      // 还原前（手工把普通字替换回部首是做不到的，这里直接看修复后）
      final drafts = splitDiaryText(text, sourceName: '一本日记');

      // 统计提取文本里形如「yyyy年MM月dd日」的日期出现次数，作为期望下限参考
      final dateHits = RegExp(r'\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日')
          .allMatches(text)
          .length;

      print(
        '提取文本长度=${text.length}  文本中日期出现次数=$dateHits  分篇结果=${drafts.length} 篇',
      );
      for (final d in drafts.take(8)) {
        print('  日期=${d.date}  标题=${d.title}');
      }

      expect(
        drafts.length,
        greaterThan(1),
        reason: '修复后不应再只识别出 1 篇（修复前正是 1 篇）',
      );
    });
  });
}
