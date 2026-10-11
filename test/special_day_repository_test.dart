import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/storage/json_store.dart';
import 'package:allone/core/storage/storage_providers.dart';
import 'package:allone/features/calendar/calendar_models.dart';
import 'package:allone/features/calendar/calendar_repository.dart';

/// 倒数日生命周期的**落盘**测试。
///
/// 纯逻辑在 `special_day_lifecycle_test.dart` 里测；这里测的是：
/// 推进 / 归档 / 恢复 / 清空是否真的写进了 `calendar/special_days.json`，
/// 以及重启（新容器）后是否仍然生效 —— 还有那条最危险的：
/// **数据没加载完就写，会不会把整份文件覆盖成空**。
void main() {
  late Directory temp;
  late ProviderContainer container;
  const today = '2026-10-11';
  const rel = 'calendar/special_days.json';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('allone_special_days');
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

  SpecialDayListNotifier notifier() =>
      container.read(specialDayListProvider.notifier);

  File file() => File('${temp.path}${Platform.pathSeparator}$rel');

  Future<void> seed(List<SpecialDay> list) async {
    await JsonStore(temp).write(rel, {
      'specialDays': list.map((e) => e.toJson()).toList(),
    });
  }

  /// 模拟「重启 App」：全新容器 + 全新存储，从磁盘重新读
  Future<List<SpecialDay>> reload() async {
    final fresh = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWith((ref) async => JsonStore(temp)),
      ],
    );
    addTearDown(fresh.dispose);
    return fresh.read(specialDayListProvider.future);
  }

  test('推进重复项：写盘生效，重启后读到的是下一次的日期', () async {
    await seed([
      const SpecialDay(
        id: 'b',
        date: '2000-03-12',
        name: '生日',
        repeatYearly: true,
      ),
      const SpecialDay(id: 'on', date: '2026-10-12', name: '考试'),
    ]);
    await container.read(specialDayListProvider.future);

    final n = await notifier().advanceRecurring(today: today);
    expect(n, 1, reason: '只有那条每年重复的需要推进');

    final list = await reload();
    final birthday = list.firstWhere((e) => e.id == 'b');
    expect(birthday.date, '2027-03-12');
    expect(birthday.originDate, '2000-03-12');
    expect(birthday.anniversaryYears(today), 27);
    // 单次项不受影响
    expect(list.firstWhere((e) => e.id == 'on').date, '2026-10-12');
  });

  test('推进无变化时不写盘（文件没有被重写）', () async {
    await seed([
      const SpecialDay(
        id: 'b',
        date: '2027-03-12',
        originDate: '2000-03-12',
        repeatYearly: true,
      ),
    ]);
    await container.read(specialDayListProvider.future);

    final before = file().lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final n = await notifier().advanceRecurring(today: today);

    expect(n, 0);
    expect(file().lastModifiedSync(), before, reason: '无变化就不该碰文件');
  });

  test('归档过期单次项：进回收站、退出活动列表，重启后仍然如此', () async {
    await seed([
      const SpecialDay(id: 'exam', date: '2026-10-01', name: '四级笔试'),
      const SpecialDay(id: 'live', date: '2026-10-20', name: '体测'),
    ]);
    await container.read(specialDayListProvider.future);

    final pending = await notifier().pendingArchive(today: today);
    expect(pending.map((e) => e.id), ['exam']);

    final archived = await notifier().archiveExpired(['exam'], today: today);
    expect(archived, 1);

    final list = await reload();
    final exam = list.firstWhere((e) => e.id == 'exam');
    expect(exam.archived, isTrue);
    expect(exam.archivedAt, today);
    // 活动列表（日历 / 倒数日页用的）里不再有它
    expect(list.where((e) => !e.archived).map((e) => e.id), ['live']);
  });

  test('恢复：从回收站回到活动列表，日期不变', () async {
    await seed([
      const SpecialDay(
        id: 'exam',
        date: '2026-10-01',
        name: '四级笔试',
        archived: true,
        archivedAt: '2026-10-05',
      ),
    ]);
    await container.read(specialDayListProvider.future);

    await notifier().restore('exam');

    final list = await reload();
    expect(list.single.archived, isFalse);
    expect(list.single.archivedAt, isNull);
    expect(list.single.date, '2026-10-01');
  });

  test('清空回收站：只删已归档的，活动项一个不动', () async {
    await seed([
      const SpecialDay(
        id: 'a',
        date: '2026-10-01',
        archived: true,
        archivedAt: '2026-10-05',
      ),
      const SpecialDay(
        id: 'b',
        date: '2026-10-02',
        archived: true,
        archivedAt: '2026-10-06',
      ),
      const SpecialDay(id: 'live', date: '2026-10-20'),
    ]);
    await container.read(specialDayListProvider.future);

    expect(await notifier().purgeAll(), 2);

    final list = await reload();
    expect(list.map((e) => e.id).toList(), ['live']);
  });

  test('没有加载完就写，不会把已有数据覆盖成空（防整表清空）', () async {
    await seed([
      const SpecialDay(id: 'old1', date: '2000-03-12', repeatYearly: true),
      const SpecialDay(id: 'old2', date: '2026-10-01', name: '旧考试'),
    ]);
    // 关键：**故意不读 provider**，直接写 —— 这正是「刚打开 App 就操作」的场景
    await notifier().save(
      const SpecialDay(id: 'new', date: '2027-01-01', name: '新加的'),
    );

    final json = await JsonStore(temp).read(rel);
    final ids = (json!['specialDays'] as List)
        .map((e) => (e as Map)['id'] as String)
        .toList();
    expect(ids, containsAll(['old1', 'old2', 'new']));
    expect(ids.length, 3);
  });
}
