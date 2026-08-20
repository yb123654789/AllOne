import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/models/common.dart';
import 'package:allone/core/widgets/rich_text_editor.dart';
import 'package:allone/features/diary/diary_models.dart';
import 'package:allone/features/todo/todo_models.dart';
import 'package:allone/features/habit/habit_models.dart';

void main() {
  group('通用模型', () {
    test('MediaAttachment JSON 往返', () {
      const m = MediaAttachment(type: MediaType.photo, file: 'a.jpg', size: 123);
      final restored = MediaAttachment.fromJson(m.toJson());
      expect(restored.type, MediaType.photo);
      expect(restored.file, 'a.jpg');
      expect(restored.size, 123);
    });

    test('TimeStamp / LocationStamp JSON 往返', () {
      const ts = TimeStamp(enabled: true, nodeDate: '2027-02-20', pinTop: true);
      final ts2 = TimeStamp.fromJson(ts.toJson());
      expect(ts2.enabled, true);
      expect(ts2.nodeDate, '2027-02-20');
      expect(ts2.pinTop, true);

      const loc = LocationStamp(enabled: true, lat: 30.6, lng: 104.06, name: '家');
      final loc2 = LocationStamp.fromJson(loc.toJson());
      expect(loc2.lat, 30.6);
      expect(loc2.name, '家');
    });

    test('AppTime.dateOnly 格式化', () {
      expect(AppTime.dateOnly(DateTime(2026, 8, 20)), '2026-08-20');
    });
  });

  group('日记模型', () {
    test('DiaryEntry JSON 往返', () {
      final e = DiaryEntry(
        id: 'id1',
        title: '标题',
        contentDelta: '[]',
        plainText: '正文',
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20, 1),
        timeStamp: const TimeStamp(enabled: true, nodeDate: '2027-02-20'),
        tags: const ['生活'],
        media: const [MediaAttachment(type: MediaType.audio, file: 'r.m4a', size: 10)],
      );
      final restored = DiaryEntry.fromJson(e.toJson());
      expect(restored.id, 'id1');
      expect(restored.title, '标题');
      expect(restored.timeStamp.nodeDate, '2027-02-20');
      expect(restored.tags, ['生活']);
      expect(restored.media.length, 1);
      expect(restored.media.first.type, MediaType.audio);
    });
  });

  group('待办模型', () {
    test('TodoItem JSON 往返', () {
      final t = TodoItem(
        id: 't1',
        title: '任务',
        mode: TodoMode.rich,
        deadline: const DeadlineInfo(date: '2026-08-25', time: '18:00', color: '#E5484D', highlight: true),
        location: const LocationInfo(text: '图书馆', highlight: true),
        status: TodoStatus.pending,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      final restored = TodoItem.fromJson(t.toJson());
      expect(restored.deadline.date, '2026-08-25');
      expect(restored.deadline.highlight, true);
      expect(restored.location.text, '图书馆');
      expect(restored.status, TodoStatus.pending);
    });

    test('TaskChain 进度计算', () {
      final c = TaskChain(
        id: 'c1',
        title: '学习',
        subTasks: const [
          ChainSubTask(id: 's1', title: 'a', done: true),
          ChainSubTask(id: 's2', title: 'b', done: false),
          ChainSubTask(id: 's3', title: 'c', done: true),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(c.progress, closeTo(2 / 3, 0.0001));
    });
  });

  group('习惯模型', () {
    test('Habit JSON 往返', () {
      final h = Habit(
        id: 'h1',
        title: '阅读',
        category: '学习',
        target: const HabitTarget(type: HabitType.duration, value: 30),
        description: '每天读 30 分钟',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final restored = Habit.fromJson(h.toJson());
      expect(restored.target.type, HabitType.duration);
      expect(restored.target.value, 30);
    });

    test('CheckinMap 连续打卡统计', () {
      final cm = CheckinMap.fromJson({
        '2026-08-18': 1,
        '2026-08-19': 1,
        '2026-08-20': 1,
      });
      expect(cm.totalDays, 3);
      expect(cm.streakDays(DateTime(2026, 8, 20)), 3);
    });
  });

  group('富文本编解码', () {
    test('QuillCodec 空字符串返回空文档', () {
      final doc = QuillCodec.decode('');
      expect(doc.toPlainText().trim(), isEmpty);
    });
  });
}
