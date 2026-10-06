import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/json_store.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/diary/diary_models.dart';
import 'package:allone/features/diary/diary_repository.dart';
import 'package:allone/features/habit/habit_models.dart';
import 'package:allone/features/habit/habit_repository.dart';
import 'package:allone/features/ledger/ledger_models.dart';
import 'package:allone/features/ledger/ledger_repository.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/todo/todo_repository.dart';

/// 附件清理回归测试。
///
/// 背景：删除条目时若只删 JSON、不删 `media/` 目录，就会留下永远无法访问的
/// 孤立附件（真实数据中已发现多例：`todo/items/<id>/media/` 还留着照片，
/// 但 `<id>.json` 已不存在）。
/// 这几条测试锁死「删除条目必定连带清理附件目录」的行为。
void main() {
  late Directory temp;
  late ProviderContainer container;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('allone_media_cleanup');
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

  String p(String rel) => '${temp.path}${Platform.pathSeparator}$rel';

  /// 造一个附件文件
  void makeMedia(String rel) {
    final f = File(p(rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('x');
  }

  group('JsonStore.deleteDirectory', () {
    test('递归删除目录；目录不存在时幂等', () async {
      final store = JsonStore(temp);
      makeMedia('todo/items/a/media/pic.jpg');
      makeMedia('todo/items/a/media/deep/rec.m4a');
      expect(Directory(p('todo/items/a/media')).existsSync(), isTrue);

      await store.deleteDirectory('todo/items/a/media');
      expect(Directory(p('todo/items/a/media')).existsSync(), isFalse);

      // 再次删除不应抛异常
      await store.deleteDirectory('todo/items/a/media');
      expect(Directory(p('todo/items/a/media')).existsSync(), isFalse);
    });
  });

  group('待办 - 彻底删除清理附件', () {
    test('删除顶层待办时连同 media 目录一起删除', () async {
      final store = JsonStore(temp);
      final item = TodoItem(
        id: '20260101000000-00001',
        title: '待删除',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await store.write('todo/items/${item.id}.json', item.toJson());

      final notifier = container.read(todoListProvider.notifier);
      await container.read(todoListProvider.future); // 先载入 state

      makeMedia('todo/items/${item.id}/media/pic.jpg'); // 载入后再放附件
      await notifier.deleteItem(item.id);

      expect(
        File(p('todo/items/${item.id}.json')).existsSync(),
        isFalse,
        reason: '顶层 JSON 应被删除',
      );
      expect(
        File(p('todo/items/${item.id}/media/pic.jpg')).existsSync(),
        isFalse,
        reason: '附件不应残留',
      );
      expect(
        Directory(p('todo/items/${item.id}/media')).existsSync(),
        isFalse,
        reason: '附件目录应被清理',
      );
    });

    test('删除待办不影响其它待办的附件', () async {
      final store = JsonStore(temp);
      final a = TodoItem(
        id: '20260101000000-0000a',
        title: 'A',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final b = TodoItem(
        id: '20260101000000-0000b',
        title: 'B',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await store.write('todo/items/${a.id}.json', a.toJson());
      await store.write('todo/items/${b.id}.json', b.toJson());

      final notifier = container.read(todoListProvider.notifier);
      await container.read(todoListProvider.future); // 先载入 state

      makeMedia('todo/items/${a.id}/media/gone.jpg');
      makeMedia('todo/items/${b.id}/media/keep.jpg');
      await notifier.deleteItem(a.id);

      expect(
        File(p('todo/items/${b.id}/media/keep.jpg')).existsSync(),
        isTrue,
        reason: '其它待办的附件必须保留',
      );
      expect(File(p('todo/items/${b.id}.json')).existsSync(), isTrue);
      expect(File(p('todo/items/${a.id}.json')).existsSync(), isFalse);
    });

    test('删除子任务：父待办文件保留，子任务从父 JSON 移除', () async {
      final store = JsonStore(temp);
      final child = TodoItem(
        id: 'child-1',
        title: '子任务',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final parent = TodoItem(
        id: '20260101000000-0000p',
        title: '父待办',
        children: [child],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await store.write('todo/items/${parent.id}.json', parent.toJson());

      final notifier = container.read(todoListProvider.notifier);
      await container.read(todoListProvider.future); // 先载入 state
      await notifier.deleteItem(child.id);

      final kept = await store.read('todo/items/${parent.id}.json');
      expect(kept, isNotNull, reason: '父待办文件应保留');
      expect(kept!['children'], isEmpty, reason: '子任务应已从父 JSON 移除');
    });
  });

  group('日记导入 - 随附照片落盘', () {
    test('importEntries 写入图片文件并登记到 media 数组', () async {
      final store = JsonStore(temp);
      final e = DiaryEntry(
        id: '20260101000000-00009',
        title: '带照片',
        plainText: '正文',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final img1 = Uint8List.fromList(List<int>.filled(120, 7));
      final img2 = Uint8List.fromList(List<int>.filled(80, 9));

      final n = await container.read(diaryListProvider.notifier).importEntries([
        e,
      ], imagesOf: (_) => [img1, img2]);
      expect(n, 1);

      // media 数组登记了两张照片
      final json = await store.read('diary/entries/${e.id}.json');
      final media = (json!['media'] as List).cast<Map<String, dynamic>>();
      expect(media.length, 2);
      expect(media.every((m) => m['type'] == 'photo'), isTrue);

      // 文件真实存在，且大小与传入字节一致
      for (final m in media) {
        final f = File(p('diary/entries/${e.id}/media/${m['file']}'));
        expect(f.existsSync(), isTrue, reason: '照片文件应已落盘');
        expect(m['size'], f.lengthSync());
      }
      expect(Directory(p('diary/entries/${e.id}/media')).listSync().length, 2);
    });

    test('没有随附照片时行为不变（不影响原有导入）', () async {
      final store = JsonStore(temp);
      final e = DiaryEntry(
        id: '20260101000000-00010',
        title: '无照片',
        plainText: '正文',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await container.read(diaryListProvider.notifier).importEntries([e]);
      final json = await store.read('diary/entries/${e.id}.json');
      expect((json!['media'] as List), isEmpty);
    });
  });

  group('日记 - 删除清理附件', () {
    test('删除日记时连同 media 目录一起删除', () async {
      final store = JsonStore(temp);
      final e = DiaryEntry(
        id: '20260101000000-00001',
        title: '日记',
        plainText: '正文',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await store.write('diary/entries/${e.id}.json', e.toJson());

      final notifier = container.read(diaryListProvider.notifier);
      await container.read(diaryListProvider.future); // 先载入 state

      makeMedia('diary/entries/${e.id}/media/photo.jpg');
      await notifier.deleteEntry(e.id);

      expect(
        File(p('diary/entries/${e.id}/media/photo.jpg')).existsSync(),
        isFalse,
        reason: '日记附件不应残留',
      );
      expect(Directory(p('diary/entries/${e.id}/media')).existsSync(), isFalse);
      expect(File(p('diary/entries/${e.id}.json')).existsSync(), isFalse);
    });
  });

  group('习惯 - 删除清理附件', () {
    test('删除习惯时清理 media 目录与打卡记录', () async {
      final store = JsonStore(temp);
      final h = Habit(
        id: '20260101000000-00001',
        title: '习惯',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await store.write('habit/habits/${h.id}.json', h.toJson());
      await store.writeText('habit/checkins/${h.id}.json', '{}');

      final notifier = container.read(habitListProvider.notifier);
      await container.read(habitListProvider.future); // 先载入 state

      makeMedia('habit/habits/${h.id}/media/pic.jpg');
      await notifier.deleteHabit(h.id);

      expect(
        File(p('habit/habits/${h.id}/media/pic.jpg')).existsSync(),
        isFalse,
        reason: '习惯附件不应残留',
      );
      expect(Directory(p('habit/habits/${h.id}/media')).existsSync(), isFalse);
      expect(File(p('habit/checkins/${h.id}.json')).existsSync(), isFalse);
    });
  });

  group('待办 - 数据未加载时不得清空磁盘', () {
    // 背景：`_persist` 会重写全部顶层文件，并把不在列表里的文件删掉。
    // 修复前各写操作取的是 `state.valueOrNull ?? []`，
    // 于是在「provider 还没加载完」时做任何一次写操作，
    // 都会把磁盘上所有待办当成「已删除」而清空。
    // 这组测试锁死：写操作会先等待数据加载，绝不拿空列表去覆盖。

    Future<void> seed(String id) async {
      final store = JsonStore(temp);
      await store.write(
        'todo/items/$id.json',
        TodoItem(
          id: id,
          title: id,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ).toJson(),
      );
    }

    test('未加载时 saveItem：既有待办必须保留', () async {
      // 刻意**不**先 read provider（模拟"刚打开 App 就保存"）
      await seed('existing-a');
      await seed('existing-b');

      await container
          .read(todoListProvider.notifier)
          .saveItem(
            TodoItem(
              id: 'brand-new',
              title: '新条目',
              createdAt: DateTime(2026, 1, 2),
              updatedAt: DateTime(2026, 1, 2),
            ),
          );

      expect(
        File(p('todo/items/existing-a.json')).existsSync(),
        isTrue,
        reason: '未加载就保存，不能把既有待办删掉',
      );
      expect(File(p('todo/items/existing-b.json')).existsSync(), isTrue);
      expect(File(p('todo/items/brand-new.json')).existsSync(), isTrue);

      final list = await container.read(todoListProvider.future);
      expect(list.map((e) => e.id).toSet(), {
        'existing-a',
        'existing-b',
        'brand-new',
      });
    });

    test('未加载时 deleteItem：只删目标，其余保留', () async {
      await seed('keep-1');
      await seed('keep-2');
      await seed('remove-me');

      await container.read(todoListProvider.notifier).deleteItem('remove-me');

      expect(File(p('todo/items/remove-me.json')).existsSync(), isFalse);
      expect(
        File(p('todo/items/keep-1.json')).existsSync(),
        isTrue,
        reason: '删除一条不应波及其它待办',
      );
      expect(File(p('todo/items/keep-2.json')).existsSync(), isTrue);
    });

    test('未加载时 setStatus：既有待办必须保留', () async {
      await seed('t1');
      await seed('t2');

      await container
          .read(todoListProvider.notifier)
          .setStatus('t1', TodoStatus.done);

      expect(File(p('todo/items/t1.json')).existsSync(), isTrue);
      expect(
        File(p('todo/items/t2.json')).existsSync(),
        isTrue,
        reason: '勾选完成不应删除其它待办',
      );
      final list = await container.read(todoListProvider.future);
      expect(list.length, 2);
    });
  });

  group('记账 - 删除账户连带清理流水', () {
    test('删除账户会删掉该账户全部流水，且不影响其它账户', () async {
      final store = JsonStore(temp);
      const accA = '20260101000000-0000a';
      const accB = '20260101000000-0000b';

      await store.write(
        'ledger/accounts/$accA.json',
        const LedgerAccount(id: accA, name: '甲').toJson(),
      );
      await store.write(
        'ledger/accounts/$accB.json',
        const LedgerAccount(id: accB, name: '乙').toJson(),
      );

      // 甲有两个月的流水，乙有一个月的流水
      await store.write(
        'ledger/transactions/${accA}_2026-09.json',
        const MonthlyRecords(
          accountId: accA,
          month: '2026-09',
          records: [
            Transaction(
              id: 't1',
              accountId: accA,
              date: '2026-09-01',
              type: TxType.expense,
              amount: 10,
            ),
          ],
        ).toJson(),
      );
      await store.write(
        'ledger/transactions/${accA}_2026-10.json',
        const MonthlyRecords(
          accountId: accA,
          month: '2026-10',
          records: [
            Transaction(
              id: 't2',
              accountId: accA,
              date: '2026-10-02',
              type: TxType.expense,
              amount: 20,
            ),
          ],
        ).toJson(),
      );
      await store.write(
        'ledger/transactions/${accB}_2026-09.json',
        const MonthlyRecords(
          accountId: accB,
          month: '2026-09',
          records: [
            Transaction(
              id: 't3',
              accountId: accB,
              date: '2026-09-03',
              type: TxType.income,
              amount: 30,
            ),
          ],
        ).toJson(),
      );

      final notifier = container.read(accountListProvider.notifier);
      await container.read(accountListProvider.future); // 先载入 state
      await notifier.deleteAccount(accA);

      // 账户文件已删
      expect(File(p('ledger/accounts/$accA.json')).existsSync(), isFalse);
      // 甲的流水全部删除（两个月份都不能残留）
      expect(
        File(p('ledger/transactions/${accA}_2026-09.json')).existsSync(),
        isFalse,
        reason: '被删账户的流水必须一并删除，否则会成为加载不出来的孤立文件',
      );
      expect(
        File(p('ledger/transactions/${accA}_2026-10.json')).existsSync(),
        isFalse,
      );
      // 乙的账户与流水都必须保留
      expect(File(p('ledger/accounts/$accB.json')).existsSync(), isTrue);
      expect(
        File(p('ledger/transactions/${accB}_2026-09.json')).existsSync(),
        isTrue,
        reason: '不能误删其它账户的流水',
      );
    });

    test('删除账户后流水视图不再包含其记录', () async {
      final store = JsonStore(temp);
      const acc = '20260101000000-0000c';
      await store.write(
        'ledger/accounts/$acc.json',
        const LedgerAccount(id: acc, name: '丙').toJson(),
      );
      await store.write(
        'ledger/transactions/${acc}_2026-09.json',
        const MonthlyRecords(
          accountId: acc,
          month: '2026-09',
          records: [
            Transaction(
              id: 't9',
              accountId: acc,
              date: '2026-09-05',
              type: TxType.expense,
              amount: 5,
            ),
          ],
        ).toJson(),
      );

      final notifier = container.read(accountListProvider.notifier);
      expect((await container.read(transactionListProvider.future)).length, 1);

      await notifier.deleteAccount(acc);

      expect(
        (await container.read(transactionListProvider.future)).length,
        0,
        reason: '账户删除后，其流水不应再出现在列表里',
      );
      expect(
        await store.read('ledger/transactions/${acc}_2026-09.json'),
        isNull,
      );
    });
  });
}
