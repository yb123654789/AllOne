import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/json_store.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/calendar/calendar_models.dart';
import 'package:allone/features/calendar/special_days_page.dart';
import 'package:allone/features/calendar/special_days_trash_page.dart';

/// 内存版 JsonStore。
///
/// widget 测试里**不能用真实文件 I/O**：`testWidgets` 用的是假时钟，
/// dart:io 的完成回调不会被推进，页面会永远停在 loading，
/// `pumpAndSettle` 于是空等（第一次就是这么卡住的）。
class _MemStore extends JsonStore {
  _MemStore() : super(Directory.systemTemp);

  final Map<String, Map<String, dynamic>> data = {};

  @override
  Future<Map<String, dynamic>?> read(String relativePath) async {
    final v = data[relativePath];
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  @override
  Future<void> write(String relativePath, Map<String, dynamic> json) async {
    data[relativePath] = Map<String, dynamic>.from(json);
  }
}

/// 倒数日页 / 回收站页的**界面接线**测试。
///
/// 纯逻辑与落盘已在另外两个测试文件里覆盖；这里测的是
/// 「进页触发 + 弹窗 + 按钮」这条链是否真的接上了 ——
/// 否则很容易出现「逻辑对了但根本没人调用」。
void main() {
  const rel = 'calendar/special_days.json';
  late _MemStore store;

  setUp(() {
    store = _MemStore();
  });

  Future<void> seed(List<SpecialDay> list) async {
    await store.write(rel, {
      'specialDays': list.map((e) => e.toJson()).toList(),
    });
  }

  /// 落地读取磁盘（内存）里那条记录
  Future<Map<String, dynamic>> stored(String id) async {
    final json = await store.read(rel);
    return (json!['specialDays'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['id'] == id);
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [jsonStoreProvider.overrideWith((ref) async => store)],
        child: MaterialApp(home: page),
      ),
    );
    // 上限 10 秒：真出问题就快速失败，而不是空等 10 分钟
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  testWidgets('过期单次项：进页弹窗 → 确认 → 归档并从列表消失（磁盘也写了）', (tester) async {
    await seed([
      // 用很早的日期，保证无论哪天跑都算「已过期」
      const SpecialDay(id: 'exam', date: '2020-01-01', name: '四级笔试'),
      const SpecialDay(id: 'live', date: '2099-01-01', name: '未来体测'),
    ]);

    await pumpPage(tester, const SpecialDaysPage());

    expect(find.text('有过期的日子'), findsOneWidget);
    expect(find.textContaining('四级笔试'), findsWidgets);

    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();

    expect(find.text('四级笔试'), findsNothing);
    expect(find.text('未来体测'), findsOneWidget);

    final exam = await stored('exam');
    expect(exam['archived'], isTrue);
    expect(exam['archivedAt'], isNotNull);
    // 归档不影响活动项
    expect((await stored('live'))['archived'], isFalse);
  });

  testWidgets('选「暂不处理」不归档，之后可用「全部归档」手动兜底', (tester) async {
    await seed([const SpecialDay(id: 'exam', date: '2020-01-01', name: '四级笔试')]);

    await pumpPage(tester, const SpecialDaysPage());
    await tester.tap(find.text('暂不处理'));
    await tester.pumpAndSettle();

    // 仍在「已经过去」里，且磁盘上没被归档
    expect(find.text('四级笔试'), findsOneWidget);
    expect(find.textContaining('已经过去'), findsOneWidget);
    expect((await stored('exam'))['archived'], isNot(true));

    await tester.tap(find.text('全部归档'));
    await tester.pumpAndSettle();

    expect(find.text('四级笔试'), findsNothing);
    expect((await stored('exam'))['archived'], isTrue);
  });

  testWidgets('每年重复项：进页自动推进，界面不再显示原始年份', (tester) async {
    await seed([
      const SpecialDay(
        id: 'b',
        date: '1998-03-12',
        name: '朋友生日',
        repeatYearly: true,
      ),
    ]);

    await pumpPage(tester, const SpecialDaysPage());

    expect(find.text('朋友生日'), findsOneWidget);
    expect(find.textContaining('每年重复'), findsOneWidget);
    // 推进后展示的是「下一次」的日期
    expect(find.textContaining('1998-03-12'), findsNothing);

    final b = await stored('b');
    expect(b['originDate'], '1998-03-12');
    expect(b['date'], isNot('1998-03-12'));
  });

  testWidgets('重复项：正好是今天 → 仍显示「今天」，不会被推到明年', (tester) async {
    final now = DateTime.now();
    final md =
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await seed([
      SpecialDay(id: 'b', date: '1998-$md', name: '今天生日', repeatYearly: true),
    ]);

    await pumpPage(tester, const SpecialDaysPage());

    expect(find.text('今天生日'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget); // 倒数文案
    // 对齐到今年，不跳明年
    expect((await stored('b'))['date'], '${now.year}-$md');
  });

  testWidgets('回收站页：列出已归档项，恢复后即离开回收站', (tester) async {
    await seed([
      const SpecialDay(
        id: 'exam',
        date: '2020-01-01',
        name: '四级笔试',
        archived: true,
        archivedAt: '2020-01-02',
      ),
    ]);

    await pumpPage(tester, const SpecialDaysTrashPage());
    expect(find.text('四级笔试'), findsOneWidget);
    expect(find.textContaining('归档于 2020-01-02'), findsOneWidget);

    await tester.tap(find.byTooltip('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('四级笔试'), findsNothing);
    expect((await stored('exam'))['archived'], isFalse);
  });

  testWidgets('倒数日页：回收站入口带数量角标', (tester) async {
    await seed([
      const SpecialDay(id: 'live', date: '2099-01-01', name: '未来体测'),
      const SpecialDay(
        id: 'old',
        date: '2020-01-01',
        name: '旧考试',
        archived: true,
        archivedAt: '2020-01-02',
      ),
    ]);

    await pumpPage(tester, const SpecialDaysPage());

    expect(find.byTooltip('回收站（1）'), findsOneWidget);
  });
}
