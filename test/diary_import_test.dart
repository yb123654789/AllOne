import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/app_paths.dart';
import 'package:allone/core/storage/json_store.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/diary/diary_import.dart';
import 'package:allone/features/diary/diary_models.dart';
import 'package:allone/features/diary/diary_repository.dart';

DiaryEntry _entry({
  String id = '',
  String title = '',
  String text = '',
  DateTime? date,
  List<String> tags = const [],
}) => DiaryEntry(
  id: id,
  title: title,
  plainText: text,
  createdAt: date ?? DateTime(2026, 1, 1),
  updatedAt: date ?? DateTime(2026, 1, 1),
  tags: tags,
);

void main() {
  group('日记导入 - 编码识别', () {
    test('UTF-8 中文', () {
      expect(decodeDiaryText(utf8.encode('2024年5月1日 晴')), '2024年5月1日 晴');
    });

    test('UTF-8 BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('日记正文')];
      expect(decodeDiaryText(bytes), '日记正文');
    });

    test('GBK（其他软件常见的 Windows 记事本编码）', () {
      final bytes = gbk.encode('今天很开心，记录一下。');
      expect(decodeDiaryText(bytes), '今天很开心，记录一下。');
    });

    test('UTF-16 LE BOM', () {
      const text = '导入测试';
      final bytes = <int>[0xFF, 0xFE];
      for (final unit in text.codeUnits) {
        bytes.add(unit & 0xFF);
        bytes.add((unit >> 8) & 0xFF);
      }
      expect(decodeDiaryText(bytes), text);
    });

    test('空内容', () {
      expect(decodeDiaryText(const []), '');
    });
  });

  group('日记导入 - 日期识别', () {
    test('常见中文日期格式', () {
      expect(parseDiaryDate('2024年5月1日 星期三 晴'), DateTime(2024, 5, 1));
      expect(parseDiaryDate('【2024-05-01】'), DateTime(2024, 5, 1));
      expect(parseDiaryDate('2024/5/1'), DateTime(2024, 5, 1));
      expect(parseDiaryDate('2024.05.01'), DateTime(2024, 5, 1));
      expect(parseDiaryDate('20240501'), DateTime(2024, 5, 1));
    });

    test('缺年份时用默认年份', () {
      expect(
        parseDiaryDate('5月1日 天气好', defaultYear: 2023),
        DateTime(2023, 5, 1),
      );
    });

    test('带时间', () {
      expect(
        parseDiaryDate('2024-05-01 08:30 起床'),
        DateTime(2024, 5, 1, 8, 30),
      );
    });

    test('无日期 / 非法日期返回 null', () {
      expect(parseDiaryDate('今天天气不错'), isNull);
      expect(parseDiaryDate('2024-02-30'), isNull);
      expect(parseDiaryDate('2024-13-01'), isNull);
    });

    test('从文件名识别日期', () {
      expect(parseDateFromFileName('2024-05-01 日记.txt'), DateTime(2024, 5, 1));
      expect(parseDateFromFileName('随手记.txt'), isNull);
    });
  });

  group('日记导入 - 日期标题行判定', () {
    test('日期 + 简短标题 → 日期行', () {
      final m = matchDateLine('2024年5月1日 星期三 晴');
      expect(m, isNotNull);
      expect(m!.date, DateTime(2024, 5, 1));
      expect(m.title, '晴');
    });

    test('日期 + 大段正文 → 不是日期行（避免正文被切成标题）', () {
      expect(matchDateLine('2024年5月1日我去了北京玩了一整天特别开心所以想记录下来'), isNull);
    });

    test('普通正文行 → null', () {
      expect(matchDateLine('今天很开心'), isNull);
    });
  });

  group('日记导入 - 文本切分', () {
    const sample = '''
第一篇前言：这是我以前的日记。

2024年5月1日 晴
今天去公园散步了。
很放松。

2024年5月2日 雨
在家看书。
''';

    test('按日期自动分篇（含前置内容单独成篇）', () {
      final drafts = splitDiaryText(sample, sourceName: '旧日记');
      expect(drafts.length, 3);
      // 首篇 = 日期行之前的内容：单行内容不作标题（避免标题=正文），改用来源文件名，正文完整保留
      expect(drafts[0].title, '旧日记');
      expect(drafts[0].plainText, '第一篇前言：这是我以前的日记。');
      expect(drafts[1].title, '晴');
      expect(drafts[1].date, DateTime(2024, 5, 1));
      expect(drafts[1].plainText, '今天去公园散步了。\n很放松。');
      expect(drafts[2].date, DateTime(2024, 5, 2));
    });

    test('没有日期行时整篇作为一篇', () {
      final drafts = splitDiaryText('只有一段文字，没有任何日期。\n第二行。', sourceName: '随笔');
      expect(drafts.length, 1);
      expect(drafts.first.plainText.contains('第二行'), isTrue);
    });

    test('整篇模式不拆分', () {
      final drafts = splitDiaryText(
        sample,
        sourceName: '旧日记',
        split: DiaryImportSplit.wholeFile,
      );
      expect(drafts.length, 1);
      expect(drafts.first.plainText.contains('2024年5月2日'), isTrue);
    });

    test('按空行分段', () {
      final drafts = splitDiaryText(
        sample,
        sourceName: '旧日记',
        split: DiaryImportSplit.blankLine,
      );
      expect(drafts.length, greaterThanOrEqualTo(3));
      expect(drafts.first.plainText, '第一篇前言：这是我以前的日记。');
      // 首段之后的段落由日期行开头，日期被识别
      expect(drafts.any((d) => d.date == DateTime(2024, 5, 1)), isTrue);
    });

    test('文件名日期作为兜底（无日期行的文件）', () {
      final drafts = splitDiaryText(
        '小时候的回忆。\n那时候很喜欢下雨天。',
        sourceName: '2023-06-01 回忆',
        fileDate: DateTime(2023, 6, 1),
      );
      expect(drafts.length, 1);
      expect(drafts.first.date, DateTime(2023, 6, 1));
    });

    test('空文件不产生草稿', () {
      expect(splitDiaryText('   \n\n  ', sourceName: '空'), isEmpty);
    });
  });

  group('日记导入 - 重复检测与转换', () {
    test('指纹：内容相同则相同，日期不同则不同', () {
      final a = diaryFingerprint(
        title: 'A',
        text: '正文',
        date: DateTime(2024, 5, 1),
      );
      final b = diaryFingerprint(
        title: 'A',
        text: '正文',
        date: DateTime(2024, 5, 1),
      );
      final c = diaryFingerprint(
        title: 'A',
        text: '正文',
        date: DateTime(2024, 5, 2),
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('现有日记指纹可用于标记疑似重复', () {
      final existing = [
        _entry(
          id: 'x',
          title: '晴',
          text: '今天去公园散步了。',
          date: DateTime(2024, 5, 1),
        ),
      ];
      final keys = diaryFingerprints(existing);
      final drafts = splitDiaryText(
        '2024年5月1日 晴\n今天去公园散步了。\n\n2024年5月3日 多云\n新的内容。',
        sourceName: '旧日记',
      );
      for (final d in drafts) {
        d.duplicate = keys.contains(d.fingerprint);
      }
      expect(drafts.length, 2);
      expect(drafts[0].duplicate, isTrue);
      expect(drafts[1].duplicate, isFalse);
    });

    test('toEntry 使用全新 ID 与识别到的日期', () {
      final drafts = splitDiaryText(
        '2024年5月1日 晴\n今天去公园散步了。',
        sourceName: '旧日记',
      );
      final e = drafts.first.toEntry(tags: ['导入']);
      expect(e.id, isNotEmpty);
      expect(e.createdAt, DateTime(2024, 5, 1));
      expect(e.updatedAt, DateTime(2024, 5, 1));
      expect(e.tags, ['导入']);
      expect(e.plainText, '今天去公园散步了。');
    });
  });

  group('日记导入 - 只新增不覆盖（仓库）', () {
    late Directory temp;
    late ProviderContainer container;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('allone_diary_import');
      container = ProviderContainer(
        overrides: [
          jsonStoreProvider.overrideWith((ref) async => JsonStore(temp)),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('导入后已有日记原样保留，ID 冲突时自动换新 ID', () async {
      final store = JsonStore(temp);
      final existing = _entry(
        id: '20240101090000-00001',
        title: '原有日记',
        text: '不能被改动',
      );
      await store.write('diary/entries/${existing.id}.json', existing.toJson());

      final notifier = container.read(diaryListProvider.notifier);
      final written = await notifier.importEntries([
        // 故意使用与现有日记相同的 ID，验证不会被覆盖
        _entry(id: existing.id, title: '导入日记', text: '新内容'),
        _entry(title: '导入日记2', text: '新内容2'),
      ]);
      expect(written, 2);

      final files = await store.listFiles('diary/entries');
      expect(files.length, 3); // 原有 1 篇 + 新导入 2 篇

      final kept = await store.read('diary/entries/${existing.id}.json');
      expect(kept!['title'], '原有日记');
      expect(kept['plainText'], '不能被改动');
    });

    test('导入列表包含既有日记（只增不减）', () async {
      final store = JsonStore(temp);
      await store.write(
        'diary/entries/keep.json',
        _entry(id: 'keep', title: '原有', text: '内容').toJson(),
      );

      final notifier = container.read(diaryListProvider.notifier);
      await notifier.importEntries([_entry(title: '新增', text: '导入内容')]);

      final list = await container.read(diaryListProvider.future);
      expect(list.length, 2);
      expect(list.any((e) => e.title == '原有'), isTrue);
      expect(list.any((e) => e.title == '新增'), isTrue);
    });

    test('批量导入 200 篇：ID 不冲突、文件数正确（Windows 时钟精度下也安全）', () async {
      final store = JsonStore(temp);
      final entries = [
        for (var i = 0; i < 200; i++) _entry(title: '第 $i 篇', text: '内容 $i'),
      ];
      final written = await container
          .read(diaryListProvider.notifier)
          .importEntries(entries);
      expect(written, 200);
      expect((await store.listFiles('diary/entries')).length, 200);
    });
  });

  group('日记导入 - ID 生成', () {
    test('连续批量生成 ID 不重复', () {
      final ids = {for (var i = 0; i < 3000; i++) AppPaths.newId()};
      expect(ids.length, 3000);
    });
  });
}
