import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/backup/backup_service.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/todo/todo_repository.dart';

/// 备份选项 + 回收站清理的回归测试。
///
/// 这些是纯逻辑，不需要设备即可验证。
void main() {
  TodoItem item(String id, TodoStatus status, DateTime updatedAt) => TodoItem(
    id: id,
    title: id,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
  );

  group('回收站清理 - purgedItemIds', () {
    final now = DateTime(2026, 10, 6);
    final tree = [
      item('pending-old', TodoStatus.pending, DateTime(2020, 1, 1)),
      item(
        'done-recent',
        TodoStatus.done,
        now.subtract(const Duration(days: 1)),
      ),
      item('done-old', TodoStatus.done, now.subtract(const Duration(days: 40))),
      item(
        'archived-old',
        TodoStatus.archived,
        now.subtract(const Duration(days: 100)),
      ),
    ];

    test('before 为 null：清空整个回收站，但绝不动 pending', () {
      final ids = purgedItemIds(tree);
      expect(ids, containsAll(['done-recent', 'done-old', 'archived-old']));
      expect(ids, isNot(contains('pending-old')), reason: '未完成的待办永远不能被回收站清理删掉');
    });

    test('只清理早于阈值的条目', () {
      final before = now.subtract(const Duration(days: 30));
      final ids = purgedItemIds(tree, before: before);
      expect(ids, containsAll(['done-old', 'archived-old']));
      expect(ids, isNot(contains('done-recent')), reason: '阈值内的条目应保留');
    });

    test('阈值极早时什么都不删', () {
      final ids = purgedItemIds(tree, before: DateTime(2000, 1, 1));
      expect(ids, isEmpty);
    });

    test('空列表安全', () {
      expect(purgedItemIds([]), isEmpty);
      expect(purgedItemIds([], before: now), isEmpty);
    });
  });

  group('备份 - 临时文件判定', () {
    test('识别原子写入产物', () {
      expect(
        BackupService.isBackupTempArtifact(r'x\todo\items\a.json.tmp'),
        isTrue,
      );
      expect(
        BackupService.isBackupTempArtifact(
          r'x\diary\entries\a\media\p.jpg.tmp',
        ),
        isTrue,
      );
    });

    test('不误伤名字以 .tmp 结尾的真实文件', () {
      // 早期实现用 endsWith('.tmp')，会把这类文件从备份里静默丢掉
      expect(
        BackupService.isBackupTempArtifact(r'x\todo\items\a.tmp'),
        isFalse,
      );
      expect(
        BackupService.isBackupTempArtifact(r'x\diary\entries\a\media\录音.tmp'),
        isFalse,
      );
    });

    test('普通文件不受影响', () {
      expect(
        BackupService.isBackupTempArtifact(r'x\todo\items\a.json'),
        isFalse,
      );
      expect(
        BackupService.isBackupTempArtifact(r'x\diary\entries\a\media\p.jpg'),
        isFalse,
      );
    });
  });

  group('备份 - 附件日期解析', () {
    test('从毫秒时间戳前缀解析', () {
      // 1787658907441 ms ≈ 2026-08-25
      final d = BackupService.mediaDateFromName(
        r'diary\entries\a\media\1787658907441_1787658907069.jpg',
      );
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 8);
    });

    test('解析不出来时返回 null（调用方应保留该文件）', () {
      expect(BackupService.mediaDateFromName(r'x\media\照片.jpg'), isNull);
      expect(BackupService.mediaDateFromName(r'x\media\abc_1.jpg'), isNull);
      expect(BackupService.mediaDateFromName(r'x\media\999_1.jpg'), isNull);
    });
  });
}
